package core

// Minimal TURN server (RFC 5766 subset) for WiFi Direct call relay.
//
// Problem: On Android hotspot mode, libwebrtc cannot enumerate the AP
// interface (e.g. 192.168.43.1) via ConnectivityManager. This TURN server
// binds to 0.0.0.0 using Go's net package (which DOES see all interfaces),
// so WebRTC can relay media through it even when direct ICE fails.
//
// Protocol subset implemented:
//   ALLOCATE (request/response, with 401 challenge)
//   REFRESH
//   CREATE-PERMISSION
//   SEND indication (client → peer via relay)
//   DATA indication (peer → client via relay)
//   CHANNEL-BIND + ChannelData (optional, for efficiency)

import (
	"encoding/binary"
	"log"
	"net"
	"sync"
	"time"
)

// ── STUN/TURN constants ───────────────────────────────────────────────────────

const (
	stunMagic = uint32(0x2112A442)

	msgAllocateReq     = uint16(0x0003)
	msgAllocateOK      = uint16(0x0103)
	msgAllocateErr     = uint16(0x0113)
	msgRefreshReq      = uint16(0x0004)
	msgRefreshOK       = uint16(0x0104)
	msgCreatePermReq   = uint16(0x0008)
	msgCreatePermOK    = uint16(0x0108)
	msgSendInd         = uint16(0x0016)
	msgDataInd         = uint16(0x0017)
	msgChannelBindReq  = uint16(0x0009)
	msgChannelBindOK   = uint16(0x0109)
	msgBindingReq      = uint16(0x0001)
	msgBindingOK       = uint16(0x0101)

	attrXorMappedAddr     = uint16(0x0020)
	attrXorRelayedAddr    = uint16(0x0016)
	attrLifetime          = uint16(0x000D)
	attrXorPeerAddr       = uint16(0x0012)
	attrData              = uint16(0x0013)
	attrReqTransport      = uint16(0x0019)
	attrChannelNumber     = uint16(0x000C)
	attrErrorCode         = uint16(0x0009)
	attrRealm             = uint16(0x0014)
	attrNonce             = uint16(0x0015)
	attrUsername          = uint16(0x0006)
	attrMsgIntegrity      = uint16(0x0008)
	attrFingerprint       = uint16(0x8028)

	turnRealm    = "piper"
	turnNonce    = "piperturn"
	allocLifetime = uint32(600)
)

// ── STUN message builder ──────────────────────────────────────────────────────

type stunMsg struct {
	msgType uint16
	txID    [12]byte
	attrs   []byte
}

func parseStun(buf []byte) (*stunMsg, bool) {
	if len(buf) < 20 {
		return nil, false
	}
	// First two bits must be 0b00 for STUN (not channel data)
	if buf[0]&0xC0 != 0 {
		return nil, false
	}
	magic := binary.BigEndian.Uint32(buf[4:8])
	if magic != stunMagic {
		return nil, false
	}
	length := binary.BigEndian.Uint16(buf[2:4])
	if int(length)+20 > len(buf) {
		return nil, false
	}
	m := &stunMsg{
		msgType: binary.BigEndian.Uint16(buf[0:2]),
		attrs:   buf[20 : 20+length],
	}
	copy(m.txID[:], buf[8:20])
	return m, true
}

func (m *stunMsg) getAttr(attrType uint16) ([]byte, bool) {
	b := m.attrs
	for len(b) >= 4 {
		t := binary.BigEndian.Uint16(b[0:2])
		l := binary.BigEndian.Uint16(b[2:4])
		padded := (int(l) + 3) &^ 3
		if len(b) < 4+padded {
			break
		}
		if t == attrType {
			return b[4 : 4+l], true
		}
		b = b[4+padded:]
	}
	return nil, false
}

type stunBuilder struct {
	buf []byte
}

func newStunBuilder(msgType uint16, txID [12]byte) *stunBuilder {
	b := &stunBuilder{buf: make([]byte, 20)}
	binary.BigEndian.PutUint16(b.buf[0:2], msgType)
	binary.BigEndian.PutUint32(b.buf[4:8], stunMagic)
	copy(b.buf[8:20], txID[:])
	return b
}

