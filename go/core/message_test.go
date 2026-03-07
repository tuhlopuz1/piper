package core

import (
	"bytes"
	"encoding/binary"
	"strings"
	"testing"
)

func TestNewHelloMessage(t *testing.T) {
	pubKey := make([]byte, 32)
	pubKey[0] = 0xAB
	msg := NewHelloMessage("peer-1", "Alice", pubKey)

	if msg.Type != MsgTypeHello {
		t.Fatalf("Type = %q, want %q", msg.Type, MsgTypeHello)
	}
	if msg.PeerID != "peer-1" {
		t.Fatalf("PeerID = %q, want %q", msg.PeerID, "peer-1")
	}
	if msg.Name != "Alice" {
		t.Fatalf("Name = %q, want %q", msg.Name, "Alice")
	}
	if !bytes.Equal(msg.PubKey, pubKey) {
		t.Fatal("PubKey mismatch")
	}
	if msg.ID == "" {
		t.Fatal("ID should not be empty")
	}
	if msg.Timestamp.IsZero() {
		t.Fatal("Timestamp should not be zero")
	}
}

func TestNewTextMessage(t *testing.T) {
	msg := NewTextMessage("peer-1", "Alice", "Hello world")

	if msg.Type != MsgTypeText {
		t.Fatalf("Type = %q, want %q", msg.Type, MsgTypeText)
	}
	if msg.Content != "Hello world" {
		t.Fatalf("Content = %q, want %q", msg.Content, "Hello world")
	}
	if msg.To != "" {
		t.Fatalf("To = %q, want empty", msg.To)
	}
}

func TestNewDirectMessage(t *testing.T) {
	nonce := []byte("012345678901")
	msg := NewDirectMessage("from-id", "Alice", "to-id", "encrypted-data", nonce)

	if msg.Type != MsgTypeDirect {
		t.Fatalf("Type = %q, want %q", msg.Type, MsgTypeDirect)
	}
	if msg.To != "to-id" {
		t.Fatalf("To = %q, want %q", msg.To, "to-id")
	}
	if !bytes.Equal(msg.Nonce, nonce) {
		t.Fatal("Nonce mismatch")
	}
}

func TestWriteReadMsg_RoundTrip(t *testing.T) {
	original := NewTextMessage("peer-1", "Bob", "Test message content")

	var buf bytes.Buffer
	if err := WriteMsg(&buf, original); err != nil {
		t.Fatalf("WriteMsg: %v", err)
	}

	got, err := ReadMsg(&buf)
	if err != nil {
		t.Fatalf("ReadMsg: %v", err)
	}

	if got.ID != original.ID {
		t.Fatalf("ID = %q, want %q", got.ID, original.ID)
	}
	if got.Type != original.Type {
		t.Fatalf("Type = %q, want %q", got.Type, original.Type)
	}
	if got.PeerID != original.PeerID {
		t.Fatalf("PeerID = %q, want %q", got.PeerID, original.PeerID)
	}
	if got.Content != original.Content {
		t.Fatalf("Content = %q, want %q", got.Content, original.Content)
	}
}

func TestWriteReadMsg_MultipleMessages(t *testing.T) {
	msgs := []Message{
		NewTextMessage("p1", "Alice", "msg1"),
		NewTextMessage("p2", "Bob", "msg2"),
		NewHelloMessage("p3", "Charlie", make([]byte, 32)),
	}

	var buf bytes.Buffer
	for _, m := range msgs {
		if err := WriteMsg(&buf, m); err != nil {
			t.Fatalf("WriteMsg: %v", err)
		}
	}

	for i, want := range msgs {
		got, err := ReadMsg(&buf)
		if err != nil {
			t.Fatalf("ReadMsg[%d]: %v", i, err)
		}
		if got.ID != want.ID {
			t.Fatalf("msg[%d] ID = %q, want %q", i, got.ID, want.ID)
		}
		if got.Type != want.Type {
			t.Fatalf("msg[%d] Type = %q, want %q", i, got.Type, want.Type)
		}
	}
}

func TestReadMsg_InvalidLength_Zero(t *testing.T) {
	var buf bytes.Buffer
	binary.Write(&buf, binary.BigEndian, uint32(0))

	_, err := ReadMsg(&buf)
	if err == nil {
		t.Fatal("ReadMsg should fail on zero length")
	}
}

func TestReadMsg_InvalidLength_TooLarge(t *testing.T) {
	var buf bytes.Buffer
	binary.Write(&buf, binary.BigEndian, uint32(5*1024*1024))

	_, err := ReadMsg(&buf)
	if err == nil {
		t.Fatal("ReadMsg should fail on too-large length")
	}
}

