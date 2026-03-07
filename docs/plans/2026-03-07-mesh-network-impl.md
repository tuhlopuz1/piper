# Mesh Network Layer — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Go overlay mesh network (`go/mesh/`) that transparently routes libwebrtc DTLS/SRTP media through multi-hop P2P paths using source routing, while preserving existing messaging/discovery untouched.

**Architecture:** `mesh/transport/` defines a push-based Link interface; `mesh/router/` runs Dijkstra with EMA-smoothed metrics and 25% hysteresis; `mesh/proxy/` opens a localhost UDP socket per call, terminates ICE STUN with `pion/stun`, and passes DTLS/SRTP into the mesh. Cutover in Phase 5 replaces `core.Node` with `mesh.Node` in the FFI bridge without changing any exported signatures.

**Tech Stack:** Go 1.22, `github.com/pion/stun/v2`, `github.com/vmihailenco/msgpack/v5`, `flutter_webrtc`, Flutter MethodChannel, Android `WifiP2pManager`

**Design doc:** `docs/plans/2026-03-07-mesh-network-design.md` — read it before starting.

---

## Phase 1 — Transport Layer (`mesh/transport/`)

### Task 1: Link interface + constants

**Files:**
- Create: `go/mesh/transport/link.go`
- Create: `go/mesh/transport/link_test.go`

**Step 1: Create the interface file**

```go
// go/mesh/transport/link.go
package transport

import "time"

type LinkQuality struct {
    RTT       time.Duration
    LossRatio float32 // 0.0–1.0, EMA-smoothed
    Bandwidth int64   // bytes/sec
}

type Link interface {
    ID() string
    PeerID() string
    Send(pkt []byte) error
    SetOnReceive(handler func(pkt []byte))
    Quality() LinkQuality
    Close()
}
```

**Step 2: Write the failing test (mock Link)**

```go
// go/mesh/transport/link_test.go
package transport_test

import (
    "testing"
    "github.com/catsi/piper/mesh/transport"
)

// MockLink for use in other package tests
type MockLink struct {
    id      string
    peerID  string
    sent    [][]byte
    handler func([]byte)
    quality transport.LinkQuality
}

func (m *MockLink) ID() string                          { return m.id }
func (m *MockLink) PeerID() string                      { return m.peerID }
func (m *MockLink) Send(pkt []byte) error               { m.sent = append(m.sent, pkt); return nil }
func (m *MockLink) SetOnReceive(h func([]byte))         { m.handler = h }
func (m *MockLink) Quality() transport.LinkQuality      { return m.quality }
func (m *MockLink) Close()                              {}

func (m *MockLink) Deliver(pkt []byte) { // simulate incoming packet
    if m.handler != nil { m.handler(pkt) }
}

func TestMockLinkImplementsLink(t *testing.T) {
    var _ transport.Link = &MockLink{}
}
```

**Step 3: Run test**

```bash
cd go && go test ./mesh/transport/... -v
```
Expected: PASS (interface check only)

**Step 4: Commit**

```bash
git add go/mesh/transport/
git commit -m "feat(mesh): add Link interface and transport package"
```

---

### Task 2: Wire format — packet encoding/decoding

**Files:**
- Create: `go/mesh/transport/packet.go`
- Create: `go/mesh/transport/packet_test.go`

**Step 1: Write failing tests**

```go
// go/mesh/transport/packet_test.go
package transport_test

import (
    "testing"
    "github.com/catsi/piper/mesh/transport"
)

func TestEncodeDecodeDataPacket(t *testing.T) {
    src  := uint32(0xAABBCCDD)
    dst  := uint32(0x11223344)
    hops := []uint32{0xDEADBEEF, 0xCAFEBABE}
    payload := []byte("hello mesh")

    buf := make([]byte, transport.MeshHeaderMaxLen+len(payload)+128)
    n := transport.EncodeDataPacket(buf, src, dst, hops, payload)

    pkt := buf[:n]
    if pkt[1] != 0 { t.Fatalf("current_hop_idx want 0 got %d", pkt[1]) }
    if int(pkt[2]) != len(hops) { t.Fatalf("hop_count want %d got %d", len(hops), pkt[2]) }

    gotSrc := transport.ReadSrcHash(pkt)
    if gotSrc != src { t.Fatalf("src want %x got %x", src, gotSrc) }

    gotDst := transport.ReadDstHash(pkt)
    if gotDst != dst { t.Fatalf("dst want %x got %x", dst, gotDst) }

    gotPayload := transport.ExtractPayload(pkt)
    if string(gotPayload) != "hello mesh" {
        t.Fatalf("payload want 'hello mesh' got %q", gotPayload)
    }
}

func TestForwardIncrementHopIdx(t *testing.T) {
    buf := make([]byte, 256)
    hops := []uint32{0xAAAA, 0xBBBB, 0xCCCC}
    n := transport.EncodeDataPacket(buf, 0x1, 0x3, hops, []byte("data"))
    pkt := buf[:n]

    if pkt[1] != 0 { t.Fatal("initial hop idx must be 0") }
    transport.IncrementHopIdx(pkt)
    if pkt[1] != 1 { t.Fatal("after increment hop idx must be 1") }
}

func TestNextHopHash(t *testing.T) {
    buf := make([]byte, 256)
    hops := []uint32{0xAAAA, 0xBBBB, 0xCCCC}
    n := transport.EncodeDataPacket(buf, 0x1, 0x3, hops, []byte("x"))
    pkt := buf[:n]

    got := transport.NextHopHash(pkt)
    if got != hops[1] { t.Fatalf("want %x got %x", hops[1], got) }
}
```

**Step 2: Run to confirm failure**

```bash
cd go && go test ./mesh/transport/... -v -run TestEncode
```
Expected: compile error — functions not defined.

**Step 3: Implement**

```go
// go/mesh/transport/packet.go
package transport

import "encoding/binary"

const (
    MeshHeaderMaxLen = 64
    HopsOffset       = 11 // bytes before hops[] in header

    TypeData     = byte(0x00)
    TypeGossip   = byte(0x10)
    TypeProbe    = byte(0x30)
    TypeProbeAck = byte(0x40)
)

// EncodeDataPacket writes a mesh DATA packet into buf starting at
// buf[MeshHeaderMaxLen - headerLen]. Returns total packet length.
// buf must be at least MeshHeaderMaxLen + len(payload) + 128 bytes.
func EncodeDataPacket(buf []byte, src, dst uint32, hops []uint32, payload []byte) int {
    hdrLen := HopsOffset + len(hops)*4 + 2 // +2 for payload_len field
    start := MeshHeaderMaxLen - hdrLen

    // Copy payload into position (already there if using headroom pattern)
    copy(buf[MeshHeaderMaxLen:], payload)

    h := buf[start:MeshHeaderMaxLen]
    h[0] = TypeData
    h[1] = 0 // current_hop_idx
    h[2] = byte(len(hops))
    binary.BigEndian.PutUint32(h[3:], src)
    binary.BigEndian.PutUint32(h[7:], dst)
    for i, hop := range hops {
        binary.BigEndian.PutUint32(h[HopsOffset+i*4:], hop)
    }
    plenOff := HopsOffset + len(hops)*4
    binary.BigEndian.PutUint16(h[plenOff:], uint16(len(payload)))

    return hdrLen + len(payload)
}

func ReadSrcHash(pkt []byte) uint32   { return binary.BigEndian.Uint32(pkt[3:]) }
func ReadDstHash(pkt []byte) uint32   { return binary.BigEndian.Uint32(pkt[7:]) }
func CurrentHopIdx(pkt []byte) byte   { return pkt[1] }
func HopCount(pkt []byte) byte        { return pkt[2] }
func IncrementHopIdx(pkt []byte)      { pkt[1]++ }

func NextHopHash(pkt []byte) uint32 {
    idx := int(pkt[1])
    return binary.BigEndian.Uint32(pkt[HopsOffset+(idx+1)*4:])
}

func ExtractPayload(pkt []byte) []byte {
    hopCount := int(pkt[2])
    plenOff := HopsOffset + hopCount*4
    plen := binary.BigEndian.Uint16(pkt[plenOff:])
    return pkt[plenOff+2 : plenOff+2+int(plen)]
}
```

