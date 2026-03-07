# Mesh Network Layer — Design Document

**Date:** 2026-03-07
**Branch:** `try_dht_and_mesh`
**Status:** Approved, ready for implementation

---

## 1. Context and Goals

### Current Architecture

- **Go core** (`go/core/`): TCP connections, mDNS + UDP broadcast discovery, X25519/ChaCha20-Poly1305 encryption
- **Flutter FFI**: CGo bridge to Go shared library
- **BLE discovery**: Already implemented — 22-byte payload (IP+port+UUID), advertising + scanning
- **DHT peer exchange**: `PiperGetPeerTable` / `PiperInjectPeers` — already in FFI bridge
- **WebRTC calls**: `flutter_webrtc` with empty `iceServers: []` (local candidates only)

### Goals

1. **Overlay mesh routing** — Go builds source-routed overlay; libwebrtc sees only `127.0.0.1:port`
2. **Auto-switching** — LAN TCP when available, mesh relay otherwise, graceful degradation
3. **WiFi Direct** — Android + Desktop where available, degradation to mDNS+TCP elsewhere
4. **BLE gossip** — peer-table exchange across isolated subnets (existing BLE infra extended)
5. **Self-healing** — automatic route recovery within ~3.6 seconds of link failure

### Non-Goals

- Internet STUN/TURN (no relay servers)
- Replacing existing messaging/file transfer (TCP path untouched during migration)
- Custom media codec stack (libwebrtc handles all media encoding)

---

## 2. Architecture Overview

### Approach: Incremental Layering

New `go/mesh/` package built alongside `go/core/`. The existing `core.Node` remains untouched until cutover (Phase 5). Flutter app works throughout all phases.

```
go/
├── core/          # Existing code — DO NOT TOUCH until cutover
└── mesh/
    ├── transport/ # Physical channel abstraction
    │   ├── link.go            # interface Link (push model)
    │   ├── tcp_link.go        # LAN TCP transport
    │   ├── wifidirect_link.go # WiFi Direct (Android/Desktop)
    │   └── ble_relay_link.go  # BLE as relay channel (not media)
    ├── router/    # Gossip + Source routing
    │   ├── peer_table.go      # Extended DHT: {id, name, []addr, []links}
    │   ├── gossip.go          # Periodic peer-table exchange with neighbors
    │   └── route.go           # Dijkstra path computation
    ├── proxy/     # UDP Proxy + STUN Termination
    │   ├── proxy.go           # Manager: peerID → localUDPPort
    │   ├── peer_proxy.go      # Per-peer proxy with pion/stun
    │   └── classify.go        # STUN/DTLS/SRTP packet classifier
    ├── healer/    # Self-healing
    │   ├── watchdog.go        # Link health monitor
    │   └── rerouter.go        # Route recomputation trigger
    └── node.go    # mesh.Node — drop-in replacement for core.Node

flutter-app/lib/
└── services/
    ├── mesh_call_service.dart   # New CallService with localhost proxy
    └── wifi_direct_service.dart # WiFi Direct MethodChannel wrapper
```

---

## 3. Transport Layer (`mesh/transport/`)

### Link Interface — Push Model

```go
type LinkQuality struct {
    RTT       time.Duration
    LossRatio float32   // 0.0–1.0, EMA-smoothed
    Bandwidth int64     // bytes/sec estimate
}

type Link interface {
    ID() string
    PeerID() string
    Send(pkt []byte) error
    SetOnReceive(handler func(pkt []byte)) // push; handler must NOT retain slice
    Quality() LinkQuality
    Close()
}
```

**Why push, not `chan []byte`:** Channels cause mutex contention + GC pressure at 50–100 pkts/sec (media rate). Push with `sync.Pool` buffers is the pattern used by quic-go and fasthttp.

**Buffer contract:** Handler receives a `[]byte` from `sync.Pool`. If the handler needs to retain the data beyond its return, it must copy. The Link layer reclaims the buffer after the handler returns.

---

## 4. Wire Format

### Data Plane (25 bytes + payload, per mesh hop)

