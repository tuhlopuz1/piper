//go:build !android

package dht

import (
	"context"
	"crypto/ed25519"
	"encoding/binary"
	"log"
	"time"

	"github.com/catsi/piper/mesh/identity"
	"github.com/vmihailenco/msgpack/v5"
	"go.etcd.io/bbolt"
)

const bucketDHTSeen = "dht_seen"

// FetchAndDeliver retrieves messages from our DHT inbox and calls deliver for
// each new message. Already-delivered messages are tracked in bbolt.
func (s *OfflineStore) FetchAndDeliver(ctx context.Context, deliver func(DeliveredMsg)) error {
	inboxKey := InboxKey(s.keys.X25519Pub)

	getCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	inboxBytes, err := s.kadDHT.GetValue(getCtx, inboxKey)
	cancel()
	if err != nil {
		return nil // no inbox or not reachable
	}

	var inbox DHTInbox
	if err := msgpack.Unmarshal(inboxBytes, &inbox); err != nil {
		return nil
	}

	var toClaim []DHTInboxItem
	for _, item := range inbox.Items {
		if item.ExpiresAt.Before(time.Now()) {
			toClaim = append(toClaim, item)
			continue
		}
		if s.isSeen(item.MsgID) {
			toClaim = append(toClaim, item)
			continue
		}

		recCtx, recCancel := context.WithTimeout(ctx, 15*time.Second)
		recBytes, err := s.kadDHT.GetValue(recCtx, MsgKey(item.MsgID))
		recCancel()
		if err != nil {
			log.Printf("[dht] FetchAndDeliver: get msg %s: %v", item.MsgID, err)
			continue
		}

		var rec DHTRecord
		if err := msgpack.Unmarshal(recBytes, &rec); err != nil {
			continue
		}

		if len(rec.SenderEd25519Pub) != ed25519.PublicKeySize {
			continue
		}
		payload, err := sigPayloadMsg(rec)
		if err != nil || !ed25519.Verify(rec.SenderEd25519Pub, payload, rec.Signature) {
			log.Printf("[dht] FetchAndDeliver: invalid sig for msg %s", item.MsgID)
			continue
		}

		plain, err := identity.Open(s.keys.X25519Priv, s.keys.X25519Pub, rec.SealedBox)
		if err != nil {
			log.Printf("[dht] FetchAndDeliver: decrypt msg %s: %v", item.MsgID, err)
			continue
		}

		s.markSeen(item.MsgID, rec.ExpiresAt)
		deliver(DeliveredMsg{
			MsgID:        item.MsgID,
			Text:         string(plain),
			SenderPeerID: rec.SenderPeerID,
		})
		toClaim = append(toClaim, item)
	}

	if len(toClaim) > 0 {
		go func() {
			pruneCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			defer cancel()
			s.pruneInbox(pruneCtx, inboxKey, toClaim, inbox.Items)
		}()
	}
	return nil
}

func (s *OfflineStore) pruneInbox(ctx context.Context, inboxKey string, claimed, all []DHTInboxItem) {
	claimedIDs := make(map[string]bool, len(claimed))
	for _, it := range claimed {
		claimedIDs[it.MsgID] = true
	}
	now := time.Now()
	var remaining []DHTInboxItem
	for _, it := range all {
		if !claimedIDs[it.MsgID] && it.ExpiresAt.After(now) {
			remaining = append(remaining, it)
		}
	}
	if err := s.publishInbox(ctx, inboxKey, remaining); err != nil {
		log.Printf("[dht] pruneInbox: %v", err)
	}
}

func (s *OfflineStore) isSeen(msgID string) bool {
	seen := false
	_ = s.db.View(func(tx *bbolt.Tx) error {
		b := tx.Bucket([]byte(bucketDHTSeen))
		if b == nil {
			return nil
		}
		val := b.Get([]byte(msgID))
		if len(val) == 8 {
			expiry := int64(binary.LittleEndian.Uint64(val))
			if time.Now().Unix() < expiry {
				seen = true
			}
		}
		return nil
	})
	return seen
}

func (s *OfflineStore) markSeen(msgID string, expiresAt time.Time) {
	_ = s.db.Update(func(tx *bbolt.Tx) error {
		b := tx.Bucket([]byte(bucketDHTSeen))
		if b == nil {
			return nil
		}
		var val [8]byte
		binary.LittleEndian.PutUint64(val[:], uint64(expiresAt.Unix()))
		return b.Put([]byte(msgID), val[:])
	})
}