**Step 4: Run tests**

```bash
cd go && go test ./mesh/transport/... -v
```
Expected: all PASS.

**Step 5: Commit**

```bash
git add go/mesh/transport/packet.go go/mesh/transport/packet_test.go
git commit -m "feat(mesh): wire format encode/decode with zero-copy headroom"
```

---

### Task 3: TCP Link implementation

**Files:**
- Create: `go/mesh/transport/tcp_link.go`
- Create: `go/mesh/transport/tcp_link_test.go`

**Step 1: Write failing integration test**

```go
// go/mesh/transport/tcp_link_test.go
package transport_test

import (
    "net"
    "sync"
    "testing"
    "time"
    "github.com/catsi/piper/mesh/transport"
)

func TestTCPLinkSendReceive(t *testing.T) {
    ln, err := net.Listen("tcp", "127.0.0.1:0")
    if err != nil { t.Fatal(err) }
    defer ln.Close()

    var wg sync.WaitGroup
    received := make(chan []byte, 1)

    // Server side
    wg.Add(1)
    go func() {
        defer wg.Done()
        conn, _ := ln.Accept()
        serverLink := transport.NewTCPLink("server", "client", conn)
        serverLink.SetOnReceive(func(pkt []byte) {
            cp := make([]byte, len(pkt))
            copy(cp, pkt)
            received <- cp
        })
        serverLink.Start()
        <-time.After(2 * time.Second)
        serverLink.Close()
    }()

    // Client side
    conn, err := net.Dial("tcp", ln.Addr().String())
    if err != nil { t.Fatal(err) }
    clientLink := transport.NewTCPLink("client", "server", conn)
    clientLink.Start()

    msg := []byte("ping from client")
    if err := clientLink.Send(msg); err != nil { t.Fatal(err) }

    select {
    case got := <-received:
        if string(got) != string(msg) {
            t.Fatalf("want %q got %q", msg, got)
        }
    case <-time.After(3 * time.Second):
        t.Fatal("timeout waiting for message")
    }

    clientLink.Close()
    wg.Wait()
}
```

**Step 2: Run to confirm failure**

```bash
cd go && go test ./mesh/transport/... -v -run TestTCP
```
Expected: compile error.

**Step 3: Implement TCP Link**

```go
// go/mesh/transport/tcp_link.go
package transport

import (
    "encoding/binary"
    "io"
    "net"
    "sync"
)

const tcpMagic = uint32(0x50495052) // "PIPR"

type TCPLink struct {
    id      string
    peerID  string
    conn    net.Conn
    handler func([]byte)
    pool    sync.Pool
    mu      sync.Mutex
    quality LinkQuality
    done    chan struct{}
}

func NewTCPLink(id, peerID string, conn net.Conn) *TCPLink {
    l := &TCPLink{
        id:     id,
        peerID: peerID,
        conn:   conn,
        done:   make(chan struct{}),
    }
    l.pool.New = func() any { b := make([]byte, 65600); return &b }
    return l
}

func (l *TCPLink) ID() string                    { return l.id }
func (l *TCPLink) PeerID() string                { return l.peerID }
func (l *TCPLink) Quality() LinkQuality          { l.mu.Lock(); defer l.mu.Unlock(); return l.quality }
func (l *TCPLink) SetOnReceive(h func([]byte))   { l.mu.Lock(); l.handler = h; l.mu.Unlock() }

func (l *TCPLink) Start() { go l.readLoop() }

func (l *TCPLink) Send(pkt []byte) error {
    // Frame: [4 magic][4 length][payload]
    hdr := make([]byte, 8)
    binary.BigEndian.PutUint32(hdr[0:], tcpMagic)
    binary.BigEndian.PutUint32(hdr[4:], uint32(len(pkt)))
    l.mu.Lock()
    defer l.mu.Unlock()
    if _, err := l.conn.Write(hdr); err != nil { return err }
    _, err := l.conn.Write(pkt)
    return err
}

func (l *TCPLink) Close() {
    select {
    case <-l.done:
    default:
        close(l.done)
    }
    l.conn.Close()
}

func (l *TCPLink) readLoop() {
    hdr := make([]byte, 8)
    for {
        if _, err := io.ReadFull(l.conn, hdr); err != nil { return }
        if binary.BigEndian.Uint32(hdr[0:]) != tcpMagic { return }
        n := binary.BigEndian.Uint32(hdr[4:])
        if n > 65535 { return }

        bufPtr := l.pool.Get().(*[]byte)
        buf := (*bufPtr)[:n]
        if _, err := io.ReadFull(l.conn, buf); err != nil {
            l.pool.Put(bufPtr)
            return
        }

        l.mu.Lock()
        h := l.handler
        l.mu.Unlock()
        if h != nil { h(buf) }
        l.pool.Put(bufPtr)
    }
}
```

**Step 4: Run tests**

```bash
cd go && go test ./mesh/transport/... -v -race
```
Expected: all PASS, no races.

**Step 5: Commit**

```bash
git add go/mesh/transport/tcp_link.go go/mesh/transport/tcp_link_test.go
git commit -m "feat(mesh): TCP link with magic-framed send/receive"
```

---

## Phase 2 — Gossip + Router (`mesh/router/`)

### Task 4: Peer table with CRDT merge

**Files:**
- Create: `go/mesh/router/peer_table.go`
- Create: `go/mesh/router/peer_table_test.go`

**Step 1: Add msgpack dependency**

```bash
cd go && go get github.com/vmihailenco/msgpack/v5
```

**Step 2: Write failing tests**

```go
// go/mesh/router/peer_table_test.go
package router_test

import (
    "testing"
    "github.com/catsi/piper/mesh/router"
)

func TestUpsertNewPeer(t *testing.T) {
    pt := router.NewPeerTable("self-id")
    peer := router.MeshPeer{ID: "peer-a", HashID: 0xAAAA, Name: "Alice", Version: 1}
    changed := pt.Merge(peer)
    if !changed { t.Fatal("new peer should trigger changed=true") }
    got := pt.Get("peer-a")
    if got == nil { t.Fatal("peer not found after merge") }
}

func TestMergeRejectsOlderVersion(t *testing.T) {
    pt := router.NewPeerTable("self")
    pt.Merge(router.MeshPeer{ID: "b", HashID: 0xBB, Version: 5})
    changed := pt.Merge(router.MeshPeer{ID: "b", HashID: 0xBB, Version: 3})
    if changed { t.Fatal("older version must not overwrite") }
}

func TestMergeAcceptsNewerVersion(t *testing.T) {
    pt := router.NewPeerTable("self")
    pt.Merge(router.MeshPeer{ID: "c", HashID: 0xCC, Version: 1})
    changed := pt.Merge(router.MeshPeer{ID: "c", HashID: 0xCC, Version: 2})
    if !changed { t.Fatal("newer version must be accepted") }
}

func TestGetByHash(t *testing.T) {
    pt := router.NewPeerTable("self")
    pt.Merge(router.MeshPeer{ID: "d", HashID: 0xDDDD, Version: 1})
    got := pt.GetByHash(0xDDDD)
    if got == nil || got.ID != "d" {
        t.Fatalf("GetByHash failed, got %v", got)
    }
}
```

**Step 3: Run to confirm failure**

```bash
cd go && go test ./mesh/router/... -v -run TestUpsert
```
Expected: compile error.

**Step 4: Implement**

