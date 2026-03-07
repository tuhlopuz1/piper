package proxy_test

import (
	"net"
	"testing"
	"time"

	"github.com/catsi/piper/mesh/proxy"
	"github.com/pion/stun/v2"
)

// mockRouter captures Send calls
type mockRouter struct{ sent [][]byte }

func (m *mockRouter) Send(peerID string, payload []byte, bufPtr *[]byte) {
	cp := make([]byte, len(payload))
	copy(cp, payload)
	m.sent = append(m.sent, cp)
}

func TestPeerProxySTUNResponse(t *testing.T) {
	icePwd := "testpassword1234"
	mr := &mockRouter{}

	pp, err := proxy.NewPeerProxy("peer-x", icePwd, mr)
	if err != nil {
		t.Fatal(err)
	}
	defer pp.Close()

	// Connect a UDP client (simulates libwebrtc)
	clientConn, err := net.DialUDP("udp", nil, pp.LocalAddr())
	if err != nil {
		t.Fatal(err)
	}
	defer clientConn.Close()

	// Build a real STUN Binding Request
	req, err := stun.Build(stun.TransactionID, stun.BindingRequest)
	if err != nil {
		t.Fatal(err)
	}

	clientConn.SetDeadline(time.Now().Add(3 * time.Second))
	if _, err := clientConn.Write(req.Raw); err != nil {
		t.Fatal(err)
	}

	// Expect a STUN response back
	buf := make([]byte, 1500)
	n, err := clientConn.Read(buf)
	if err != nil {
		t.Fatalf("no STUN response: %v", err)
	}

	resp := new(stun.Message)
	if err := stun.Decode(buf[:n], resp); err != nil {
		t.Fatalf("invalid STUN response: %v", err)
	}
	if resp.Type != stun.BindingSuccess {
		t.Fatalf("want BindingSuccess got %v", resp.Type)
	}
}

func TestPeerProxyForwardsDTLS(t *testing.T) {
	mr := &mockRouter{}
	pp, err := proxy.NewPeerProxy("peer-x", "pwd", mr)
	if err != nil {
		t.Fatal(err)
	}
	defer pp.Close()

	client, _ := net.DialUDP("udp", nil, pp.LocalAddr())
	defer client.Close()

	// DTLS first byte = 22 (0x16)
	dtlsPkt := append([]byte{22}, []byte("fake dtls content")...)
	client.SetDeadline(time.Now().Add(2 * time.Second))
	client.Write(dtlsPkt)

	time.Sleep(100 * time.Millisecond)
	if len(mr.sent) == 0 {
		t.Fatal("DTLS packet not forwarded to router")
	}
	if mr.sent[0][0] != 22 {
		t.Fatalf("wrong first byte: %x", mr.sent[0][0])
	}
}
