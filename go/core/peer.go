package core

import (
	"fmt"
	"net"
	"sync"
	"time"
)

// PeerState represents the lifecycle state of a peer connection.
type PeerState int

const (
	PeerConnecting PeerState = iota
	PeerConnected
	PeerDisconnected
)

// PeerInfo holds the runtime state of a discovered/connected peer.
type PeerInfo struct {
	ID          string    // stable UUID advertised via mDNS/UDP
	Name        string    // canonical name as reported by the peer
	DisplayName string    // unique display name shown in the UI (may have #2, #3 suffix)
	Addr        net.Addr  // remote TCP address
	State       PeerState
	LastSeen    time.Time
	PubKey      []byte   // X25519 public key received in Hello (32 bytes)
	SharedKey   [32]byte // ChaCha20-Poly1305 key derived via ECDH; zero until handshake complete
	IsRelay     bool     // peer is reachable only via relay path
	RelayVia    string   // peer ID of direct next-hop relay node
	RelayHops   int      // hop count from this node to peer
}

// PeerEvent is emitted to the application layer when peers join/leave.
type PeerEvent struct {
	Peer *PeerInfo
	Kind PeerEventKind
}

// PeerEventKind categorises peer lifecycle events.
type PeerEventKind int

const (
	PeerJoined      PeerEventKind = iota
	PeerNameUpdated               // display name may have changed
	PeerLeft
)

// PeerManager tracks all known peers keyed by peer ID.
type PeerManager struct {
	mu    sync.RWMutex
	peers map[string]*PeerInfo
}

// NewPeerManager creates an empty PeerManager.
func NewPeerManager() *PeerManager {
	return &PeerManager{peers: make(map[string]*PeerInfo)}
}

// Upsert adds or updates a peer and returns (info, wasNew).
// It assigns a unique DisplayName, appending #2, #3, … if the name is already taken.
func (pm *PeerManager) Upsert(id, name string, addr net.Addr, state PeerState) (*PeerInfo, bool) {
	pm.mu.Lock()
	defer pm.mu.Unlock()

	if existing, ok := pm.peers[id]; ok {
		if existing.Name != name {
			existing.Name = name
			existing.DisplayName = pm.uniqueDisplayName(name, id)
		}
		existing.Addr = addr
		existing.State = state
		existing.LastSeen = time.Now()
		return existing, false
	}

	displayName := pm.uniqueDisplayName(name, id)
	p := &PeerInfo{
		ID:          id,
		Name:        name,
		DisplayName: displayName,
		Addr:        addr,
		State:       state,
		LastSeen:    time.Now(),
	}
	pm.peers[id] = p
	return p, true
}

// uniqueDisplayName returns a display name that is not used by any other peer.
// It tries name, then name#2, name#3, … until it finds a free slot.
// excludeID is the peer ID being upserted (so we don't conflict with ourselves).
func (pm *PeerManager) uniqueDisplayName(name, excludeID string) string {
	taken := make(map[string]bool)
	for id, p := range pm.peers {
		if id != excludeID {
			taken[p.DisplayName] = true
		}
	}
	if !taken[name] {
		return name
	}
	for i := 2; ; i++ {
		candidate := fmt.Sprintf("%s#%d", name, i)
		if !taken[candidate] {
			return candidate
		}
	}
}

// SetSharedKey stores the derived ECDH shared key for a peer.
func (pm *PeerManager) SetSharedKey(id string, key [32]byte) {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	if p, ok := pm.peers[id]; ok {
		p.SharedKey = key
	}
}

// SetPubKey stores the peer's X25519 public key.
func (pm *PeerManager) SetPubKey(id string, pub []byte) {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	if p, ok := pm.peers[id]; ok {
		p.PubKey = pub
	}
}

// SetState updates only the connection state of a peer.
func (pm *PeerManager) SetState(id string, state PeerState) {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	if p, ok := pm.peers[id]; ok {
		p.State = state
		p.LastSeen = time.Now()
	}
}

// SetRelay marks a peer as relay-reachable (or direct when isRelay=false).
func (pm *PeerManager) SetRelay(id, via string, hops int, isRelay bool) {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	if p, ok := pm.peers[id]; ok {
		p.IsRelay = isRelay
		p.RelayVia = via
		p.RelayHops = hops
		p.LastSeen = time.Now()
	}
}

// Get returns the peer info for id, or nil if unknown.
func (pm *PeerManager) Get(id string) *PeerInfo {
	pm.mu.RLock()
	defer pm.mu.RUnlock()
	return pm.peers[id]
}

// List returns a snapshot of all peers regardless of state.
func (pm *PeerManager) List() []*PeerInfo {
	pm.mu.RLock()
	defer pm.mu.RUnlock()
	out := make([]*PeerInfo, 0, len(pm.peers))
	for _, p := range pm.peers {
		out = append(out, p)
	}
	return out
}

// Remove deletes a peer by ID.
func (pm *PeerManager) Remove(id string) {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	delete(pm.peers, id)
}
