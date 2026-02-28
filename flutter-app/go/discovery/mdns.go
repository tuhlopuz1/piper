// Package discovery advertises the local Piper instance via mDNS and
// browses for other Piper instances on the same LAN.
package discovery

import (
	"context"
	"log"
	"strings"

	"github.com/grandcat/zeroconf"
)

const serviceType = "_piper._tcp"
const domain = "local."

// PeerInfo holds the connection details of a discovered peer.
type PeerInfo struct {
	ID   string
	Name string
	IP   string
	Port int
}

// Service handles mDNS registration and browsing.
type Service struct {
	id      string
	name    string
	port    int
	onFound func(PeerInfo)
	server  *zeroconf.Server
	cancel  context.CancelFunc
	known   map[string]struct{} // set of known peer IDs (not thread-safe, only used in Run goroutine)
}

// New registers the local instance on mDNS and returns a Service ready to Run.
// onFound is called (in the Run goroutine) when a new peer is discovered.
func New(id, name string, port int, onFound func(PeerInfo)) (*Service, error) {
	txt := []string{"id=" + id}
	server, err := zeroconf.Register(name, serviceType, domain, port, txt, nil)
	if err != nil {
		return nil, err
	}
	log.Printf("[mdns] registered as %q on port %d", name, port)
	return &Service{
		id:      id,
		name:    name,
		port:    port,
		onFound: onFound,
		server:  server,
		known:   make(map[string]struct{}),
	}, nil
}

// Run browses for peers until Shutdown is called. Call in a goroutine.
func (s *Service) Run() {
	ctx, cancel := context.WithCancel(context.Background())
	s.cancel = cancel

	resolver, err := zeroconf.NewResolver(nil)
	if err != nil {
		log.Printf("[mdns] resolver error: %v", err)
		return
	}

	entries := make(chan *zeroconf.ServiceEntry)
	go func() {
		if err := resolver.Browse(ctx, serviceType, domain, entries); err != nil {
			log.Printf("[mdns] browse error: %v", err)
		}
	}()

	log.Printf("[mdns] browsing for peers...")
	for {
		select {
		case entry, ok := <-entries:
			if !ok {
				return
			}
			s.handleEntry(entry)
		case <-ctx.Done():
			return
		}
	}
}

func (s *Service) handleEntry(entry *zeroconf.ServiceEntry) {
	if len(entry.AddrIPv4) == 0 || entry.Port == 0 {
		return
	}

	// Parse peer ID from TXT records
	peerID := ""
	for _, txt := range entry.Text {
		if strings.HasPrefix(txt, "id=") {
			peerID = strings.TrimPrefix(txt, "id=")
		}
	}
	if peerID == "" || peerID == s.id {
		return // unknown format or our own advertisement
	}
	if _, seen := s.known[peerID]; seen {
		return // already connected or connecting
	}
	s.known[peerID] = struct{}{}

	info := PeerInfo{
		ID:   peerID,
		Name: entry.Instance,
		IP:   entry.AddrIPv4[0].String(),
		Port: entry.Port,
	}
	log.Printf("[mdns] found peer: %s @ %s:%d", info.Name, info.IP, info.Port)
	s.onFound(info)
}

// Shutdown unregisters the mDNS service and stops browsing.
func (s *Service) Shutdown() {
	if s.cancel != nil {
		s.cancel()
	}
	s.server.Shutdown()
}