```go
// go/mesh/router/peer_table.go
package router

import (
    "hash/crc32"
    "sync"
    "time"
)

func HashID(uuid string) uint32 {
    return crc32.ChecksumIEEE([]byte(uuid))
}

type LinkAddr struct {
    Type string // "tcp", "wifidirect", "ble"
    IP   string
    Port int
}

type LinkEntry struct {
    PeerHashID uint32
    RTTms      float64 // EMA-smoothed milliseconds
    LossRatio  float32 // EMA-smoothed 0.0–1.0
}

type MeshPeer struct {
    ID       string      `msgpack:"id"`
    HashID   uint32      `msgpack:"h"`
    Name     string      `msgpack:"n"`
    Addrs    []LinkAddr  `msgpack:"a"`
    Links    []LinkEntry `msgpack:"l"`
    Version  uint64      `msgpack:"v"` // only incremented by the owner
    LastSeen time.Time   `msgpack:"t"`
}

type PeerTable struct {
    localID string
    mu      sync.RWMutex
    byID    map[string]*MeshPeer
    byHash  map[uint32]*MeshPeer
}

func NewPeerTable(localID string) *PeerTable {
    return &PeerTable{
        localID: localID,
        byID:    make(map[string]*MeshPeer),
        byHash:  make(map[uint32]*MeshPeer),
    }
}

// Merge applies a remote peer record. Returns true if the table changed.
// Rule: accept only if received.Version > local.Version (CRDT-style).
// Never increment another peer's Version.
func (pt *PeerTable) Merge(p MeshPeer) bool {
    if p.ID == pt.localID { return false }
    pt.mu.Lock()
    defer pt.mu.Unlock()

    if existing, ok := pt.byID[p.ID]; ok {
        if p.Version <= existing.Version { return false }
    }
    p.LastSeen = time.Now()
    cp := p
    pt.byID[p.ID] = &cp
    pt.byHash[p.HashID] = &cp
    return true
}

func (pt *PeerTable) Get(id string) *MeshPeer {
    pt.mu.RLock(); defer pt.mu.RUnlock()
    return pt.byID[id]
}

func (pt *PeerTable) GetByHash(h uint32) *MeshPeer {
    pt.mu.RLock(); defer pt.mu.RUnlock()
    return pt.byHash[h]
}

func (pt *PeerTable) All() []MeshPeer {
    pt.mu.RLock(); defer pt.mu.RUnlock()
    out := make([]MeshPeer, 0, len(pt.byID))
    for _, p := range pt.byID { out = append(out, *p) }
    return out
}
```

**Step 5: Run tests**

```bash
cd go && go test ./mesh/router/... -v -race
```
Expected: all PASS.

**Step 6: Commit**

```bash
git add go/mesh/router/
git commit -m "feat(mesh): peer table with CRDT version merge"
```

---

### Task 5: Dijkstra route computation with hysteresis

**Files:**
- Create: `go/mesh/router/route.go`
- Create: `go/mesh/router/route_test.go`

**Step 1: Write failing tests**

```go
// go/mesh/router/route_test.go
package router_test

import (
    "testing"
    "github.com/catsi/piper/mesh/router"
)

// Graph: A --10ms--> B --10ms--> C
// A --100ms--> C (direct but worse)
// Dijkstra should find A→B→C with lower weight

func TestDijkstraFindsShortestPath(t *testing.T) {
    pt := router.NewPeerTable("A")
    pt.Merge(router.MeshPeer{
        ID: "B", HashID: 0xBB, Version: 1,
        Links: []router.LinkEntry{
            {PeerHashID: 0xAA, RTTms: 10, LossRatio: 0},
            {PeerHashID: 0xCC, RTTms: 10, LossRatio: 0},
        },
    })
    pt.Merge(router.MeshPeer{
        ID: "C", HashID: 0xCC, Version: 1,
        Links: []router.LinkEntry{
            {PeerHashID: 0xBB, RTTms: 10, LossRatio: 0},
        },
    })

    // local links from A
    localLinks := map[uint32]router.LinkEntry{
        0xBB: {PeerHashID: 0xBB, RTTms: 10, LossRatio: 0},
        0xCC: {PeerHashID: 0xCC, RTTms: 100, LossRatio: 0},
    }

    route := router.Dijkstra(0xAA, 0xCC, pt, localLinks)
    if route == nil { t.Fatal("expected route, got nil") }
    if len(route.Hops) != 2 { t.Fatalf("want 2 hops [B,C] got %v", route.Hops) }
    if route.Hops[0] != 0xBB { t.Fatalf("first hop want B(0xBB) got %x", route.Hops[0]) }
}

func TestDijkstraReturnsNilWhenNoPath(t *testing.T) {
    pt := router.NewPeerTable("A")
    route := router.Dijkstra(0xAA, 0xFF, pt, nil)
    if route != nil { t.Fatal("expected nil route for unreachable peer") }
}

func TestEdgeWeight(t *testing.T) {
    // 5% loss → 5%² × 10000 = 25, RTT=50ms, tcp=0 → weight=75
    w := router.EdgeWeight(50, 0.05, "tcp")
    if w < 74 || w > 76 { t.Fatalf("want ~75 got %f", w) }

    // 15% loss → 15%² × 10000 = 225, RTT=50ms → weight=275
    w2 := router.EdgeWeight(50, 0.15, "tcp")
    if w2 < 274 || w2 > 276 { t.Fatalf("want ~275 got %f", w2) }
}

func TestHysteresisBlocksMinorImprovement(t *testing.T) {
    current := &router.Route{Score: 100}
    candidate := &router.Route{Score: 115} // only 13% better — below 25% threshold
    if router.ShouldSwitch(current, candidate) {
        t.Fatal("should not switch for <25% improvement")
    }
}

func TestHysteresisAllowsMajorImprovement(t *testing.T) {
    current := &router.Route{Score: 100}
    candidate := &router.Route{Score: 60} // 40% better — above threshold
    if !router.ShouldSwitch(current, candidate) {
        t.Fatal("should switch for >25% improvement")
    }
}
```

**Step 2: Run to confirm failure**

```bash
cd go && go test ./mesh/router/... -v -run TestDijkstra
```
Expected: compile errors.

**Step 3: Implement**

```go
// go/mesh/router/route.go
package router

import (
    "container/heap"
    "math"
)

const (
    RouteHysteresis  = 0.25
    StickyLossThresh = float32(0.15)
    EMARTTAlpha      = 0.2
)

type Route struct {
    Destination uint32
    Hops        []uint32 // [hop1, hop2, ..., dst]
    Score       float64
}

// EdgeWeight computes the Dijkstra edge cost.
// loss is quadratic: 5% → 25, 15% → 225.
func EdgeWeight(rttMs float64, lossRatio float32, linkType string) float64 {
    penalty := map[string]float64{"tcp": 0, "wifidirect": 10, "ble": 200}
    p := penalty[linkType]
    l := float64(lossRatio)
    return rttMs + l*l*10000 + p
}

// ShouldSwitch returns true if candidate is ≥25% better than current.
func ShouldSwitch(current, candidate *Route) bool {
    if current == nil { return true }
    return candidate.Score < current.Score*(1-RouteHysteresis)
}

type node struct{ id uint32; dist float64; path []uint32 }
type minHeap []node

func (h minHeap) Len() int            { return len(h) }
func (h minHeap) Less(i, j int) bool  { return h[i].dist < h[j].dist }
func (h minHeap) Swap(i, j int)       { h[i], h[j] = h[j], h[i] }
func (h *minHeap) Push(x any)         { *h = append(*h, x.(node)) }
func (h *minHeap) Pop() any           { old := *h; n := old[len(old)-1]; *h = old[:len(old)-1]; return n }

// Dijkstra computes the best source route from src to dst.
// localLinks: direct links from the local node (src), keyed by neighbor hashID.
func Dijkstra(src, dst uint32, pt *PeerTable, localLinks map[uint32]LinkEntry) *Route {
    dist := map[uint32]float64{src: 0}
    prev := map[uint32]uint32{}

    h := &minHeap{{id: src, dist: 0}}
    heap.Init(h)

    neighbors := func(id uint32) []LinkEntry {
        if id == src { // local outgoing links
            out := make([]LinkEntry, 0, len(localLinks))
            for _, e := range localLinks { out = append(out, e) }
            return out
        }
        p := pt.GetByHash(id)
        if p == nil { return nil }
        return p.Links
    }

    for h.Len() > 0 {
        cur := heap.Pop(h).(node)
        if cur.id == dst {
            // Reconstruct path
            path := []uint32{}
            for n := dst; n != src; n = prev[n] {
                path = append([]uint32{n}, path...)
            }
            return &Route{Destination: dst, Hops: path, Score: cur.dist}
        }

        for _, e := range neighbors(cur.id) {
            w := EdgeWeight(e.RTTms, e.LossRatio, "tcp") // link type refinement in Task 9
            nd := cur.dist + w
            if best, ok := dist[e.PeerHashID]; !ok || nd < best {
                dist[e.PeerHashID] = nd
                prev[e.PeerHashID] = cur.id
                heap.Push(h, node{id: e.PeerHashID, dist: nd})
            }
        }
    }
    return nil
}

// UpdateEMA updates RTT using exponential moving average (alpha=0.2).
func UpdateEMA(old, current float64) float64 {
    return old*(1-EMARTTAlpha) + current*EMARTTAlpha
}

func UpdateLossEMA(old, current float32) float32 {
    return old*(1-EMARTTAlpha) + current*EMARTTAlpha
}

func IsAboveStickyThreshold(lossRatio float32) bool {
    return lossRatio > StickyLossThresh
}

// clamp keeps score sane
func _ (x float64) float64 { return math.Max(0, x) }
```

