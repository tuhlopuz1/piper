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

	// Identity public keys (omitempty so older peers without them still gossip).
	IdentityX25519Pub  []byte `msgpack:"ix,omitempty"`
	IdentityEd25519Pub []byte `msgpack:"ie,omitempty"`
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
	if p.ID == pt.localID {
		return false
	}
	pt.mu.Lock()
	defer pt.mu.Unlock()

	if existing, ok := pt.byID[p.ID]; ok {
		if p.Version <= existing.Version {
			return false
		}
	}
	p.LastSeen = time.Now()
	cp := p
	pt.byID[p.ID] = &cp
	pt.byHash[p.HashID] = &cp
	return true
}

func (pt *PeerTable) Get(id string) *MeshPeer {
	pt.mu.RLock()
	defer pt.mu.RUnlock()
	return pt.byID[id]
}

func (pt *PeerTable) GetByHash(h uint32) *MeshPeer {
	pt.mu.RLock()
	defer pt.mu.RUnlock()
	return pt.byHash[h]
}

func (pt *PeerTable) All() []MeshPeer {
	pt.mu.RLock()
	defer pt.mu.RUnlock()
	out := make([]MeshPeer, 0, len(pt.byID))
	for _, p := range pt.byID {
		out = append(out, *p)
	}
	return out
}
