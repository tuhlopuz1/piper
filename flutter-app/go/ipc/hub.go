// Package ipc provides the local WebSocket + HTTP server that Flutter connects to.
package ipc

import (
	"encoding/json"
	"log"
	"net"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

// Event is the envelope sent from the Go daemon to Flutter over WebSocket.
type Event struct {
	Event string `json:"event"`
	Data  any    `json:"data"`
}

// Sender is implemented by transport.Manager. It lets the HTTP handlers
// call into the networking layer without a circular import.
type Sender interface {
	GetStatus() map[string]any
	GetPeers() []map[string]any
	SendText(to, text string) error
	SendCallSignal(to, sdpType, sdp, candidate string) error
	EndCall(to string) error
	SetProfile(name, avatarColor string)
}

// Hub manages connected Flutter WebSocket clients and broadcasts events to them.
type Hub struct {
	mu        sync.RWMutex
	clients   map[*wsClient]struct{}
	broadcast chan []byte
}

type wsClient struct {
	conn *websocket.Conn
	send chan []byte
}

func NewHub() *Hub {
	return &Hub{
		clients:   make(map[*wsClient]struct{}),
		broadcast: make(chan []byte, 512),
	}
}

// Run processes the broadcast channel. Call in a goroutine.
func (h *Hub) Run() {
	for msg := range h.broadcast {
		h.mu.RLock()
		for c := range h.clients {
			select {
			case c.send <- msg:
			default:
				// slow client — drop message
			}
		}
		h.mu.RUnlock()
	}
}

// Broadcast sends an event with arbitrary data to all Flutter clients.
func (h *Hub) Broadcast(event string, data any) {
	b, _ := json.Marshal(Event{Event: event, Data: data})
	select {
	case h.broadcast <- b:
	default:
		log.Printf("[ipc] broadcast channel full, dropping event: %s", event)
	}
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

func (h *Hub) serveWS(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[ipc] WS upgrade error: %v", err)
		return
	}
	c := &wsClient{conn: conn, send: make(chan []byte, 128)}

	h.mu.Lock()
	h.clients[c] = struct{}{}
	h.mu.Unlock()

	log.Printf("[ipc] Flutter client connected")

	// Write pump
	go func() {
		defer func() {
			conn.Close()
			h.mu.Lock()
			delete(h.clients, c)
			h.mu.Unlock()
			log.Printf("[ipc] Flutter client disconnected")
		}()
		for msg := range c.send {
			if err := conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		}
	}()

	// Read pump — drain incoming frames to detect disconnection
	for {
		if _, _, err := conn.ReadMessage(); err != nil {
			close(c.send)
			return
		}
	}
}

// ListenAndServe starts the HTTP server on a random localhost port,
// registers all routes, and returns the chosen port.
func (h *Hub) ListenAndServe(s Sender) (int, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	port := l.Addr().(*net.TCPAddr).Port

	mux := http.NewServeMux()
	mux.HandleFunc("/ws", h.serveWS)
	registerAPI(mux, s)

	go func() {
		if err := http.Serve(l, mux); err != nil {
			log.Printf("[ipc] HTTP server: %v", err)
		}
	}()

	log.Printf("[ipc] HTTP server on 127.0.0.1:%d", port)
	return port, nil
}