**Step 4: Run tests**

```bash
cd go && go test ./mesh/router/... -v -race
```
Expected: all PASS.

**Step 5: Commit**

```bash
git add go/mesh/router/route.go go/mesh/router/route_test.go
git commit -m "feat(mesh): Dijkstra source routing with hysteresis and EMA metrics"
```

---

### Task 6: Gossip protocol

**Files:**
- Create: `go/mesh/router/gossip.go`
- Create: `go/mesh/router/gossip_test.go`

**Step 1: Write failing tests**

```go
// go/mesh/router/gossip_test.go
package router_test

import (
    "testing"
    "time"
    "github.com/catsi/piper/mesh/router"
    "github.com/catsi/piper/mesh/transport"
)

func TestGossipPacketRoundtrip(t *testing.T) {
    pkt := router.GossipPacket{
        From:    "peer-a",
        SeqNum:  42,
        IsDelta: false,
        Peers: []router.MeshPeer{
            {ID: "peer-b", HashID: 0xBB, Name: "Bob", Version: 3},
        },
    }
    data, err := router.EncodeGossip(pkt)
    if err != nil { t.Fatal(err) }
    got, err := router.DecodeGossip(data)
    if err != nil { t.Fatal(err) }
    if got.From != "peer-a" { t.Fatalf("From: want peer-a got %s", got.From) }
    if got.SeqNum != 42 { t.Fatalf("SeqNum: want 42 got %d", got.SeqNum) }
    if len(got.Peers) != 1 { t.Fatalf("Peers len: want 1 got %d", len(got.Peers)) }
    if got.Peers[0].Name != "Bob" { t.Fatal("peer name mismatch") }
}

func TestGossipAppliesUpdatesToTable(t *testing.T) {
    pt := router.NewPeerTable("self")
    g := router.NewGossip("self", pt, 10*time.Millisecond, 50*time.Millisecond)

    mockLink := &MockLink{id: "link-a", peerID: "peer-a"}
    g.AddLink(mockLink)

    // Simulate receiving a gossip packet from peer-a
    pkt := router.GossipPacket{
        From:   "peer-a",
        SeqNum: 1,
        Peers:  []router.MeshPeer{{ID: "peer-b", HashID: 0xBB, Name: "Bob", Version: 1}},
    }
    data, _ := router.EncodeGossip(pkt)
    g.HandleIncoming(data, "peer-a")

    // peer-b should now be in the table
    got := pt.Get("peer-b")
    if got == nil { t.Fatal("peer-b not in table after gossip") }
    if got.Name != "Bob" { t.Fatal("wrong name") }
}
```

**Step 2: Run to confirm failure**

```bash
cd go && go test ./mesh/router/... -v -run TestGossip
```

**Step 3: Implement**

```go
// go/mesh/router/gossip.go
package router

import (
    "sync"
    "time"

    "github.com/catsi/piper/mesh/transport"
    "github.com/vmihailenco/msgpack/v5"
)

type GossipPacket struct {
    From    string     `msgpack:"f"`
    SeqNum  uint32     `msgpack:"s"`
    Peers   []MeshPeer `msgpack:"p"`
    IsDelta bool       `msgpack:"d"`
}

func EncodeGossip(p GossipPacket) ([]byte, error) { return msgpack.Marshal(p) }
func DecodeGossip(b []byte) (GossipPacket, error) {
    var p GossipPacket
    return p, msgpack.Unmarshal(b, &p)
}

type Gossip struct {
    localID      string
    table        *PeerTable
    pushInterval time.Duration
    pullInterval time.Duration

    mu    sync.RWMutex
    links map[string]transport.Link // peerID → Link

    stopCh chan struct{}
}

func NewGossip(localID string, table *PeerTable, push, pull time.Duration) *Gossip {
    return &Gossip{
        localID:      localID,
        table:        table,
        pushInterval: push,
        pullInterval: pull,
        links:        make(map[string]transport.Link),
        stopCh:       make(chan struct{}),
    }
}

func (g *Gossip) AddLink(l transport.Link) {
    g.mu.Lock()
    g.links[l.PeerID()] = l
    g.mu.Unlock()
    l.SetOnReceive(func(pkt []byte) {
        if len(pkt) > 0 && pkt[0]&0xF0 == 0x10 { // TypeGossip
            g.HandleIncoming(pkt[1:], l.PeerID()) // strip type byte
        }
    })
}

func (g *Gossip) RemoveLink(peerID string) {
    g.mu.Lock()
    delete(g.links, peerID)
    g.mu.Unlock()
}

func (g *Gossip) HandleIncoming(data []byte, fromPeerID string) {
    pkt, err := DecodeGossip(data)
    if err != nil { return }
    for _, p := range pkt.Peers {
        g.table.Merge(p)
    }
}

func (g *Gossip) Start() { go g.pushLoop() }

func (g *Gossip) Stop() { close(g.stopCh) }

func (g *Gossip) pushLoop() {
    pushTick := time.NewTicker(g.pushInterval)
    defer pushTick.Stop()
    for {
        select {
        case <-g.stopCh: return
        case <-pushTick.C:
            g.broadcast()
        }
    }
}

func (g *Gossip) broadcast() {
    pkt := GossipPacket{
        From:    g.localID,
        IsDelta: false,
        Peers:   g.table.All(),
    }
    data, err := EncodeGossip(pkt)
    if err != nil { return }

    // Prefix with type byte
    frame := append([]byte{0x10}, data...)

    g.mu.RLock()
    defer g.mu.RUnlock()
    for _, l := range g.links {
        l.Send(frame) //nolint:errcheck
    }
}
```

**Step 4: Run all router tests**

```bash
cd go && go test ./mesh/router/... -v -race
```
Expected: all PASS.

**Step 5: Commit**

```bash
git add go/mesh/router/gossip.go go/mesh/router/gossip_test.go
git commit -m "feat(mesh): gossip protocol with msgpack encoding"
```

---

## Phase 3 — UDP Proxy + STUN Termination (`mesh/proxy/`)

### Task 7: Add pion/stun dependency + packet classifier

**Files:**
- Create: `go/mesh/proxy/classify.go`
- Create: `go/mesh/proxy/classify_test.go`

**Step 1: Add dependency**

```bash
cd go && go get github.com/pion/stun/v2
```

**Step 2: Write failing tests**

```go
// go/mesh/proxy/classify_test.go
package proxy_test

import (
    "testing"
    "github.com/catsi/piper/mesh/proxy"
)

func TestClassifySTUN(t *testing.T) {
    for _, b := range []byte{0x00, 0x01, 0x02, 0x03} {
        if proxy.Classify([]byte{b}) != proxy.PktSTUN {
            t.Fatalf("byte 0x%02x should be STUN", b)
        }
    }
}

func TestClassifyDTLS(t *testing.T) {
    for _, b := range []byte{20, 40, 63} {
        if proxy.Classify([]byte{b}) != proxy.PktDTLS {
            t.Fatalf("byte %d should be DTLS", b)
        }
    }
}

func TestClassifySRTP(t *testing.T) {
    for _, b := range []byte{128, 150, 191} {
        if proxy.Classify([]byte{b}) != proxy.PktSRTP {
            t.Fatalf("byte %d should be SRTP", b)
        }
    }
}

func TestClassifyUnknown(t *testing.T) {
    if proxy.Classify([]byte{}) != proxy.PktUnknown { t.Fatal("empty should be unknown") }
    if proxy.Classify([]byte{64}) != proxy.PktUnknown { t.Fatal("64 should be unknown") }
}
```

