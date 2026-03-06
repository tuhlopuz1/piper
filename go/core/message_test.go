package core

import (
	"bytes"
	"encoding/binary"
	"strings"
	"testing"
	"time"
)

func TestWriteReadRoundtrip(t *testing.T) {
	original := Message{
		ID:        "test-id-123",
		Type:      MsgTypeDirect,
		PeerID:    "peer-abc",
		Name:      "Alice",
		Content:   "hello world",
		To:        "peer-xyz",
		GroupID:   "grp-1",
		Timestamp: time.Now().Round(time.Millisecond), // round to avoid nanosecond drift in JSON
	}

	var buf bytes.Buffer
	if err := WriteMsg(&buf, original); err != nil {
		t.Fatalf("WriteMsg: %v", err)
	}

	got, err := ReadMsg(&buf)
	if err != nil {
		t.Fatalf("ReadMsg: %v", err)
	}

	if got.ID != original.ID {
		t.Errorf("ID: got %q, want %q", got.ID, original.ID)
	}
	if got.Type != original.Type {
		t.Errorf("Type: got %q, want %q", got.Type, original.Type)
	}
	if got.PeerID != original.PeerID {
		t.Errorf("PeerID: got %q, want %q", got.PeerID, original.PeerID)
	}
	if got.Name != original.Name {
		t.Errorf("Name: got %q, want %q", got.Name, original.Name)
	}
	if got.Content != original.Content {
		t.Errorf("Content: got %q, want %q", got.Content, original.Content)
	}
	if got.To != original.To {
		t.Errorf("To: got %q, want %q", got.To, original.To)
	}
	if got.GroupID != original.GroupID {
		t.Errorf("GroupID: got %q, want %q", got.GroupID, original.GroupID)
	}
}

func TestWriteReadRoundtripBinaryFields(t *testing.T) {
	nonce := []byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}
	pubKey := make([]byte, 32)
	for i := range pubKey {
		pubKey[i] = byte(i)
	}

	original := Message{
		ID:     "bin-msg",
		Type:   MsgTypeHello,
		PeerID: "p1",
		Name:   "Bob",
		Nonce:  nonce,
		PubKey: pubKey,
	}

	var buf bytes.Buffer
	WriteMsg(&buf, original)
	got, err := ReadMsg(&buf)
	if err != nil {
		t.Fatalf("ReadMsg: %v", err)
	}

	if !bytes.Equal(got.Nonce, nonce) {
		t.Errorf("Nonce mismatch")
	}
	if !bytes.Equal(got.PubKey, pubKey) {
		t.Errorf("PubKey mismatch")
	}
}

func TestReadMsgTooLarge(t *testing.T) {
	var buf bytes.Buffer
	// Write a 5 MB length header (exceeds 4 MB limit).
	var lenBuf [4]byte
	binary.BigEndian.PutUint32(lenBuf[:], 5*1024*1024)
	buf.Write(lenBuf[:])

	_, err := ReadMsg(&buf)
	if err == nil {
		t.Error("ReadMsg should reject messages over 4 MB, got nil error")
	}
}

func TestReadMsgZeroLength(t *testing.T) {
	var buf bytes.Buffer
	var lenBuf [4]byte
	binary.BigEndian.PutUint32(lenBuf[:], 0)
	buf.Write(lenBuf[:])

	_, err := ReadMsg(&buf)
	if err == nil {
		t.Error("ReadMsg should reject zero-length messages, got nil error")
	}
}

func TestReadMsgTruncatedBody(t *testing.T) {
	var buf bytes.Buffer
	// Claim 100 bytes but write only 10.
	var lenBuf [4]byte
	binary.BigEndian.PutUint32(lenBuf[:], 100)
	buf.Write(lenBuf[:])
	buf.Write([]byte("tooshort!!"))

	_, err := ReadMsg(&buf)
	if err == nil {
		t.Error("ReadMsg should fail on truncated body")
	}
}

