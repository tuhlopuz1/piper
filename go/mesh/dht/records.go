package dht

import (
	"crypto/sha256"
	"encoding/hex"
	"time"
)

// DHTInboxItem is one entry in a recipient's inbox index.
type DHTInboxItem struct {
	MsgID     string    `msgpack:"id"`
	ExpiresAt time.Time `msgpack:"exp"`
}

// DHTInbox is the inbox index stored at InboxKey.
// The Signature covers the Items list and is signed by the writer's Ed25519 key.
type DHTInbox struct {
	Items     []DHTInboxItem `msgpack:"items"`
	SenderPub []byte         `msgpack:"pub"` // Ed25519 pub of the writer
	Signature []byte         `msgpack:"sig"`
}

// DHTRecord is the encrypted message payload stored at MsgKey.
type DHTRecord struct {
	SealedBox        []byte    `msgpack:"box"`
	ExpiresAt        time.Time `msgpack:"exp"`
	SenderEd25519Pub []byte    `msgpack:"pub"`
	SenderPeerID     string    `msgpack:"pid"` // piper peer ID of the sender
	Signature        []byte    `msgpack:"sig"` // covers Box+Exp+Pub+PeerID
}

// InboxKey returns the DHT key for recipientX25519Pub's inbox.
// Format: /piper/inbox/v1/{hex20(SHA256(recipientX25519Pub)[:20])}
func InboxKey(recipientX25519Pub [32]byte) string {
	h := sha256.Sum256(recipientX25519Pub[:])
	return "/piper/inbox/v1/" + hex.EncodeToString(h[:20])
}

// MsgKey returns the DHT key for a message payload.
func MsgKey(msgID string) string {
	return "/piper/msg/v1/" + msgID
}
