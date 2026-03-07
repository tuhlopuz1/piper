package proxy

import (
	"net"
	"sync"

	"github.com/pion/stun/v2"
)

// Router is implemented by the mesh routing layer to forward payloads.
type Router interface {
	Send(peerID string, payload []byte, bufPtr *[]byte)
}

type PeerProxy struct {
	peerID       string
	remoteIcePwd string
	conn         *net.UDPConn
	webrtcAddr   *net.UDPAddr
	router       Router
	stopCh       chan struct{}
	mu           sync.Mutex
}

func NewPeerProxy(peerID, remoteIcePwd string, r Router) (*PeerProxy, error) {
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		return nil, err
	}

	pp := &PeerProxy{
		peerID:       peerID,
		remoteIcePwd: remoteIcePwd,
		conn:         conn,
		router:       r,
		stopCh:       make(chan struct{}),
	}
	go pp.run()
	return pp, nil
}

func (p *PeerProxy) LocalAddr() *net.UDPAddr {
	return p.conn.LocalAddr().(*net.UDPAddr)
}

func (p *PeerProxy) Close() {
	select {
	case <-p.stopCh:
	default:
		close(p.stopCh)
	}
	p.conn.Close()
}

func (p *PeerProxy) DeliverFromMesh(payload []byte) {
	p.mu.Lock()
	addr := p.webrtcAddr
	p.mu.Unlock()
	if addr == nil {
		return
	}
	p.conn.WriteToUDP(payload, addr)
}

func (p *PeerProxy) run() {
	buf := make([]byte, 65600)
	for {
		select {
		case <-p.stopCh:
			return
		default:
		}

		n, addr, err := p.conn.ReadFromUDP(buf)
		if err != nil {
			return
		}

		p.mu.Lock()
		if p.webrtcAddr == nil {
			p.webrtcAddr = addr
		}
		p.mu.Unlock()

		pkt := buf[:n]

		switch Classify(pkt) {
		case PktSTUN:
			p.handleSTUN(pkt, addr)
		case PktDTLS, PktSRTP:
			cp := make([]byte, n)
			copy(cp, pkt)
			p.router.Send(p.peerID, cp, nil)
		}
	}
}

func (p *PeerProxy) handleSTUN(reqBytes []byte, clientAddr *net.UDPAddr) {
	msg := new(stun.Message)
	if err := stun.Decode(reqBytes, msg); err != nil {
		return
	}

	resp := new(stun.Message)
	if err := resp.Build(
		msg,
		stun.BindingSuccess,
		&stun.XORMappedAddress{IP: clientAddr.IP, Port: clientAddr.Port},
		stun.NewShortTermIntegrity(p.remoteIcePwd),
		stun.Fingerprint,
	); err != nil {
		return
	}

	p.conn.WriteToUDP(resp.Raw, clientAddr)
}