func TestReadMsgInvalidJSON(t *testing.T) {
	body := []byte("not valid json {{{")
	var buf bytes.Buffer
	var lenBuf [4]byte
	binary.BigEndian.PutUint32(lenBuf[:], uint32(len(body)))
	buf.Write(lenBuf[:])
	buf.Write(body)

	_, err := ReadMsg(&buf)
	if err == nil {
		t.Error("ReadMsg should fail on invalid JSON body")
	}
}

func TestNewTextMessageFields(t *testing.T) {
	msg := NewTextMessage("peer-1", "Alice", "hello")

	if msg.ID == "" {
		t.Error("ID should not be empty")
	}
	if msg.Type != MsgTypeText {
		t.Errorf("Type: got %q, want %q", msg.Type, MsgTypeText)
	}
	if msg.PeerID != "peer-1" {
		t.Errorf("PeerID: got %q, want peer-1", msg.PeerID)
	}
	if msg.Name != "Alice" {
		t.Errorf("Name: got %q, want Alice", msg.Name)
	}
	if msg.Content != "hello" {
		t.Errorf("Content: got %q, want hello", msg.Content)
	}
	if msg.Timestamp.IsZero() {
		t.Error("Timestamp should not be zero")
	}
}

func TestNewDirectMessageFields(t *testing.T) {
	nonce := []byte{1, 2, 3}
	msg := NewDirectMessage("from-id", "Alice", "to-id", "ciphertext", nonce)

	if msg.Type != MsgTypeDirect {
		t.Errorf("Type: got %q, want %q", msg.Type, MsgTypeDirect)
	}
	if msg.PeerID != "from-id" {
		t.Errorf("PeerID: got %q, want from-id", msg.PeerID)
	}
	if msg.To != "to-id" {
		t.Errorf("To: got %q, want to-id", msg.To)
	}
	if msg.Content != "ciphertext" {
		t.Errorf("Content: got %q, want ciphertext", msg.Content)
	}
	if !bytes.Equal(msg.Nonce, nonce) {
		t.Error("Nonce mismatch")
	}
}

func TestNewHelloMessageFields(t *testing.T) {
	pubKey := make([]byte, 32)
	msg := NewHelloMessage("my-id", "Bob", pubKey)

	if msg.Type != MsgTypeHello {
		t.Errorf("Type: got %q, want %q", msg.Type, MsgTypeHello)
	}
	if msg.PeerID != "my-id" {
		t.Errorf("PeerID: got %q, want my-id", msg.PeerID)
	}
	if !bytes.Equal(msg.PubKey, pubKey) {
		t.Error("PubKey mismatch")
	}
}

func TestMessageIDsAreUnique(t *testing.T) {
	ids := make(map[string]bool)
	for i := 0; i < 100; i++ {
		msg := NewTextMessage("p", "name", "text")
		if ids[msg.ID] {
			t.Fatalf("duplicate message ID after %d iterations: %q", i, msg.ID)
		}
		ids[msg.ID] = true
	}
}

func TestWriteMsgMultipleMessages(t *testing.T) {
	// WriteMsg multiple times into same buffer, ReadMsg reads them in order.
	var buf bytes.Buffer
	msgs := []Message{
		NewTextMessage("p1", "Alice", "first"),
		NewTextMessage("p2", "Bob", "second"),
		NewTextMessage("p3", "Charlie", "third"),
	}
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
		if got.Content != want.Content {
			t.Errorf("msg[%d] Content: got %q, want %q", i, got.Content, want.Content)
		}
	}
}

func TestReadMsgFromEmptyReader(t *testing.T) {
	var buf bytes.Buffer
	_, err := ReadMsg(&buf)
	if err == nil {
		t.Error("ReadMsg on empty reader should return error")
	}
	// Should mention EOF or similar.
	if !strings.Contains(err.Error(), "len") && !strings.Contains(err.Error(), "EOF") {
		t.Logf("error message: %v", err) // informational
	}
}
