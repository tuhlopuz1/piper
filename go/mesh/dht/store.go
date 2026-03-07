//go:build !android

package dht

import (
	"context"
	"crypto/ed25519"
	"fmt"
	"log"
	"time"

	"github.com/catsi/piper/mesh/identity"
	"github.com/catsi/piper/mesh/router"
	"github.com/libp2p/go-libp2p/core/host"
	kaddht "github.com/libp2p/go-libp2p-kad-dht"
	"github.com/vmihailenco/msgpack/v5"
	"go.etcd.io/bbolt"
)

const (
	maxInboxItems = 100
	msgTTL        = 48 * time.Hour
)

// OfflineStore seals, signs, and publishes messages to the piper DHT.
// The libp2p host and kad-dht instance are owned by this struct.
type OfflineStore struct {
	keys         identity.Keys
	senderPeerID string
	h            host.Host
	kadDHT       *kaddht.IpfsDHT
	db           *bbolt.DB
}

// NewOfflineStore creates a libp2p host on meshPort+1, initialises kad-dht,
// and returns an OfflineStore ready to use.
func NewOfflineStore(ctx context.Context, keys identity.Keys, senderPeerID string, meshPort int, db *bbolt.DB) (*OfflineStore, error) {
	h, err := newHost(keys, meshPort+1)
	if err != nil {
		return nil, fmt.Errorf("offline_store: libp2p host: %w", err)
	}
	kadDHT, err := newKadDHT(ctx, h)
	if err != nil {
		h.Close()
		return nil, fmt.Errorf("offline_store: kad-dht: %w", err)
	}
	return &OfflineStore{
		keys:         keys,
		senderPeerID: senderPeerID,
		h:            h,
		kadDHT:       kadDHT,
		db:           db,
	}, nil
}

// Bootstrap connects to known peers from the peer table and bootstraps routing.
func (s *OfflineStore) Bootstrap(ctx context.Context, peers []router.MeshPeer) {
	for _, pInfo := range bootstrapPeers(peers, 1) {
		if err := s.h.Connect(ctx, pInfo); err != nil {
			log.Printf("[dht] bootstrap connect %s: %v", pInfo.ID, err)
		}
	}
	if err := s.kadDHT.Bootstrap(ctx); err != nil {
		log.Printf("[dht] Bootstrap: %v", err)
	}
}

// Close shuts down the kad-dht and the underlying libp2p host.
func (s *OfflineStore) Close() {
	s.kadDHT.Close()
	s.h.Close()
}

// Diag returns a map with DHT diagnostics for PiperDHTDiag.
func (s *OfflineStore) Diag() map[string]interface{} {
	addrs := s.h.Addrs()
	addrStrs := make([]string, len(addrs))
	for i, a := range addrs {
		addrStrs[i] = a.String()
	}
	return map[string]interface{}{
		"status":    "ok",
		"peer_id":   s.h.ID().String(),
		"dht_peers": len(s.h.Network().Peers()),
		"addrs":     addrStrs,
	}
}

// Store encrypts text for recipientX25519Pub and publishes it to the DHT.
func (s *OfflineStore) Store(ctx context.Context, msgID, text string, recipientX25519Pub [32]byte) error {
	sealedBox, err := identity.Seal(recipientX25519Pub, []byte(text))
	if err != nil {
		return fmt.Errorf("offline_store: seal: %w", err)
	}
	expiresAt := time.Now().Add(msgTTL)

	rec := DHTRecord{
		SealedBox:        sealedBox,
		ExpiresAt:        expiresAt,
		SenderEd25519Pub: s.keys.Ed25519Pub,
		SenderPeerID:     s.senderPeerID,
	}
	payload, err := sigPayloadMsg(rec)
	if err != nil {
		return fmt.Errorf("offline_store: sig payload: %w", err)
	}
	rec.Signature = ed25519.Sign(s.keys.Ed25519Priv, payload)

	recBytes, err := msgpack.Marshal(rec)
	if err != nil {
		return fmt.Errorf("offline_store: marshal record: %w", err)
	}

	putCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	if err := s.kadDHT.PutValue(putCtx, MsgKey(msgID), recBytes); err != nil {
		return fmt.Errorf("offline_store: put msg: %w", err)
	}

	return s.updateInbox(ctx, InboxKey(recipientX25519Pub), DHTInboxItem{
		MsgID:     msgID,
		ExpiresAt: expiresAt,
	})
}

func (s *OfflineStore) updateInbox(ctx context.Context, inboxKey string, newItem DHTInboxItem) error {
	var items []DHTInboxItem
	getCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	if existing, err := s.kadDHT.GetValue(getCtx, inboxKey); err == nil {
		var inbox DHTInbox
		if msgpack.Unmarshal(existing, &inbox) == nil {
			items = inbox.Items
		}
	}
	cancel()

	found := false
	for _, it := range items {
		if it.MsgID == newItem.MsgID {
			found = true
			break
		}
	}
	if !found && newItem.MsgID != "" {
		items = append(items, newItem)
	}

	now := time.Now()
	var fresh []DHTInboxItem
	for _, it := range items {
		if it.ExpiresAt.After(now) {
			fresh = append(fresh, it)
		}
	}
	if len(fresh) > maxInboxItems {
		fresh = fresh[len(fresh)-maxInboxItems:]
	}

	return s.publishInbox(ctx, inboxKey, fresh)
}

func (s *OfflineStore) publishInbox(ctx context.Context, inboxKey string, items []DHTInboxItem) error {
	sigPayload, err := sigPayloadInbox(items)
	if err != nil {
		return fmt.Errorf("offline_store: inbox sig payload: %w", err)
	}
	inbox := DHTInbox{
		Items:     items,
		SenderPub: s.keys.Ed25519Pub,
		Signature: ed25519.Sign(s.keys.Ed25519Priv, sigPayload),
	}
	inboxBytes, err := msgpack.Marshal(inbox)
	if err != nil {
		return fmt.Errorf("offline_store: marshal inbox: %w", err)
	}
	putCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	if err := s.kadDHT.PutValue(putCtx, inboxKey, inboxBytes); err != nil {
		return fmt.Errorf("offline_store: put inbox: %w", err)
	}
	return nil
}