```
[1]  version_and_type   bits 0-3: version=1, bits 4-7: DATA=0/GOSSIP=1/ACK=2/PROBE=3/PROBE_ACK=4
[1]  current_hop_idx    O(1) forwarding: next hop = hops[current_hop_idx + 1]
[1]  hop_count          total hops in source route
[4]  src_hash_id        CRC32(srcUUID)
[4]  dst_hash_id        CRC32(dstUUID)
[4*] hops[]             4-byte CRC32 hashes of transit peers
[2]  payload_len        max 65535 bytes
[N]  payload            DTLS/SRTP ciphertext (unchanged from libwebrtc)
```

**TCP framing only:** prefix with 4-byte magic `0x50495052` ("PIPR") for stream framing. UDP and BLE omit it.

**Hops array starts at byte 11.**

### Control Plane (GOSSIP packets)

Uses full 16-byte UUIDs instead of 4-byte hashes. Serialized with `msgpack` (vmihailenco/msgpack) — 3–5x smaller than JSON, zero string allocations.

### Key Constants

```go
const (
    MeshHeaderMaxLen = 64      // headroom reserved at buffer start for zero-copy prepend
    HopsOffset       = 11      // byte offset where hops[] begins in data packet
    DataPlaneType    = 0x00
    GossipType       = 0x10
    ProbeType        = 0x30
    ProbeAckType     = 0x40
)
```

### Zero-Copy Header Prepend

`PeerProxy` reads from libwebrtc into `buf[MeshHeaderMaxLen:]`, leaving headroom. `Router.Send` writes the mesh header into `buf[MeshHeaderMaxLen-hdrLen:MeshHeaderMaxLen]` in-place — no allocation, no copy of payload.

```go
// In PeerProxy:
const MeshHeaderMaxLen = 64
n, _, _ := p.conn.ReadFromUDP((*bufPtr)[MeshHeaderMaxLen:])
payload := (*bufPtr)[MeshHeaderMaxLen : MeshHeaderMaxLen+n]
p.router.Send(p.peerID, payload, bufPtr)

// In Router.Send:
hdrLen := 11 + len(route.Hops)*4
startIdx := MeshHeaderMaxLen - hdrLen
writeHeader((*bufPtr)[startIdx:MeshHeaderMaxLen], ...)
route.Link.Send((*bufPtr)[startIdx : MeshHeaderMaxLen+len(payload)])
// bufPtr returned to pool inside Link.Send after transmission
```

### O(1) Transit Forwarding

```go
func (r *Router) Forward(raw []byte) {
    idx      := raw[1]
    hopCount := raw[2]

    if int(idx+1) >= int(hopCount) {
        // We are the destination — deliver to PeerProxy
        srcHash := binary.BigEndian.Uint32(raw[3:])
        payload := extractPayload(raw)
        r.mu.RLock()
        px := r.proxies[srcHash]
        r.mu.RUnlock()
        if px != nil {
            px.DeliverFromMesh(payload)
        }
        return
    }

    // Transit: increment hop index in-place, forward
    raw[1]++  // stateless O(1)
    nextHash := binary.BigEndian.Uint32(raw[HopsOffset + int(idx+1)*4:])
    r.mu.RLock()
    link := r.linkByHash(nextHash)
    r.mu.RUnlock()
    if link != nil {
        link.Send(raw) // zero-copy: same buffer
    }
}
```

---

## 5. UDP Proxy + STUN Termination (`mesh/proxy/`)

### Design

When Flutter wants to call peer X:
1. Flutter asks Go: `openProxy(peerID, remoteIcePwd)` → Go returns `localPort`
2. Go opens `127.0.0.1:localPort` UDP socket dedicated to peer X
3. Flutter creates `RTCPeerConnection` with `iceServers: [], iceTransportPolicy: "relay"`
4. Flutter injects single ICE candidate: `127.0.0.1:localPort`
5. libwebrtc sends all packets to this socket; Go classifies by first byte

### Packet Classification (RFC 5764)

```go
type pktClass uint8
const (
    pktSTUN    pktClass = iota // byte[0] in 0x00–0x03
    pktDTLS                    // byte[0] in 20–63
    pktSRTP                    // byte[0] in 128–191
    pktUnknown
)

func classifyPacket(b []byte) pktClass {
    if len(b) == 0 { return pktUnknown }
    switch {
    case b[0] <= 0x03:                   return pktSTUN
    case b[0] >= 20 && b[0] <= 63:      return pktDTLS
    case b[0] >= 128 && b[0] <= 191:    return pktSRTP
    default:                              return pktUnknown
    }
}
```