**Step 3: Implement**

```go
// go/mesh/proxy/classify.go
package proxy

type PktClass uint8
const (
    PktSTUN    PktClass = iota
    PktDTLS
    PktSRTP
    PktUnknown
)

func Classify(b []byte) PktClass {
    if len(b) == 0 { return PktUnknown }
    switch {
    case b[0] <= 0x03:                  return PktSTUN
    case b[0] >= 20 && b[0] <= 63:     return PktDTLS
    case b[0] >= 128 && b[0] <= 191:   return PktSRTP
    default:                             return PktUnknown
    }
}
```

**Step 4: Run tests**

```bash
cd go && go test ./mesh/proxy/... -v
```
Expected: PASS.

**Step 5: Commit**

```bash
git add go/mesh/proxy/
git commit -m "feat(mesh): packet classifier (STUN/DTLS/SRTP)"
```

---

### Task 8: PeerProxy with STUN termination

**Files:**
- Create: `go/mesh/proxy/peer_proxy.go`
- Create: `go/mesh/proxy/peer_proxy_test.go`

**Step 1: Write failing integration test**

```go
// go/mesh/proxy/peer_proxy_test.go
package proxy_test

import (
    "net"
    "testing"
    "time"

    "github.com/pion/stun/v2"
    "github.com/catsi/piper/mesh/proxy"
    "github.com/catsi/piper/mesh/router"
)

// mockRouter captures Send calls
type mockRouter struct { sent [][]byte }
func (m *mockRouter) Send(peerID string, payload []byte, bufPtr *[]byte) {
    cp := make([]byte, len(payload))
    copy(cp, payload)
    m.sent = append(m.sent, cp)
}

func TestPeerProxySTUNResponse(t *testing.T) {
    icePwd := "testpassword1234"
    mr := &mockRouter{}

    pp, err := proxy.NewPeerProxy("peer-x", icePwd, mr)
    if err != nil { t.Fatal(err) }
    defer pp.Close()

    // Connect a UDP client (simulates libwebrtc)
    clientConn, err := net.DialUDP("udp", nil, pp.LocalAddr())
    if err != nil { t.Fatal(err) }
    defer clientConn.Close()

    // Build a real STUN Binding Request
    req, err := stun.Build(stun.TransactionID, stun.BindingRequest)
    if err != nil { t.Fatal(err) }

    clientConn.SetDeadline(time.Now().Add(3 * time.Second))
    if _, err := clientConn.Write(req.Raw); err != nil { t.Fatal(err) }

    // Expect a STUN response back
    buf := make([]byte, 1500)
    n, err := clientConn.Read(buf)
    if err != nil { t.Fatalf("no STUN response: %v", err) }

    resp := new(stun.Message)
    if err := resp.Unmarshal(buf[:n]); err != nil { t.Fatalf("invalid STUN response: %v", err) }
    if resp.Type != stun.BindingSuccess { t.Fatalf("want BindingSuccess got %v", resp.Type) }
}

func TestPeerProxyForwardsDTLS(t *testing.T) {
    mr := &mockRouter{}
    pp, err := proxy.NewPeerProxy("peer-x", "pwd", mr)
    if err != nil { t.Fatal(err) }
    defer pp.Close()

    client, _ := net.DialUDP("udp", nil, pp.LocalAddr())
    defer client.Close()

    // DTLS first byte = 22 (0x16)
    dtlsPkt := append([]byte{22}, []byte("fake dtls content")...)
    client.SetDeadline(time.Now().Add(2 * time.Second))
    client.Write(dtlsPkt)

    time.Sleep(100 * time.Millisecond)
    if len(mr.sent) == 0 { t.Fatal("DTLS packet not forwarded to router") }
    if mr.sent[0][0] != 22 { t.Fatalf("wrong first byte: %x", mr.sent[0][0]) }
}
```

**Step 2: Run to confirm failure**

```bash
cd go && go test ./mesh/proxy/... -v -run TestPeerProxy
```

**Step 3: Implement**

```go
// go/mesh/proxy/peer_proxy.go
package proxy

import (
    "net"
    "sync"

    "github.com/pion/stun/v2"
    "github.com/catsi/piper/mesh/transport"
)

const MeshHeaderMaxLen = transport.MeshHeaderMaxLen

type Router interface {
    Send(peerID string, payload []byte, bufPtr *[]byte)
}

type PeerProxy struct {
    peerID       string
    remoteIcePwd string
    conn         *net.UDPConn
    webrtcAddr   *net.UDPAddr
    router       Router
    pool         sync.Pool
    stopCh       chan struct{}
    mu           sync.Mutex
}

func NewPeerProxy(peerID, remoteIcePwd string, r Router) (*PeerProxy, error) {
    conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
    if err != nil { return nil, err }

    pp := &PeerProxy{
        peerID:       peerID,
        remoteIcePwd: remoteIcePwd,
        conn:         conn,
        router:       r,
        stopCh:       make(chan struct{}),
    }
    pp.pool.New = func() any {
        b := make([]byte, MeshHeaderMaxLen+65600)
        return &b
    }
    go pp.run()
    return pp, nil
}

func (p *PeerProxy) LocalAddr() *net.UDPAddr {
    return p.conn.LocalAddr().(*net.UDPAddr)
}

func (p *PeerProxy) Close() {
    select {
    case <-p.stopCh:
    default: close(p.stopCh)
    }
    p.conn.Close()
}

func (p *PeerProxy) DeliverFromMesh(payload []byte) {
    p.mu.Lock()
    addr := p.webrtcAddr
    p.mu.Unlock()
    if addr == nil { return }
    p.conn.WriteToUDP(payload, addr)
}

func (p *PeerProxy) run() {
    for {
        select {
        case <-p.stopCh: return
        default:
        }

        bufPtr := p.pool.Get().(*[]byte)
        n, addr, err := p.conn.ReadFromUDP((*bufPtr)[MeshHeaderMaxLen:])
        if err != nil {
            p.pool.Put(bufPtr)
            return
        }

        p.mu.Lock()
        if p.webrtcAddr == nil { p.webrtcAddr = addr }
        p.mu.Unlock()

        pkt := (*bufPtr)[MeshHeaderMaxLen : MeshHeaderMaxLen+n]

        switch Classify(pkt) {
        case PktSTUN:
            p.handleSTUN(pkt, addr)
            p.pool.Put(bufPtr)
        case PktDTLS, PktSRTP:
            p.router.Send(p.peerID, pkt, bufPtr)
        default:
            p.pool.Put(bufPtr)
        }
    }
}

func (p *PeerProxy) handleSTUN(reqBytes []byte, clientAddr *net.UDPAddr) {
    msg := new(stun.Message)
    if err := msg.Unmarshal(reqBytes); err != nil { return }

    resp := new(stun.Message)
    if err := resp.Build(
        msg,
        stun.BindingSuccess,
        &stun.XORMappedAddress{IP: clientAddr.IP, Port: clientAddr.Port},
        stun.NewShortTermIntegrity(p.remoteIcePwd),
        stun.Fingerprint,
    ); err != nil { return }

    p.conn.WriteToUDP(resp.Raw, clientAddr)
}
```

**Step 4: Run tests with race detector**

```bash
cd go && go test ./mesh/proxy/... -v -race
```
Expected: all PASS.

**Step 5: Commit**

```bash
git add go/mesh/proxy/peer_proxy.go go/mesh/proxy/peer_proxy_test.go
git commit -m "feat(mesh): PeerProxy with ICE-compliant STUN termination using pion/stun"
```

---

### Task 9: ProxyManager

**Files:**
- Create: `go/mesh/proxy/proxy.go`
- Create: `go/mesh/proxy/proxy_test.go`

**Step 1: Write failing test**

