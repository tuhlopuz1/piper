// Package transport handles TCP peer connections and message routing.
package transport

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"sync"
	"time"

	"piper/discovery"
	"piper/ipc"
)

// Manager manages all active peer connections.
type Manager struct {
	id          string
	name        string
	avatarColor string
	hub         *ipc.Hub

	mu      sync.RWMutex
	peers   map[string]*peer // key: peer ID
	localIP string
	tcpPort int
}

func NewManager(id, name string, hub *ipc.Hub) *Manager {
	return &Manager{
		id:      id,
		name:    name,
		hub:     hub,
		peers:   make(map[string]*peer),
		localIP: getLocalIP(),
	}
}

// ListenAndServe accepts incoming peer TCP connections on the given port.
func (m *Manager) ListenAndServe(port int) error {
	m.tcpPort = port
	ln, err := net.Listen("tcp", fmt.Sprintf("0.0.0.0:%d", port))
	if err != nil {
		return err
	}
	log.Printf("[transport] TCP server listening on :%d", port)

	for {
		conn, err := ln.Accept()
		if err != nil {
			return err
		}
		go m.handleIncoming(conn)
	}
}

// handleIncoming runs the listener-side handshake for a new connection.
func (m *Manager) handleIncoming(conn net.Conn) {
	p := newPeer(conn, m.onMsg, m.onClose)
	if err := p.recvHello(m.id, m.name); err != nil {
		log.Printf("[transport] handshake error from %s: %v", conn.RemoteAddr(), err)
		conn.Close()
		return
	}
	m.register(p)
}

// Connect dials a peer discovered via mDNS. Runs in its own goroutine.
func (m *Manager) Connect(info discovery.PeerInfo) {
	m.mu.RLock()
	_, exists := m.peers[info.ID]
	m.mu.RUnlock()
	if exists {
		return
	}

	go func() {
		addr := fmt.Sprintf("%s:%d", info.IP, info.Port)
		conn, err := net.DialTimeout("tcp", addr, 5*time.Second)
		if err != nil {
			log.Printf("[transport] cannot connect to %s: %v", addr, err)
			return
		}
		p := newPeer(conn, m.onMsg, m.onClose)
		p.id = info.ID
		p.name = info.Name
		p.ip = info.IP
		if err := p.sendHello(m.id, m.name); err != nil {
			log.Printf("[transport] hello send error: %v", err)
			conn.Close()
			return
		}
		m.register(p)
	}()
}

// register adds the peer to the active map (deduplicates by ID) and
// announces it to Flutter, then starts the peer's read loop.
func (m *Manager) register(p *peer) {
	m.mu.Lock()
	if _, exists := m.peers[p.id]; exists {
		m.mu.Unlock()
		p.conn.Close() // duplicate — drop
		return
	}
	m.peers[p.id] = p
	m.mu.Unlock()

	log.Printf("[transport] peer connected: %s (%s)", p.name, p.id)
	m.hub.Broadcast("peer_found", map[string]any{
		"id":   p.id,
		"name": p.name,
		"ip":   p.ip,
	})

	go p.readLoop()
}

// onClose is called by a peer's readLoop when the connection closes.
func (m *Manager) onClose(p *peer) {
	m.mu.Lock()
	delete(m.peers, p.id)
	m.mu.Unlock()

	log.Printf("[transport] peer disconnected: %s", p.id)
	m.hub.Broadcast("peer_lost", map[string]any{"id": p.id})
}

// onMsg routes an incoming peer message to Flutter via the hub.
func (m *Manager) onMsg(p *peer, msg peerMsg) {
	switch msg.Type {
	case "text":
		var pl struct {
			Text string `json:"text"`
			TS   int64  `json:"ts"`
		}
		_ = json.Unmarshal(msg.Payload, &pl)
		m.hub.Broadcast("message", map[string]any{
			"from": p.id,
			"name": p.name,
			"text": pl.Text,
			"ts":   pl.TS,
		})

	case "call_signal":
		var pl map[string]any
		_ = json.Unmarshal(msg.Payload, &pl)
		pl["from"] = p.id
		m.hub.Broadcast("call_signal", pl)

	case "call_end":
		m.hub.Broadcast("call_ended", map[string]any{"peer_id": p.id})

	default:
		log.Printf("[transport] unknown message type from %s: %s", p.id, msg.Type)
	}
}

// Shutdown closes all peer connections.
func (m *Manager) Shutdown() {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, p := range m.peers {
		p.conn.Close()
	}
}

// ── ipc.Sender interface ──────────────────────────────────────────────────────

func (m *Manager) GetStatus() map[string]any {
	return map[string]any{
		"id":      m.id,
		"name":    m.name,
		"ip":      m.localIP,
		"port":    m.tcpPort,
	}
}

func (m *Manager) GetPeers() []map[string]any {
	m.mu.RLock()
	defer m.mu.RUnlock()
	result := make([]map[string]any, 0, len(m.peers))
	for _, p := range m.peers {
		result = append(result, map[string]any{
			"id":   p.id,
			"name": p.name,
			"ip":   p.ip,
		})
	}
	return result
}

func (m *Manager) SendText(to, text string) error {
	p := m.get(to)
	if p == nil {
		return fmt.Errorf("peer not found: %s", to)
	}
	payload, _ := json.Marshal(map[string]any{"text": text, "ts": time.Now().Unix()})
	return p.send(peerMsg{Type: "text", From: m.id, Payload: payload})
}

func (m *Manager) SendCallSignal(to, sdpType, sdp, candidate string) error {
	p := m.get(to)
	if p == nil {
		return fmt.Errorf("peer not found: %s", to)
	}
	payload, _ := json.Marshal(map[string]any{
		"sdp_type":  sdpType,
		"sdp":       sdp,
		"candidate": candidate,
	})
	return p.send(peerMsg{Type: "call_signal", From: m.id, Payload: payload})
}

func (m *Manager) EndCall(to string) error {
	p := m.get(to)
	if p == nil {
		return nil
	}
	return p.send(peerMsg{Type: "call_end", From: m.id})
}

func (m *Manager) SetProfile(name, color string) {
	if name != "" {
		m.name = name
	}
	if color != "" {
		m.avatarColor = color
	}
}

func (m *Manager) get(id string) *peer {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.peers[id]
}

func getLocalIP() string {
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err != nil {
		return "127.0.0.1"
	}
	defer conn.Close()
	return conn.LocalAddr().(*net.UDPAddr).IP.String()
}