### STUN Termination with pion/stun

Go must respond to ICE STUN Binding Requests with `MESSAGE-INTEGRITY` (HMAC-SHA1 keyed by `remoteIcePwd`). Requires `github.com/pion/stun/v2`.

```go
import "github.com/pion/stun/v2"

type PeerProxy struct {
    peerID       string
    remoteIcePwd string  // extracted from remote SDP by Flutter
    conn         *net.UDPConn
    webrtcAddr   *net.UDPAddr  // ephemeral port of libwebrtc (from first ReadFromUDP)
    router       *router.Router
    pool         *sync.Pool
    stopCh       chan struct{}
}

func (p *PeerProxy) run() {
    for {
        bufPtr := p.pool.Get().(*[]byte)
        buf := *bufPtr

        // Read into headroom-offset position for zero-copy mesh encapsulation
        n, addr, err := p.conn.ReadFromUDP(buf[MeshHeaderMaxLen:])
        if err != nil { p.pool.Put(bufPtr); return }

        if p.webrtcAddr == nil { p.webrtcAddr = addr }

        pkt := buf[MeshHeaderMaxLen : MeshHeaderMaxLen+n]
        switch classifyPacket(pkt) {
        case pktSTUN:
            p.handleSTUN(pkt, addr)
            p.pool.Put(bufPtr) // STUN handled synchronously

        case pktDTLS, pktSRTP:
            // Router takes ownership; must call pool.Put(bufPtr) after send
            p.router.Send(p.peerID, pkt, bufPtr)
        }
    }
}

func (p *PeerProxy) handleSTUN(reqBytes []byte, clientAddr *net.UDPAddr) {
    msg := new(stun.Message)
    if err := msg.Unmarshal(reqBytes); err != nil { return }

    res := new(stun.Message)
    res.Build(
        msg,
        stun.BindingSuccess,
        &stun.XORMappedAddress{
            IP:   clientAddr.IP,    // client's address (127.0.0.1)
            Port: clientAddr.Port,  // client's EPHEMERAL port (not our listen port)
        },
        stun.NewShortTermIntegrity(p.remoteIcePwd), // HMAC-SHA1
        stun.Fingerprint,
    )
    p.conn.WriteToUDP(res.Raw, clientAddr)
}

func (p *PeerProxy) DeliverFromMesh(payload []byte) {
    if p.webrtcAddr == nil { return }
    p.conn.WriteToUDP(payload, p.webrtcAddr)
}
```

### Flutter Integration

```dart
// mesh_call_service.dart

class MeshCallService extends CallService {
  static const _channel = MethodChannel('piper/mesh');

  Future<void> attachMeshProxy(String peerId, String remoteSdp) async {
    final remoteIcePwd = _extractIcePwd(remoteSdp);
    final remoteUfrag  = _extractIceUfrag(remoteSdp);
    if (remoteIcePwd == null) throw Exception('no ice-pwd in SDP');

    final port = await _channel.invokeMethod<int>('openProxy', {
      'peerId': peerId,
      'remoteIcePwd': remoteIcePwd,
    });
    if (port == null || port < 0) throw Exception('proxy unavailable');

    await _pc!.addCandidate(RTCIceCandidate(
      'candidate:1 1 UDP 2130706431 127.0.0.1 $port typ host'
      '${remoteUfrag != null ? " ufrag $remoteUfrag" : ""}',
      '0', 0,
    ));
  }

  @override
  Future<void> _cleanup() async {
    if (peerId != null) {
      await _channel.invokeMethod('closeProxy', {'peerId': peerId});
    }
    await super._cleanup();
  }

  String? _extractIcePwd(String sdp) =>
      RegExp(r'a=ice-pwd:(\S+)').firstMatch(sdp)?.group(1);

  String? _extractIceUfrag(String sdp) =>
      RegExp(r'a=ice-ufrag:(\S+)').firstMatch(sdp)?.group(1);
}

// RTCPeerConnection config for mesh calls:
// {
//   'iceServers': [],
//   'iceTransportPolicy': 'relay',  // suppress host candidate gathering
// }
```

### FFI Bridge Additions

