// Package dht provides Piper's DHT store-and-forward layer built on
// go-libp2p-kad-dht. On Android the libp2p stack is stubbed out to avoid
// the wlynxg/anet linkname restriction; all other types are available.
package dht

import (
	"crypto/sha256"
	"encoding/hex"
	"time"
)

// DeliveredMsg is passed to the deliver callback in FetchAndDeliver.
type DeliveredMsg struct {
	MsgID        string
	Text         string
	SenderPeerID string
}

// DHTInboxItem is one entry in a recipient's inbox index.
type DHTInboxItem struct {
	MsgID     string    `msgpack:"id"`
	ExpiresAt time.Time `msgpack:"exp"`
}

// DHTInbox is the inbox index stored at InboxKey.
type DHTInbox struct {
	Items     []DHTInboxItem `msgpack:"items"`
	SenderPub []byte         `msgpack:"pub"`
	Signature []byte         `msgpack:"sig"`
}

// DHTRecord is the encrypted message payload stored at MsgKey.
type DHTRecord struct {
	SealedBox        []byte    `msgpack:"box"`
	ExpiresAt        time.Time `msgpack:"exp"`
	SenderEd25519Pub []byte    `msgpack:"pub"`
	SenderPeerID     string    `msgpack:"pid"`
	Signature        []byte    `msgpack:"sig"`
}

// InboxKey returns the DHT key for recipientX25519Pub's inbox.
func InboxKey(recipientX25519Pub [32]byte) string {
	h := sha256.Sum256(recipientX25519Pub[:])
	return "/piper/inbox/v1/" + hex.EncodeToString(h[:20])
}

// MsgKey returns the DHT key for a message payload.
func MsgKey(msgID string) string {
	return "/piper/msg/v1/" + msgID
}
