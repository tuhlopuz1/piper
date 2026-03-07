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

func (m *MockLink) ID() string                     { return m.id }
func (m *MockLink) PeerID() string                 { return m.peerID }
func (m *MockLink) Send(pkt []byte) error          { m.sent = append(m.sent, pkt); return nil }
func (m *MockLink) SetOnReceive(h func([]byte))    { m.handler = h }
func (m *MockLink) Quality() transport.LinkQuality { return m.quality }
func (m *MockLink) Close()                         {}

func (m *MockLink) Deliver(pkt []byte) { // simulate incoming packet
	if m.handler != nil {
		m.handler(pkt)
	}
}

func TestMockLinkImplementsLink(t *testing.T) {
	var _ transport.Link = &MockLink{}
}