func (b *stunBuilder) addAttr(attrType uint16, val []byte) {
	padded := (len(val) + 3) &^ 3
	hdr := make([]byte, 4)
	binary.BigEndian.PutUint16(hdr[0:2], attrType)
	binary.BigEndian.PutUint16(hdr[2:4], uint16(len(val)))
	b.buf = append(b.buf, hdr...)
	b.buf = append(b.buf, val...)
	for i := len(val); i < padded; i++ {
		b.buf = append(b.buf, 0)
	}
}

func (b *stunBuilder) addU32Attr(attrType uint16, v uint32) {
	var buf [4]byte
	binary.BigEndian.PutUint32(buf[:], v)
	b.addAttr(attrType, buf[:])
}

func (b *stunBuilder) addXorAddr(attrType uint16, ip net.IP, port int, txID [12]byte) {
	ip4 := ip.To4()
	if ip4 == nil {
		return
	}
	val := make([]byte, 8)
	val[0] = 0x00
	val[1] = 0x01 // IPv4
	xPort := uint16(port) ^ uint16(stunMagic>>16)
	binary.BigEndian.PutUint16(val[2:4], xPort)
	xIP := binary.BigEndian.Uint32(ip4) ^ stunMagic
	binary.BigEndian.PutUint32(val[4:8], xIP)
	b.addAttr(attrType, val)
}

func (b *stunBuilder) bytes() []byte {
	body := len(b.buf) - 20
	binary.BigEndian.PutUint16(b.buf[2:4], uint16(body))
	return b.buf
}

// ── parseXorAddr ──────────────────────────────────────────────────────────────

func parseXorAddr(val []byte, txID [12]byte) *net.UDPAddr {
	if len(val) < 8 {
		return nil
	}
	if val[1] != 0x01 { // IPv4 only
		return nil
	}
	port := int(binary.BigEndian.Uint16(val[2:4]) ^ uint16(stunMagic>>16))
	xip := binary.BigEndian.Uint32(val[4:8]) ^ stunMagic
	ip := make(net.IP, 4)
	binary.BigEndian.PutUint32(ip, xip)
	return &net.UDPAddr{IP: ip, Port: port}
}

// ── Allocation ────────────────────────────────────────────────────────────────

type turnAlloc struct {
	clientAddr *net.UDPAddr
	relayConn  *net.UDPConn
	expiry     time.Time
	perms      map[string]bool // permitted peer IPs
	channels   map[uint16]*net.UDPAddr
	mu         sync.Mutex
}

func (a *turnAlloc) addPerm(ip string) {
	a.mu.Lock()
	a.perms[ip] = true
	a.mu.Unlock()
}

func (a *turnAlloc) hasPerm(ip string) bool {
	a.mu.Lock()
	ok := a.perms[ip]
	a.mu.Unlock()
	return ok
}

// ── TURNServer ────────────────────────────────────────────────────────────────

// TURNServer is a minimal TURN relay server. It binds to 0.0.0.0 so it is
// reachable on all interfaces, including the WiFi hotspot AP interface that
// libwebrtc cannot enumerate.
type TURNServer struct {
	conn   *net.UDPConn
	allocs map[string]*turnAlloc // key: client addr string
	mu     sync.Mutex
	done   chan struct{}
	port   int
}

// NewTURNServer starts a TURN server on an OS-assigned UDP port.
func NewTURNServer() (*TURNServer, error) {
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4zero, Port: 0})
	if err != nil {
		return nil, err
	}
	s := &TURNServer{
		conn:   conn,
		allocs: make(map[string]*turnAlloc),
		done:   make(chan struct{}),
		port:   conn.LocalAddr().(*net.UDPAddr).Port,
	}
	go s.serve()
	go s.gcLoop()
	return s, nil
}

// Port returns the UDP port the server is listening on.
func (s *TURNServer) Port() int { return s.port }

// Stop shuts down the TURN server.
func (s *TURNServer) Stop() {
	select {
	case <-s.done:
	default:
		close(s.done)
	}
	s.conn.Close()
	s.mu.Lock()
	for _, a := range s.allocs {
		a.relayConn.Close()
	}
	s.mu.Unlock()
}

func (s *TURNServer) serve() {
	buf := make([]byte, 65536)
	for {
		n, addr, err := s.conn.ReadFromUDP(buf)
		if err != nil {
			select {
			case <-s.done:
			default:
				log.Printf("[turn] read error: %v", err)
			}
			return
		}
		pkt := make([]byte, n)
		copy(pkt, buf[:n])
		go s.handlePkt(pkt, addr)
	}
}