```go
// go/mesh/proxy/proxy_test.go
package proxy_test

import (
    "testing"
    "github.com/catsi/piper/mesh/proxy"
)

func TestProxyManagerOpenClose(t *testing.T) {
    mr := &mockRouter{}
    mgr := proxy.NewProxyManager(mr)

    port, err := mgr.OpenProxy("peer-a", "password-a")
    if err != nil { t.Fatal(err) }
    if port <= 0 || port > 65535 { t.Fatalf("invalid port %d", port) }

    // Opening same peer twice returns same port
    port2, err := mgr.OpenProxy("peer-a", "password-a")
    if err != nil { t.Fatal(err) }
    if port2 != port { t.Fatalf("want same port, got %d vs %d", port, port2) }

    mgr.CloseProxy("peer-a")

    // After close, new OpenProxy gets a new port
    port3, err := mgr.OpenProxy("peer-a", "password-a")
    if err != nil { t.Fatal(err) }
    if port3 == port { t.Fatal("after close, expected new port") }
    mgr.CloseProxy("peer-a")
}
```

**Step 2: Implement**

```go
// go/mesh/proxy/proxy.go
package proxy

import "sync"

type ProxyManager struct {
    mu      sync.Mutex
    proxies map[string]*PeerProxy
    router  Router
}

func NewProxyManager(r Router) *ProxyManager {
    return &ProxyManager{proxies: make(map[string]*PeerProxy), router: r}
}

func (m *ProxyManager) OpenProxy(peerID, remoteIcePwd string) (int, error) {
    m.mu.Lock()
    defer m.mu.Unlock()

    if existing, ok := m.proxies[peerID]; ok {
        return existing.LocalAddr().Port, nil
    }

    pp, err := NewPeerProxy(peerID, remoteIcePwd, m.router)
    if err != nil { return -1, err }
    m.proxies[peerID] = pp
    return pp.LocalAddr().Port, nil
}

func (m *ProxyManager) CloseProxy(peerID string) {
    m.mu.Lock()
    defer m.mu.Unlock()
    if pp, ok := m.proxies[peerID]; ok {
        pp.Close()
        delete(m.proxies, peerID)
    }
}

func (m *ProxyManager) Deliver(peerID string, payload []byte) {
    m.mu.Lock()
    pp := m.proxies[peerID]
    m.mu.Unlock()
    if pp != nil { pp.DeliverFromMesh(payload) }
}
```

**Step 3: Run tests**

```bash
cd go && go test ./mesh/proxy/... -v -race
```

**Step 4: Commit**

```bash
git add go/mesh/proxy/proxy.go go/mesh/proxy/proxy_test.go
git commit -m "feat(mesh): ProxyManager — per-peer UDP proxy lifecycle"
```

---

## Phase 4 — Self-Healing (`mesh/healer/`)

### Task 10: Watchdog

**Files:**
- Create: `go/mesh/healer/watchdog.go`
- Create: `go/mesh/healer/watchdog_test.go`

**Step 1: Write failing tests**

```go
// go/mesh/healer/watchdog_test.go
package healer_test

import (
    "testing"
    "time"
    "github.com/catsi/piper/mesh/healer"
)

type mockRerouter struct { triggered []string }
func (m *mockRerouter) TriggerReroute(peerID, reason string) {
    m.triggered = append(m.triggered, peerID+":"+reason)
}

func TestWatchdogDetectsLinkDead(t *testing.T) {
    mr := &mockRerouter{}
    w := healer.NewWatchdog(mr, 50*time.Millisecond)
    w.AddPeer("peer-x")

    // Don't call OnPacketReceived — silence should trigger dead link
    time.Sleep(300 * time.Millisecond)

    if len(mr.triggered) == 0 { t.Fatal("expected reroute trigger") }
    if mr.triggered[0] != "peer-x:link_dead" {
        t.Fatalf("want peer-x:link_dead got %s", mr.triggered[0])
    }
}

func TestWatchdogResetsOnPacket(t *testing.T) {
    mr := &mockRerouter{}
    w := healer.NewWatchdog(mr, 50*time.Millisecond)
    w.AddPeer("peer-y")

    // Feed packets regularly — should NOT trigger reroute
    done := make(chan struct{})
    go func() {
        for {
            select {
            case <-done: return
            case <-time.After(20 * time.Millisecond):
                w.OnPacketReceived("peer-y")
            }
        }
    }()

    time.Sleep(300 * time.Millisecond)
    close(done)

    if len(mr.triggered) > 0 {
        t.Fatalf("unexpected reroute: %v", mr.triggered)
    }
}

func TestWatchdogProbeAckValidatesSeq(t *testing.T) {
    mr := &mockRerouter{}
    w := healer.NewWatchdog(mr, 50*time.Millisecond)
    w.AddPeer("peer-z")

    // Let it go degraded
    time.Sleep(120 * time.Millisecond)

    // Send wrong seq — should not reset
    w.OnProbeAck("peer-z", 9999)

    // Should still reroute eventually
    time.Sleep(200 * time.Millisecond)
    if len(mr.triggered) == 0 { t.Fatal("expected reroute after bad probe ack") }
}
```

**Step 2: Run to confirm failure**

```bash
cd go && go test ./mesh/healer/... -v -run TestWatchdog
```

**Step 3: Implement**

```go
// go/mesh/healer/watchdog.go
package healer

import (
    "sync"
    "time"
)

type LinkState uint8
const (
    LinkHealthy  LinkState = iota
    LinkDegraded
    LinkDead
)

type Rerouter interface {
    TriggerReroute(peerID, reason string)
}

type linkHealth struct {
    state      LinkState
    lastAckAt  time.Time
    failCount  int
    probeSeq   uint32
}

type Watchdog struct {
    rerouter Rerouter
    tick     time.Duration
    mu       sync.Mutex
    links    map[string]*linkHealth
    stopCh   chan struct{}
}

// silentThreshold: silence > 4 ticks → degraded; 3 more ticks → dead
const degradedAfter = 4
const deadAfter     = 3

func NewWatchdog(r Rerouter, tick time.Duration) *Watchdog {
    w := &Watchdog{
        rerouter: r,
        tick:     tick,
        links:    make(map[string]*linkHealth),
        stopCh:   make(chan struct{}),
    }
    go w.loop()
    return w
}

func (w *Watchdog) AddPeer(peerID string) {
    w.mu.Lock()
    w.links[peerID] = &linkHealth{state: LinkHealthy, lastAckAt: time.Now()}
    w.mu.Unlock()
}

func (w *Watchdog) RemovePeer(peerID string) {
    w.mu.Lock()
    delete(w.links, peerID)
    w.mu.Unlock()
}

func (w *Watchdog) OnPacketReceived(peerID string) {
    w.mu.Lock()
    defer w.mu.Unlock()
    if h, ok := w.links[peerID]; ok {
        h.lastAckAt = time.Now()
        if h.state == LinkDegraded {
            h.state = LinkHealthy
            h.failCount = 0
        }
    }
}

func (w *Watchdog) OnProbeAck(peerID string, seq uint32) {
    w.mu.Lock()
    defer w.mu.Unlock()
    h, ok := w.links[peerID]
    if !ok { return }
    if h.probeSeq != seq { return } // stale/wrong seq — ignore
    h.lastAckAt = time.Now()
    h.state = LinkHealthy
    h.failCount = 0
}

func (w *Watchdog) Stop() { close(w.stopCh) }

func (w *Watchdog) loop() {
    t := time.NewTicker(w.tick)
    defer t.Stop()
    silentTicks := make(map[string]int)

    for {
        select {
        case <-w.stopCh: return
        case now := <-t.C:
            w.mu.Lock()
            for id, h := range w.links {
                if now.Sub(h.lastAckAt) > w.tick {
                    silentTicks[id]++
                } else {
                    silentTicks[id] = 0
                }

                switch h.state {
                case LinkHealthy:
                    if silentTicks[id] >= degradedAfter {
                        h.state = LinkDegraded
                        h.failCount = 0
                        h.probeSeq++
                    }
                case LinkDegraded:
                    h.failCount++
                    if h.failCount >= deadAfter {
                        h.state = LinkDead
                        w.mu.Unlock()
                        w.rerouter.TriggerReroute(id, "link_dead")
                        w.mu.Lock()
                    }
                case LinkDead:
                    // wait for gossip recovery
                }
            }
            w.mu.Unlock()
        }
    }
}
```