func TestReadMsg_TruncatedBody(t *testing.T) {
	var buf bytes.Buffer
	binary.Write(&buf, binary.BigEndian, uint32(100))
	buf.WriteString("short")

	_, err := ReadMsg(&buf)
	if err == nil {
		t.Fatal("ReadMsg should fail on truncated body")
	}
}

func TestReadMsg_EmptyReader(t *testing.T) {
	var buf bytes.Buffer
	_, err := ReadMsg(&buf)
	if err == nil {
		t.Fatal("ReadMsg should fail on empty reader")
	}
}

func TestWriteReadMsg_WithAllFields(t *testing.T) {
	msg := Message{
		ID:         "test-id",
		Type:       MsgTypeFileOffer,
		PeerID:     "sender",
		Name:       "Sender",
		Content:    "content",
		To:         "receiver",
		GroupID:    "group-1",
		GroupName:  "Test Group",
		Members:    []string{"a", "b", "c"},
		FileName:   "test.txt",
		FileSize:   1024,
		FileHash:   "abc123",
		TransferID: "transfer-1",
		ChunkSeq:   5,
		ChunkData:  []byte{0x01, 0x02, 0x03},
		PeerRecords: []PeerRecord{
			{ID: "p1", Name: "Peer1", IP: "192.168.1.1", Port: 8080},
		},
	}

	var buf bytes.Buffer
	if err := WriteMsg(&buf, msg); err != nil {
		t.Fatalf("WriteMsg: %v", err)
	}

	got, err := ReadMsg(&buf)
	if err != nil {
		t.Fatalf("ReadMsg: %v", err)
	}

	if got.FileName != msg.FileName {
		t.Fatalf("FileName = %q, want %q", got.FileName, msg.FileName)
	}
	if got.FileSize != msg.FileSize {
		t.Fatalf("FileSize = %d, want %d", got.FileSize, msg.FileSize)
	}
	if len(got.Members) != len(msg.Members) {
		t.Fatalf("Members len = %d, want %d", len(got.Members), len(msg.Members))
	}
	if len(got.PeerRecords) != 1 {
		t.Fatalf("PeerRecords len = %d, want 1", len(got.PeerRecords))
	}
	if got.PeerRecords[0].IP != "192.168.1.1" {
		t.Fatalf("PeerRecords[0].IP = %q, want %q", got.PeerRecords[0].IP, "192.168.1.1")
	}
}

func TestWriteReadMsg_RelayPayload(t *testing.T) {
	msg := Message{
		ID:           "relay-1",
		Type:         MsgTypeRelay,
		PeerID:       "sender",
		To:           "final-dest",
		RelayPayload: `{"id":"inner","type":"direct","peer_id":"orig"}`,
	}

	var buf bytes.Buffer
	if err := WriteMsg(&buf, msg); err != nil {
		t.Fatalf("WriteMsg: %v", err)
	}

	got, err := ReadMsg(&buf)
	if err != nil {
		t.Fatalf("ReadMsg: %v", err)
	}

	if got.Type != MsgTypeRelay {
		t.Fatalf("Type = %q, want %q", got.Type, MsgTypeRelay)
	}
	if got.RelayPayload != msg.RelayPayload {
		t.Fatalf("RelayPayload = %q, want %q", got.RelayPayload, msg.RelayPayload)
	}
	if got.To != "final-dest" {
		t.Fatalf("To = %q, want %q", got.To, "final-dest")
	}
}

func TestWriteReadMsg_Unicode(t *testing.T) {
	msg := NewTextMessage("p1", "Пользователь", "Привет, мир! 🌍")

	var buf bytes.Buffer
	WriteMsg(&buf, msg)

	got, _ := ReadMsg(&buf)
	if got.Name != "Пользователь" {
		t.Fatalf("Name = %q, want %q", got.Name, "Пользователь")
	}
	if got.Content != "Привет, мир! 🌍" {
		t.Fatalf("Content = %q, want %q", got.Content, "Привет, мир! 🌍")
	}
}

func TestReadMsg_InvalidJSON(t *testing.T) {
	body := []byte("not valid json{{{")
	var buf bytes.Buffer
	binary.Write(&buf, binary.BigEndian, uint32(len(body)))
	buf.Write(body)

	_, err := ReadMsg(&buf)
	if err == nil {
		t.Fatal("ReadMsg should fail on invalid JSON")
	}
	if !strings.Contains(err.Error(), "unmarshal") {
		t.Fatalf("error should mention unmarshal, got: %v", err)
	}
}
