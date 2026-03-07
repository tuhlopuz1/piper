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
	if err != nil {
		return
	}
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
		case <-g.stopCh:
			return
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
	if err != nil {
		return
	}

	// Prefix with type byte
	frame := append([]byte{0x10}, data...)

	g.mu.RLock()
	defer g.mu.RUnlock()
	for _, l := range g.links {
		l.Send(frame) //nolint:errcheck
	}
}