```go
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
    snap := e.node.MeshDiag()
    data, _ := json.Marshal(snap)
    return C.CString(string(data)) // Dart must call PiperFreeString() after use
}
// Note: PiperFreeString already exists in bridge.go:387
```

---

## 6. Gossip + Source Routing (`mesh/router/`)

### Peer Table Entry

```go
// Control plane: full UUIDs
type MeshPeer struct {
    ID       string      // full UUID (used in GOSSIP packets)
    HashID   uint32      // CRC32(ID) — used in DATA packet headers
    Name     string
    Addrs    []LinkAddr  // known addresses: {type, ip, port}
    Links    []LinkEntry // direct neighbors with quality metrics
    Version  uint64      // monotonically increasing; incremented ONLY by the owner
    LastSeen time.Time
}

type LinkEntry struct {
    PeerHashID uint32
    RTT        time.Duration // EMA-smoothed: new = old*0.8 + current*0.2
    LossRatio  float32       // EMA-smoothed
}

type LinkAddr struct {
    Type string // "tcp", "wifidirect", "ble"
    IP   string
    Port int
}
```

### Gossip Protocol

**Push:** on local table change, broadcast delta to all direct neighbors.
**Pull:** every 30s, request full table from a random neighbor (anti-entropy).

```go
type GossipPacket struct {
    From    string     `msgpack:"f"` // full UUID
    SeqNum  uint32     `msgpack:"s"`
    Peers   []MeshPeer `msgpack:"p"`
    IsDelta bool       `msgpack:"d"` // true = only changed entries
}
```

**Merge rule (CRDT-style):** accept a remote record for peer X only if `received.Version > local.Version`. Never increment another peer's Version — only propagate it.

### Dijkstra with Hysteresis

**Edge weight formula:**
```
weight = RTT_ms + (LossRatio² × 10000) + LinkTypePenalty

LinkTypePenalty: tcp=0, wifidirect=10, ble_relay=200
```

Loss is quadratic: 5% loss is tolerable, 15% is catastrophic — the formula reflects this.

**Hysteresis rules (prevent route flapping):**
1. **EMA smoothing:** RTT and LossRatio updated with α=0.2 (new = old×0.8 + current×0.2)
2. **Switch threshold:** only commit a new route if it's ≥25% better than the current active route
3. **Sticky routes:** do not recompute for an active call unless:
   - Link physically fails (Watchdog → `LinkDead`), OR
   - `LossRatio > 0.15` (15% sustained loss)

```go
const (
    EMARTTAlpha      = 0.2
    RouteHysteresis  = 0.25  // 25% improvement required to switch
    StickyLossThresh = 0.15
)
```

---

## 7. Self-Healing (`mesh/healer/`)

### Link State Machine

```
LinkHealthy  →(silent > 2s)→  LinkDegraded  →(3 probe failures)→  LinkDead
LinkDead     →(gossip/packet from peer)→  LinkHealthy
LinkDegraded →(any packet received)→      LinkHealthy
```

### Watchdog

Ticks every 500ms. Uses **implicit keepalive**: any received packet (media or gossip) resets the silence timer. Active ICMP-like probes only sent in `LinkDegraded` state.

```go
type Watchdog struct {
    router    *router.Router
    rerouter  *Rerouter
    links     map[string]*linkHealth
    mu        sync.Mutex
    probeTick time.Duration // 500ms
}

func (w *Watchdog) Tick() {
    now := time.Now()
    w.mu.Lock()
    defer w.mu.Unlock()

    for _, h := range w.links {
        silent := now.Sub(h.lastAckAt)

        switch h.state {
        case LinkHealthy:
            if silent > 2*time.Second {
                h.state = LinkDegraded
                h.failCount = 0
                w.sendProbe(h)
            }

        case LinkDegraded:
            h.failCount++ // increments every 500ms tick without response
            if h.failCount >= 3 {
                h.state = LinkDead
                w.rerouter.TriggerReroute(h.peerID, "link_dead")
            } else {
                w.sendProbe(h)
            }

        case LinkDead:
            // wait for gossip to signal recovery
        }
    }
}

// Separate handler for PROBE_ACK — validates seq to reject stale buffered packets
func (w *Watchdog) OnProbeAck(peerID string, seq uint32) {
    w.mu.Lock()
    defer w.mu.Unlock()
    h, ok := w.links[peerID]
    if !ok || h.probeSeq != seq { return } // stale/wrong ACK — ignore
    h.lastAckAt = time.Now()
    h.state = LinkHealthy
    h.failCount = 0
}
```