func (s *TURNServer) handlePkt(pkt []byte, from *net.UDPAddr) {
	// Channel data (first two bits = 0b01)?
	if len(pkt) >= 4 && pkt[0]&0xC0 == 0x40 {
		ch := binary.BigEndian.Uint16(pkt[0:2]) & 0x3FFF
		length := binary.BigEndian.Uint16(pkt[2:4])
		if len(pkt) < 4+int(length) {
			return
		}
		data := pkt[4 : 4+length]
		s.handleChannelData(ch, data, from)
		return
	}

	m, ok := parseStun(pkt)
	if !ok {
		return
	}

	switch m.msgType {
	case msgAllocateReq:
		s.handleAllocate(m, from)
	case msgRefreshReq:
		s.handleRefresh(m, from)
	case msgCreatePermReq:
		s.handleCreatePerm(m, from)
	case msgSendInd:
		s.handleSend(m, from)
	case msgChannelBindReq:
		s.handleChannelBind(m, from)
	case msgBindingReq:
		s.handleBinding(m, from)
	}
}

func (s *TURNServer) handleBinding(m *stunMsg, from *net.UDPAddr) {
	b := newStunBuilder(msgBindingOK, m.txID)
	b.addXorAddr(attrXorMappedAddr, from.IP, from.Port, m.txID)
	s.conn.WriteToUDP(b.bytes(), from)
}

func (s *TURNServer) handleAllocate(m *stunMsg, from *net.UDPAddr) {
	// If request has no USERNAME, send 401 with REALM+NONCE so client retries with credentials.
	if _, hasUser := m.getAttr(attrUsername); !hasUser {
		s.send401(m, from)
		return
	}
	// Accept any credentials (local server, no security needed).
	key := from.String()
	s.mu.Lock()
	if _, exists := s.allocs[key]; exists {
		s.mu.Unlock()
		// Already have allocation — refresh it.
		s.sendAllocOK(m, from)
		return
	}

	relay, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4zero, Port: 0})
	if err != nil {
		s.mu.Unlock()
		log.Printf("[turn] relay listen: %v", err)
		return
	}
	a := &turnAlloc{
		clientAddr: from,
		relayConn:  relay,
		expiry:     time.Now().Add(time.Duration(allocLifetime) * time.Second),
		perms:      make(map[string]bool),
		channels:   make(map[uint16]*net.UDPAddr),
	}
	s.allocs[key] = a
	s.mu.Unlock()

	go s.relayRecv(a)
	s.sendAllocOK(m, from)
}

func (s *TURNServer) sendAllocOK(m *stunMsg, from *net.UDPAddr) {
	s.mu.Lock()
	a := s.allocs[from.String()]
	s.mu.Unlock()
	if a == nil {
		return
	}

	relayAddr := a.relayConn.LocalAddr().(*net.UDPAddr)
	b := newStunBuilder(msgAllocateOK, m.txID)
	b.addXorAddr(attrXorRelayedAddr, net.IPv4zero, relayAddr.Port, m.txID)
	b.addXorAddr(attrXorMappedAddr, from.IP, from.Port, m.txID)
	b.addU32Attr(attrLifetime, allocLifetime)
	s.conn.WriteToUDP(b.bytes(), from)
}

func (s *TURNServer) send401(m *stunMsg, from *net.UDPAddr) {
	b := newStunBuilder(msgAllocateErr, m.txID)
	// Error code: 401 Unauthorized
	errCode := []byte{0x00, 0x00, 0x04, 0x01}
	errCode = append(errCode, []byte("Unauthorized")...)
	b.addAttr(attrErrorCode, errCode)
	b.addAttr(attrRealm, []byte(turnRealm))
	b.addAttr(attrNonce, []byte(turnNonce))
	s.conn.WriteToUDP(b.bytes(), from)
}

func (s *TURNServer) handleRefresh(m *stunMsg, from *net.UDPAddr) {
	s.mu.Lock()
	a := s.allocs[from.String()]
	if a != nil {
		a.expiry = time.Now().Add(time.Duration(allocLifetime) * time.Second)
	}
	s.mu.Unlock()

	b := newStunBuilder(msgRefreshOK, m.txID)
	b.addU32Attr(attrLifetime, allocLifetime)
	s.conn.WriteToUDP(b.bytes(), from)
}

