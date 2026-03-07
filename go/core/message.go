package core

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"time"

	"github.com/google/uuid"
)

// MsgType is the type of a protocol message.
type MsgType string

const (
	MsgTypeHello  MsgType = "hello"  // initial handshake (carries PubKey)
	MsgTypeText   MsgType = "text"   // global broadcast chat (plaintext)
	MsgTypeDirect MsgType = "direct" // personal encrypted message
	MsgTypePing   MsgType = "ping"   // keepalive
	MsgTypePong   MsgType = "pong"   // keepalive reply
	MsgTypeLeave  MsgType = "leave"  // graceful disconnect

	// Group message types
	MsgTypeGroupInvite MsgType = "group_invite" // carries GroupID, GroupName, Members
	MsgTypeGroupJoin   MsgType = "group_join"   // peerID accepted invite to GroupID
	MsgTypeGroupLeave  MsgType = "group_leave"  // peerID left GroupID
	MsgTypeGroupText   MsgType = "group_text"   // encrypted chat message in a group

	// File transfer message types
	MsgTypeFileOffer  MsgType = "file_offer"  // sender proposes a file transfer
	MsgTypeFileAccept MsgType = "file_accept" // receiver accepts
	MsgTypeFileChunk  MsgType = "file_chunk"  // one encrypted chunk of file data
	MsgTypeFileDone   MsgType = "file_done"   // sender signals all chunks sent (carries hash)
	MsgTypeFileReject MsgType = "file_reject" // receiver declines

	// DHT peer exchange
	MsgTypePeerExchange MsgType = "peer_exchange" // carries known peers for cross-peer discovery

	// Call signaling message types (payload = encrypted JSON in Content field)
	MsgTypeCallOffer  MsgType = "call_offer"  // caller → callee: {"sdp":"...","is_video":true}
	MsgTypeCallAnswer MsgType = "call_answer" // callee → caller: {"sdp":"..."}
	MsgTypeCallReject MsgType = "call_reject" // callee → caller: {}
	MsgTypeCallEnd    MsgType = "call_end"    // either side: {}
	MsgTypeCallIce    MsgType = "call_ice"    // either side: {"candidate":"...","sdpMid":"...","sdpMLineIndex":0}
	MsgTypeCallBusy   MsgType = "call_busy"   // callee/peer → caller: {"call_id":"...","reason":"busy"}
	MsgTypeCallAck    MsgType = "call_ack"    // either side: {"call_id":"...","ack_seq":N,"ack_type":"call_end"}
)

// PeerRecord is one entry in a DHT peer-exchange payload.
// It is serialised inside Message.PeerRecords and can also be transmitted
// over out-of-band transports (BLE, WiFi Direct) for cross-subnet bootstrap.
type PeerRecord struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	IP   string `json:"ip"`
	Port int    `json:"port"`
}

// Message is the top-level protocol envelope exchanged between peers.
// Wire format: 4-byte big-endian uint32 length prefix + JSON body.
type Message struct {
	ID        string   `json:"id"`
	Type      MsgType  `json:"type"`
	PeerID    string   `json:"peer_id"`              // sender's stable ID
	Name      string   `json:"name"`                 // sender's display name
	Content   string   `json:"content"`              // plaintext (Text) or base64 ciphertext (Direct)
	To        string   `json:"to,omitempty"`         // peerID for direct; "" = global
	PubKey    []byte   `json:"pub_key,omitempty"`    // X25519 public key (Hello only)
	Nonce     []byte   `json:"nonce,omitempty"`      // ChaCha20-Poly1305 nonce (Direct / GroupText)
	GroupID   string   `json:"group_id,omitempty"`   // group identifier (group messages)
	GroupName string   `json:"group_name,omitempty"` // human-readable group name (GroupInvite)
	Members   []string `json:"members,omitempty"`    // current member IDs (GroupInvite)

	// File transfer fields
	FileName   string `json:"file_name,omitempty"`   // original file name
	FileSize   int64  `json:"file_size,omitempty"`   // total file size in bytes
	FileHash   string `json:"file_hash,omitempty"`   // SHA-256 hex digest (FileDone)
	TransferID string `json:"transfer_id,omitempty"` // unique transfer identifier
	ChunkSeq   int    `json:"chunk_seq,omitempty"`   // chunk sequence number
	ChunkData  []byte `json:"chunk_data,omitempty"`  // encrypted chunk data (auto-base64 in JSON)

	// DHT peer exchange
	PeerRecords []PeerRecord `json:"peer_records,omitempty"` // known peers (peer_exchange only)

	Timestamp time.Time `json:"ts"`
}

// NewHelloMessage creates the initial handshake message carrying the sender's public key.
func NewHelloMessage(peerID, name string, pubKey []byte) Message {
	return Message{
		ID:        uuid.NewString(),
		Type:      MsgTypeHello,
		PeerID:    peerID,
		Name:      name,
		PubKey:    pubKey,
		Timestamp: time.Now(),
	}
}

// NewTextMessage creates a global broadcast chat message.
func NewTextMessage(peerID, name, content string) Message {
	return Message{
		ID:        uuid.NewString(),
		Type:      MsgTypeText,
		PeerID:    peerID,
		Name:      name,
		Content:   content,
		Timestamp: time.Now(),
	}
}

// NewDirectMessage creates a personal encrypted message.
// content should be the base64-encoded ciphertext from Encrypt().
func NewDirectMessage(fromID, fromName, toID, content string, nonce []byte) Message {
	return Message{
		ID:        uuid.NewString(),
		Type:      MsgTypeDirect,
		PeerID:    fromID,
		Name:      fromName,
		Content:   content,
		To:        toID,
		Nonce:     nonce,
		Timestamp: time.Now(),
	}
}

// WriteMsg serialises msg as length-prefixed JSON to w.
func WriteMsg(w io.Writer, msg Message) error {
	data, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("marshal: %w", err)
	}
	var lenBuf [4]byte
	binary.BigEndian.PutUint32(lenBuf[:], uint32(len(data)))
	if _, err := w.Write(lenBuf[:]); err != nil {
		return fmt.Errorf("write len: %w", err)
	}
	if _, err := w.Write(data); err != nil {
		return fmt.Errorf("write body: %w", err)
	}
	return nil
}

// ReadMsg deserialises the next length-prefixed JSON message from r.
func ReadMsg(r io.Reader) (Message, error) {
	var lenBuf [4]byte
	if _, err := io.ReadFull(r, lenBuf[:]); err != nil {
		return Message{}, fmt.Errorf("read len: %w", err)
	}
	msgLen := binary.BigEndian.Uint32(lenBuf[:])
	if msgLen == 0 || msgLen > 4*1024*1024 {
		return Message{}, fmt.Errorf("invalid message length: %d", msgLen)
	}
	buf := make([]byte, msgLen)
	if _, err := io.ReadFull(r, buf); err != nil {
		return Message{}, fmt.Errorf("read body: %w", err)
	}
	var msg Message
	if err := json.Unmarshal(buf, &msg); err != nil {
		return Message{}, fmt.Errorf("unmarshal: %w", err)
	}
	return msg, nil
}