**Step 4: Run tests**

```bash
cd go && go test ./mesh/healer/... -v -race
```
Expected: all PASS.

**Step 5: Commit**

```bash
git add go/mesh/healer/
git commit -m "feat(mesh): Watchdog — link health monitoring with probe ACK validation"
```

---

### Task 11: Rerouter

**Files:**
- Create: `go/mesh/healer/rerouter.go`
- Create: `go/mesh/healer/rerouter_test.go`

**Step 1: Write failing test**

```go
// go/mesh/healer/rerouter_test.go
package healer_test

import (
    "testing"
    "time"
    "github.com/catsi/piper/mesh/healer"
)

type mockRecomputer struct { called []string }
func (m *mockRecomputer) Recompute(peerID string) { m.called = append(m.called, peerID) }

func TestRerouterDeduplicates(t *testing.T) {
    mc := &mockRecomputer{}
    r := healer.NewRerouter(mc, 50*time.Millisecond)

    r.TriggerReroute("peer-a", "link_dead")
    r.TriggerReroute("peer-a", "link_dead") // duplicate — should be ignored
    r.TriggerReroute("peer-a", "link_dead")

    time.Sleep(200 * time.Millisecond)

    if len(mc.called) != 1 {
        t.Fatalf("want 1 Recompute call, got %d", len(mc.called))
    }
}
```

**Step 2: Implement**

```go
// go/mesh/healer/rerouter.go
package healer

import (
    "sync"
    "time"
)

type Recomputer interface {
    Recompute(peerID string)
}

type RerouteEvent struct {
    PeerID string
    Reason string
}

type Rerouter struct {
    recomputer Recomputer
    cooldown   time.Duration
    mu         sync.Mutex
    active     map[string]bool
    events     chan RerouteEvent
}

func NewRerouter(r Recomputer, cooldown time.Duration) *Rerouter {
    rt := &Rerouter{
        recomputer: r,
        cooldown:   cooldown,
        active:     make(map[string]bool),
        events:     make(chan RerouteEvent, 64),
    }
    go rt.loop()
    return rt
}

func (r *Rerouter) TriggerReroute(peerID, reason string) {
    r.mu.Lock()
    if r.active[peerID] { r.mu.Unlock(); return }
    r.active[peerID] = true
    r.mu.Unlock()
    r.events <- RerouteEvent{PeerID: peerID, Reason: reason}
}

func (r *Rerouter) loop() {
    for ev := range r.events {
        r.recomputer.Recompute(ev.PeerID)
        time.Sleep(r.cooldown) // cooldown before next reroute for same peer
        r.mu.Lock()
        delete(r.active, ev.PeerID)
        r.mu.Unlock()
    }
}
```

**Step 3: Run tests**

```bash
cd go && go test ./mesh/healer/... -v -race
```

**Step 4: Commit**

```bash
git add go/mesh/healer/rerouter.go go/mesh/healer/rerouter_test.go
git commit -m "feat(mesh): Rerouter with deduplication and cooldown"
```

---

## Phase 5 — Cutover (`mesh/node.go` + FFI + Flutter)

### Task 12: mesh.Node

**Files:**
- Create: `go/mesh/node.go`
- Create: `go/mesh/node_test.go`

**Step 1: Write smoke test**

```go
// go/mesh/node_test.go
package mesh_test

import (
    "testing"
    "github.com/catsi/piper/mesh"
)

func TestNodeStartStop(t *testing.T) {
    n := mesh.NewNode("test-node")
    if err := n.Start(); err != nil { t.Fatal(err) }
    id := n.ID()
    if id == "" { t.Fatal("node ID must not be empty") }
    n.Stop()
}

func TestNodeOpenCloseProxy(t *testing.T) {
    n := mesh.NewNode("proxy-test")
    n.Start()
    defer n.Stop()

    port, err := n.OpenProxy("some-peer", "ice-password-xyz")
    if err != nil { t.Fatal(err) }
    if port <= 0 { t.Fatal("invalid port") }
    n.CloseProxy("some-peer")
}
```

**Step 2: Implement mesh.Node**

```go
// go/mesh/node.go
package mesh

import (
    "github.com/catsi/piper/core"
    "github.com/catsi/piper/mesh/healer"
    "github.com/catsi/piper/mesh/proxy"
    "github.com/catsi/piper/mesh/router"
    "github.com/google/uuid"
)

type Node struct {
    id      string
    name    string
    keyPair core.KeyPair

    table    *router.PeerTable
    gossip   *router.Gossip
    proxyMgr *proxy.ProxyManager
    watchdog *healer.Watchdog
    rerouter *healer.Rerouter

    // Delegate messaging to core.Node until full cutover
    legacy  *core.Node
    events  chan core.Event
}

func NewNode(name string) *Node {
    return NewNodeWithID(name, uuid.New().String())
}

func NewNodeWithID(name, id string) *Node {
    n := &Node{
        id:     id,
        name:   name,
        events: make(chan core.Event, 256),
    }
    n.table = router.NewPeerTable(id)
    return n
}

func (n *Node) Start() error {
    n.legacy = core.NewNodeWithID(n.name, n.id)
    if err := n.legacy.Start(); err != nil { return err }

    // Initialize mesh subsystems
    rt := &meshRouter{node: n}
    n.proxyMgr = proxy.NewProxyManager(rt)
    n.rerouter = healer.NewRerouter(rt, 500*1e6)
    n.watchdog = healer.NewWatchdog(n.rerouter, 500*1e6)

    // Forward legacy events to our channel
    go func() {
        for ev := range n.legacy.Events() {
            n.events <- ev
        }
    }()
    return nil
}

func (n *Node) Stop() {
    n.watchdog.Stop()
    n.legacy.Stop()
}

func (n *Node) ID() string   { return n.id }
func (n *Node) Name() string { return n.name }

func (n *Node) OpenProxy(peerID, remoteIcePwd string) (int, error) {
    return n.proxyMgr.OpenProxy(peerID, remoteIcePwd)
}

func (n *Node) CloseProxy(peerID string) {
    n.proxyMgr.CloseProxy(peerID)
}

// Delegate all messaging to legacy core.Node
func (n *Node) Send(text, toPeerID string)         { n.legacy.Send(text, toPeerID) }
func (n *Node) SendCallSignal(to, t, p string) error { return n.legacy.SendCallSignal(to, t, p) }
func (n *Node) PeerTable() []core.PeerRecord        { return n.legacy.PeerTable() }
func (n *Node) InjectPeers(r []core.PeerRecord)     { n.legacy.InjectPeers(r) }
func (n *Node) LocalEndpoint() core.PeerRecord      { return n.legacy.LocalEndpoint() }
func (n *Node) Events() <-chan core.Event            { return n.events }
func (n *Node) Peers() []*core.PeerInfo             { return n.legacy.Peers() }
func (n *Node) Groups() []*core.Group               { return n.legacy.Groups() }
func (n *Node) SetName(name string)                 { n.name = name; n.legacy.SetName(name) }
func (n *Node) SetDownloadsDir(dir string)          { n.legacy.SetDownloadsDir(dir) }

// meshRouter implements proxy.Router and healer.Recomputer
type meshRouter struct{ node *Node }
func (r *meshRouter) Send(peerID string, payload []byte, bufPtr *[]byte) { /* Phase 6 */ }
func (r *meshRouter) Recompute(peerID string)                            { /* Phase 6 */ }
```

**Step 3: Run tests**

```bash
cd go && go test ./mesh/... -v -race
```
Expected: all PASS.

**Step 4: Commit**

```bash
git add go/mesh/node.go go/mesh/node_test.go
git commit -m "feat(mesh): mesh.Node delegating to core.Node with proxy subsystem"
```

---

### Task 13: FFI bridge — add mesh exports

**Files:**
- Modify: `go/ffi/bridge.go`

**Step 1: Add three exports after existing `PiperGetLocalInfo`**