func (s *TURNServer) handleCreatePerm(m *stunMsg, from *net.UDPAddr) {
	s.mu.Lock()
	a := s.allocs[from.String()]
	s.mu.Unlock()
	if a == nil {
		return
	}

	if val, ok := m.getAttr(attrXorPeerAddr); ok {
		if peer := parseXorAddr(val, m.txID); peer != nil {
			a.addPerm(peer.IP.String())
		}
	}

	b := newStunBuilder(msgCreatePermOK, m.txID)
	s.conn.WriteToUDP(b.bytes(), from)
}

func (s *TURNServer) handleSend(m *stunMsg, from *net.UDPAddr) {
	s.mu.Lock()
	a := s.allocs[from.String()]
	s.mu.Unlock()
	if a == nil {
		return
	}

	peerVal, hasPeer := m.getAttr(attrXorPeerAddr)
	data, hasData := m.getAttr(attrData)
	if !hasPeer || !hasData {
		return
	}
	peer := parseXorAddr(peerVal, m.txID)
	if peer == nil {
		return
	}

	a.mu.Lock()
	// Auto-add permission (lenient local server).
	a.perms[peer.IP.String()] = true
	a.mu.Unlock()

	a.relayConn.WriteToUDP(data, peer)
}

func (s *TURNServer) handleChannelBind(m *stunMsg, from *net.UDPAddr) {
	s.mu.Lock()
	a := s.allocs[from.String()]
	s.mu.Unlock()
	if a == nil {
		return
	}

	chVal, hasCh := m.getAttr(attrChannelNumber)
	peerVal, hasPeer := m.getAttr(attrXorPeerAddr)
	if !hasCh || !hasPeer || len(chVal) < 2 {
		return
	}
	ch := binary.BigEndian.Uint16(chVal[0:2])
	peer := parseXorAddr(peerVal, m.txID)
	if peer == nil {
		return
	}

	a.mu.Lock()
	a.channels[ch] = peer
	a.perms[peer.IP.String()] = true
	a.mu.Unlock()

	b := newStunBuilder(msgChannelBindOK, m.txID)
	s.conn.WriteToUDP(b.bytes(), from)
}

func (s *TURNServer) handleChannelData(ch uint16, data []byte, from *net.UDPAddr) {
	s.mu.Lock()
	a := s.allocs[from.String()]
	s.mu.Unlock()
	if a == nil {
		return
	}
	a.mu.Lock()
	peer := a.channels[ch]
	a.mu.Unlock()
	if peer == nil {
		return
	}
	a.relayConn.WriteToUDP(data, peer)
}

// relayRecv forwards data received at the relay socket back to the client
// via DATA indications.
func (s *TURNServer) relayRecv(a *turnAlloc) {
	buf := make([]byte, 65536)
	for {
		n, peer, err := a.relayConn.ReadFromUDP(buf)
		if err != nil {
			return
		}
		if !a.hasPerm(peer.IP.String()) {
			continue
		}
		data := buf[:n]

		// Try channel data first (if a channel is bound for this peer).
		a.mu.Lock()
		var chNum uint16
		for ch, p := range a.channels {
			if p.IP.Equal(peer.IP) && p.Port == peer.Port {
				chNum = ch
				break
			}
		}
		a.mu.Unlock()

		if chNum != 0 {
			// Channel data format: 0x4XXX | channel, length, data
			pkt := make([]byte, 4+len(data))
			binary.BigEndian.PutUint16(pkt[0:2], 0x4000|chNum)
			binary.BigEndian.PutUint16(pkt[2:4], uint16(len(data)))
			copy(pkt[4:], data)
			s.conn.WriteToUDP(pkt, a.clientAddr)
		} else {
			// DATA indication
			var txID [12]byte
			b := newStunBuilder(msgDataInd, txID)
			b.addXorAddr(attrXorPeerAddr, peer.IP, peer.Port, txID)
			b.addAttr(attrData, data)
			s.conn.WriteToUDP(b.bytes(), a.clientAddr)
		}
	}
}

func (s *TURNServer) gcLoop() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-s.done:
			return
		case <-ticker.C:
			now := time.Now()
			s.mu.Lock()
			for key, a := range s.allocs {
				if now.After(a.expiry) {
					a.relayConn.Close()
					delete(s.allocs, key)
				}
			}
			s.mu.Unlock()
		}
	}
}