### Probe Packet Format

Type `0x30` (PROBE), 15 bytes:
```
[1]  version_and_type = 0x31
[1]  current_hop_idx  = 0
[1]  hop_count        = 1
[4]  src_hash_id
[4]  dst_hash_id
[4]  probe_seq        // uint32, matched in PROBE_ACK
```
PROBE_ACK (`0x40`) mirrors the structure with src/dst swapped.

### Recovery Timeline

```
T=0.0s  Link A→B fails
T=2.0s  Watchdog: silent > 2s → LinkDegraded, probe #1 sent
T=2.5s  Probe timeout → failCount=1, probe #2 sent
T=3.0s  Probe timeout → failCount=2, probe #3 sent
T=3.5s  Probe timeout → failCount=3 → LinkDead
T=3.5s  TriggerReroute("B", "link_dead")
T=3.6s  Dijkstra: A→C→B → CommitRoute (if 25%+ better than nothing)
T=3.6s  Media flows via new route. Total downtime: ~3.6 seconds.
T=60s   B recovers → gossip from C informs A → OnPacketReceived → LinkHealthy
T=60s   Recompute: A→B direct (25%+ better) → CommitRoute
```

---

## 8. Cutover Strategy (Phase 5)

### mesh.Node — Drop-in Replacement

`mesh.Node` implements the same public API as `core.Node`. The FFI bridge switches `NewNode()` call; Flutter is unaware.

```go
// Same methods as core.Node — no FFI changes needed:
func (n *Node) Start() error
func (n *Node) Stop()
func (n *Node) Send(text, toPeerID string)
func (n *Node) SendCallSignal(toPeerID, signalType, payload string) error
func (n *Node) PeerTable() []core.PeerRecord
func (n *Node) InjectPeers(records []core.PeerRecord)
func (n *Node) LocalEndpoint() core.PeerRecord
func (n *Node) Events() <-chan core.Event

// New mesh-only methods (added to FFI bridge):
func (n *Node) OpenProxy(peerID, remoteIcePwd string) (localPort int, err error)
func (n *Node) CloseProxy(peerID string)
func (n *Node) MeshDiag() MeshDiagSnapshot
```

### Transport Auto-Selection (Flutter)

```dart
Future<void> startCall(String peerId, String peerName, bool isVideo) async {
    final peer = PiperNode.instance.listPeers()
        .firstWhere((p) => p.id == peerId);

    // Direct LAN peer → existing CallService (standard WebRTC ICE)
    // Mesh-only peer  → MeshCallService (localhost proxy)
    final svc = peer.isDirectlyReachable
        ? CallService.instance
        : MeshCallService.instance;

    await svc.startCall(peerId, peerName, isVideo);
}
```

### WiFi Direct Integration

```
flutter-app/android/app/src/main/kotlin/WifiDirectPlugin.kt
flutter-app/lib/services/wifi_direct_service.dart
```

Android `WifiP2pManager` wrapped in a Flutter MethodChannel. Discovered peers injected via `PiperNode.injectPeers()` → Go mesh router adds as `wifidirect` Link.

---

## 9. Dependencies to Add

| Package | Purpose |
|---|---|
| `github.com/pion/stun/v2` | ICE-compliant STUN Binding Response with MESSAGE-INTEGRITY |
| `github.com/vmihailenco/msgpack/v5` | Compact binary serialization for gossip packets |

Existing: `github.com/grandcat/zeroconf`, `golang.org/x/crypto`, `github.com/google/uuid` — unchanged.

---

## 10. Implementation Phases

| Phase | Package | Deliverable |
|---|---|---|
| 1 | `mesh/transport/` | Link interface + TCP link + unit tests |
| 2 | `mesh/router/` | PeerTable + Gossip + Dijkstra + hysteresis |
| 3 | `mesh/proxy/` | UDP Proxy + STUN termination + pion/stun |
| 4 | `mesh/healer/` | Watchdog + Rerouter + probe protocol |
| 5 | `mesh/node.go` + FFI + Flutter | Cutover: mesh.Node replaces core.Node |

Each phase is independently testable. The app remains fully functional throughout.
