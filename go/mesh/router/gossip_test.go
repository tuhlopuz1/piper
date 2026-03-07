package router_test

import (
	"testing"
	"time"

	"github.com/catsi/piper/mesh/router"
	"github.com/catsi/piper/mesh/transport"
)

// mockLink is a local transport.Link mock for gossip tests.
type mockLink struct {
	id      string
	peerID  string
	sent    [][]byte
	handler func([]byte)
}

func (m *mockLink) ID() string                     { return m.id }
func (m *mockLink) PeerID() string                 { return m.peerID }
func (m *mockLink) Send(pkt []byte) error          { m.sent = append(m.sent, pkt); return nil }
func (m *mockLink) SetOnReceive(h func([]byte))    { m.handler = h }
func (m *mockLink) Quality() transport.LinkQuality { return transport.LinkQuality{} }
func (m *mockLink) Close()                         {}

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
	if err != nil {
		t.Fatal(err)
	}
	got, err := router.DecodeGossip(data)
	if err != nil {
		t.Fatal(err)
	}
	if got.From != "peer-a" {
		t.Fatalf("From: want peer-a got %s", got.From)
	}
	if got.SeqNum != 42 {
		t.Fatalf("SeqNum: want 42 got %d", got.SeqNum)
	}
	if len(got.Peers) != 1 {
		t.Fatalf("Peers len: want 1 got %d", len(got.Peers))
	}
	if got.Peers[0].Name != "Bob" {
		t.Fatal("peer name mismatch")
	}
}

func TestGossipAppliesUpdatesToTable(t *testing.T) {
	pt := router.NewPeerTable("self")
	g := router.NewGossip("self", pt, 10*time.Millisecond, 50*time.Millisecond)

	ml := &mockLink{id: "link-a", peerID: "peer-a"}
	g.AddLink(ml)

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
	if got == nil {
		t.Fatal("peer-b not in table after gossip")
	}
	if got.Name != "Bob" {
		t.Fatal("wrong name")
	}
}