```go
// Add to go/ffi/bridge.go — after PiperInjectPeers

//export PiperOpenProxy
func PiperOpenProxy(handle C.int, peerID, remoteIcePwd *C.char) C.int {
    e := getEntry(handle)
    if e == nil { return -1 }
    port, err := e.node.OpenProxy(C.GoString(peerID), C.GoString(remoteIcePwd))
    if err != nil { return -1 }
    return C.int(port)
}

//export PiperCloseProxy
func PiperCloseProxy(handle C.int, peerID *C.char) {
    e := getEntry(handle)
    if e == nil { return }
    e.node.CloseProxy(C.GoString(peerID))
}

//export PiperMeshDiag
func PiperMeshDiag(handle C.int) *C.char {
    e := getEntry(handle)
    if e == nil { return C.CString("{}") }
    // Returns JSON snapshot; caller MUST call PiperFreeString() after use
    data, _ := json.Marshal(map[string]string{"status": "ok"})
    return C.CString(string(data))
}
```

**Step 2: Build FFI to confirm no compile errors**

```bash
cd go && go build ./ffi/...
```
Expected: success.

**Step 3: Commit**

```bash
git add go/ffi/bridge.go
git commit -m "feat(mesh): FFI exports for OpenProxy/CloseProxy/MeshDiag"
```

---

### Task 14: Flutter — MeshCallService + PiperNode bindings

**Files:**
- Create: `flutter-app/lib/services/mesh_call_service.dart`
- Modify: `flutter-app/lib/native/piper_node.dart`

**Step 1: Add native bindings to piper_node.dart**

Read the file first, then add after existing bindings:

```dart
// In piper_node.dart — add these methods to PiperNode class:

int openProxy(String peerId, String remoteIcePwd) {
    // Returns local UDP port, or -1 on error
    final peerIdPtr  = peerId.toNativeUtf8();
    final icePwdPtr  = remoteIcePwd.toNativeUtf8();
    final port = _bindings.PiperOpenProxy(_handle, peerIdPtr, icePwdPtr);
    calloc.free(peerIdPtr);
    calloc.free(icePwdPtr);
    return port;
}

void closeProxy(String peerId) {
    final ptr = peerId.toNativeUtf8();
    _bindings.PiperCloseProxy(_handle, ptr);
    calloc.free(ptr);
}
```

**Step 2: Create MeshCallService**

```dart
// flutter-app/lib/services/mesh_call_service.dart
import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../native/piper_node.dart';
import 'call_service.dart';

class MeshCallService extends CallService {
  MeshCallService._() : super._();
  static final MeshCallService instance = MeshCallService._();

  @override
  Map<String, dynamic> get _rtcConfig => const {
    'iceServers': <Map<String, dynamic>>[],
    'iceTransportPolicy': 'relay', // suppress host candidate gathering
  };

  /// Call after setRemoteDescription — extracts ice-pwd, opens Go proxy,
  /// injects single localhost ICE candidate.
  Future<void> attachMeshProxy(String peerId, String remoteSdp) async {
    final icePwd   = _extractIcePwd(remoteSdp);
    final iceUfrag = _extractIceUfrag(remoteSdp);
    if (icePwd == null) throw Exception('no ice-pwd in remote SDP');

    final port = _piperNode.openProxy(peerId, icePwd);
    if (port < 0) throw Exception('Go proxy unavailable for $peerId');

    final ufragSuffix = iceUfrag != null ? ' ufrag $iceUfrag' : '';
    await _pc!.addCandidate(RTCIceCandidate(
      'candidate:1 1 UDP 2130706431 127.0.0.1 $port typ host$ufragSuffix',
      '0',
      0,
    ));
  }

  @override
  Future<void> _cleanup() async {
    final id = peerId;
    await super._cleanup();
    if (id != null) _piperNode.closeProxy(id);
  }

  String? _extractIcePwd(String sdp) =>
      RegExp(r'a=ice-pwd:(\S+)').firstMatch(sdp)?.group(1);

  String? _extractIceUfrag(String sdp) =>
      RegExp(r'a=ice-ufrag:(\S+)').firstMatch(sdp)?.group(1);
}
```

**Step 3: Build Flutter to confirm no errors**

```bash
cd flutter-app && flutter build apk --debug 2>&1 | tail -20
```
Expected: no compile errors (runtime testing requires device).

**Step 4: Commit**

```bash
git add flutter-app/lib/services/mesh_call_service.dart
git add flutter-app/lib/native/piper_node.dart
git commit -m "feat(mesh): MeshCallService with localhost proxy ICE candidate"
```

---

### Task 15: WiFi Direct service (Android)

**Files:**
- Create: `flutter-app/android/app/src/main/kotlin/com/catsi/piper/WifiDirectPlugin.kt`
- Create: `flutter-app/lib/services/wifi_direct_service.dart`

**Step 1: Create Kotlin plugin skeleton**

```kotlin
// WifiDirectPlugin.kt
package com.catsi.piper

import android.content.Context
import android.net.wifi.p2p.WifiP2pManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class WifiDirectPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private val manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager?
    private var eventSink: EventChannel.EventSink? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startDiscovery" -> startDiscovery(result)
            "stopDiscovery"  -> stopDiscovery(result)
            else             -> result.notImplemented()
        }
    }

    override fun onListen(args: Any?, sink: EventChannel.EventSink?) { eventSink = sink }
    override fun onCancel(args: Any?) { eventSink = null }

    private fun startDiscovery(result: MethodChannel.Result) {
        // WifiP2pManager.discoverPeers — implementation in full Phase 5
        result.success(null)
    }

    private fun stopDiscovery(result: MethodChannel.Result) {
        result.success(null)
    }
}
```

**Step 2: Create Dart service**

```dart
// flutter-app/lib/services/wifi_direct_service.dart
import 'dart:io';
import 'package:flutter/services.dart';
import '../native/piper_node.dart';

class WifiDirectService {
  static const _method = MethodChannel('piper/wifidirect');
  static const _events = EventChannel('piper/wifidirect/events');

  static bool get isSupported => Platform.isAndroid;

  Future<void> start(PiperNode node) async {
    if (!isSupported) return;
    await _method.invokeMethod('startDiscovery');
    _events.receiveBroadcastStream().listen((event) {
      final map = Map<String, dynamic>.from(event as Map);
      final rec = PeerRecord(
        id:   map['id'] as String,
        name: map['name'] as String? ?? '',
        ip:   map['ip'] as String,
        port: map['port'] as int,
      );
      node.injectPeers([rec]);
    });
  }

  Future<void> stop() async {
    if (!isSupported) return;
    await _method.invokeMethod('stopDiscovery');
  }
}
```

**Step 3: Commit**

```bash
git add flutter-app/android/app/src/main/kotlin/com/catsi/piper/WifiDirectPlugin.kt
git add flutter-app/lib/services/wifi_direct_service.dart
git commit -m "feat(mesh): WiFi Direct plugin skeleton (Android)"
```

---

## Verification Checklist

Run before merging to master:

```bash
# All Go tests with race detector
cd go && go test ./mesh/... -v -race -count=1

# Go build
cd go && go build ./...

# Flutter analyze
cd flutter-app && flutter analyze

# Flutter unit tests
cd flutter-app && flutter test
```

Expected: all green, no races, no lint warnings.

---

## Summary of New Files

```
go/mesh/transport/link.go
go/mesh/transport/packet.go
go/mesh/transport/tcp_link.go
go/mesh/router/peer_table.go
go/mesh/router/route.go
go/mesh/router/gossip.go
go/mesh/healer/watchdog.go
go/mesh/healer/rerouter.go
go/mesh/proxy/classify.go
go/mesh/proxy/peer_proxy.go
go/mesh/proxy/proxy.go
go/mesh/node.go
flutter-app/lib/services/mesh_call_service.dart
flutter-app/lib/services/wifi_direct_service.dart
flutter-app/android/.../WifiDirectPlugin.kt
```

**Modified:**
```
go/ffi/bridge.go         (+3 exports)
flutter-app/lib/native/piper_node.dart  (+2 methods)
go/go.mod                (+pion/stun/v2, +msgpack/v5)
```
