package transport

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
)

// peerMsg is the envelope for every message exchanged between two Piper peers.
type peerMsg struct {
	Type    string          `json:"type"`
	From    string          `json:"from"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

// peer represents a single TCP connection to another Piper instance.
type peer struct {
	id      string
	name    string
	ip      string
	conn    net.Conn
	onMsg   func(*peer, peerMsg)
	onClose func(*peer)
}

func newPeer(conn net.Conn, onMsg func(*peer, peerMsg), onClose func(*peer)) *peer {
	host, _, _ := net.SplitHostPort(conn.RemoteAddr().String())
	return &peer{
		conn:    conn,
		ip:      host,
		onMsg:   onMsg,
		onClose: onClose,
	}
}

// sendHello sends our identity (dialer side initiates).
func (p *peer) sendHello(myID, myName string) error {
	payload, _ := json.Marshal(map[string]string{"name": myName})
	return p.send(peerMsg{Type: "hello", From: myID, Payload: payload})
}

// recvHello reads the first message and expects it to be a "hello".
// On the listener side: read peer hello, then reply with our own hello.
func (p *peer) recvHello(myID, myName string) error {
	msg, err := p.read()
	if err != nil {
		return fmt.Errorf("read hello: %w", err)
	}
	if msg.Type != "hello" {
		return fmt.Errorf("expected hello, got %q", msg.Type)
	}
	p.id = msg.From
	var payload struct {
		Name string `json:"name"`
	}
	_ = json.Unmarshal(msg.Payload, &payload)
	p.name = payload.Name

	// Send our hello in reply
	return p.sendHello(myID, myName)
}

// send encodes msg with a 4-byte big-endian length prefix and writes it.
func (p *peer) send(msg peerMsg) error {
	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	buf := make([]byte, 4+len(data))
	binary.BigEndian.PutUint32(buf[:4], uint32(len(data)))
	copy(buf[4:], data)
	_, err = p.conn.Write(buf)
	return err
}

// read reads one length-prefixed JSON message from the connection.
func (p *peer) read() (peerMsg, error) {
	var lenBuf [4]byte
	if _, err := io.ReadFull(p.conn, lenBuf[:]); err != nil {
		return peerMsg{}, err
	}
	size := binary.BigEndian.Uint32(lenBuf[:])
	if size > 64<<20 { // 64 MB hard cap
		return peerMsg{}, fmt.Errorf("message too large: %d bytes", size)
	}
	data := make([]byte, size)
	if _, err := io.ReadFull(p.conn, data); err != nil {
		return peerMsg{}, err
	}
	var msg peerMsg
	return msg, json.Unmarshal(data, &msg)
}

// readLoop runs until the connection closes; calls onMsg for every message.
func (p *peer) readLoop() {
	defer func() {
		p.conn.Close()
		if p.onClose != nil {
			p.onClose(p)
		}
	}()
	for {
		msg, err := p.read()
		if err != nil {
			if err != io.EOF {
				log.Printf("[transport] peer %s read error: %v", p.id, err)
			}
			return
		}
		if p.onMsg != nil {
			p.onMsg(p, msg)
		}
	}
}
