package transport

import (
	"encoding/binary"
	"io"
	"net"
	"sync"
)

const tcpMagic = uint32(0x50495052) // "PIPR"

type TCPLink struct {
	id      string
	peerID  string
	conn    net.Conn
	handler func([]byte)
	pool    sync.Pool
	mu      sync.Mutex
	quality LinkQuality
	done    chan struct{}
}

func NewTCPLink(id, peerID string, conn net.Conn) *TCPLink {
	l := &TCPLink{
		id:     id,
		peerID: peerID,
		conn:   conn,
		done:   make(chan struct{}),
	}
	l.pool.New = func() any { b := make([]byte, 65600); return &b }
	return l
}

func (l *TCPLink) ID() string                  { return l.id }
func (l *TCPLink) PeerID() string              { return l.peerID }
func (l *TCPLink) Quality() LinkQuality        { l.mu.Lock(); defer l.mu.Unlock(); return l.quality }
func (l *TCPLink) SetOnReceive(h func([]byte)) { l.mu.Lock(); l.handler = h; l.mu.Unlock() }

func (l *TCPLink) Start() { go l.readLoop() }

func (l *TCPLink) Send(pkt []byte) error {
	// Frame: [4 magic][4 length][payload]
	hdr := make([]byte, 8)
	binary.BigEndian.PutUint32(hdr[0:], tcpMagic)
	binary.BigEndian.PutUint32(hdr[4:], uint32(len(pkt)))
	l.mu.Lock()
	defer l.mu.Unlock()
	if _, err := l.conn.Write(hdr); err != nil {
		return err
	}
	_, err := l.conn.Write(pkt)
	return err
}

func (l *TCPLink) Close() {
	select {
	case <-l.done:
	default:
		close(l.done)
	}
	l.conn.Close()
}

func (l *TCPLink) readLoop() {
	hdr := make([]byte, 8)
	for {
		if _, err := io.ReadFull(l.conn, hdr); err != nil {
			return
		}
		if binary.BigEndian.Uint32(hdr[0:]) != tcpMagic {
			return
		}
		n := binary.BigEndian.Uint32(hdr[4:])
		if n > 65535 {
			return
		}

		bufPtr := l.pool.Get().(*[]byte)
		buf := (*bufPtr)[:n]
		if _, err := io.ReadFull(l.conn, buf); err != nil {
			l.pool.Put(bufPtr)
			return
		}

		l.mu.Lock()
		h := l.handler
		l.mu.Unlock()
		if h != nil {
			h(buf)
		}
		l.pool.Put(bufPtr)
	}
}
