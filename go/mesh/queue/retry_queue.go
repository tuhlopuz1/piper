package queue

import (
	"fmt"
	"time"

	"github.com/vmihailenco/msgpack/v5"
	"go.etcd.io/bbolt"
)

const (
	bucketRetry = "retry"
	maxPerPeer  = 200
	ttl         = 24 * time.Hour
)

// RetryEntry is one queued message awaiting delivery to an offline peer.
type RetryEntry struct {
	MsgID     string    `msgpack:"id"`
	PeerID    string    `msgpack:"p"`
	Text      string    `msgpack:"t"`
	CreatedAt time.Time `msgpack:"c"`
}

// RetryQueue is a bbolt-backed, per-peer message queue for MsgTypeDirect
// messages sent to offline peers.
type RetryQueue struct {
	db *bbolt.DB
}

// New creates a RetryQueue backed by the provided bbolt database.
// The caller must ensure the "retry" bucket already exists (see store.Open).
func New(db *bbolt.DB) *RetryQueue {
	return &RetryQueue{db: db}
}

// Enqueue appends an entry for the given peer. If the peer already has
// maxPerPeer queued entries the oldest entry is evicted.
func (q *RetryQueue) Enqueue(e RetryEntry) error {
	e.CreatedAt = time.Now()
	return q.db.Update(func(tx *bbolt.Tx) error {
		b := tx.Bucket([]byte(bucketRetry))
		prefix := peerPrefix(e.PeerID)

		// Count existing entries for this peer and find oldest key.
		count := 0
		var firstKey []byte
		c := b.Cursor()
		for k, _ := c.Seek(prefix); k != nil && hasPrefix(k, prefix); k, _ = c.Next() {
			if count == 0 {
				firstKey = make([]byte, len(k))
				copy(firstKey, k)
			}
			count++
		}
		// Evict oldest if at limit.
		if count >= maxPerPeer && firstKey != nil {
			if err := b.Delete(firstKey); err != nil {
				return err
			}
		}

		// Composite key: peerID + \x00 + msgID
		key := compositeKey(e.PeerID, e.MsgID)
		val, err := msgpack.Marshal(e)
		if err != nil {
			return fmt.Errorf("retry_queue: marshal: %w", err)
		}
		return b.Put(key, val)
	})
}

// Flush returns and deletes all queued entries for peerID.
func (q *RetryQueue) Flush(peerID string) ([]RetryEntry, error) {
	var entries []RetryEntry
	return entries, q.db.Update(func(tx *bbolt.Tx) error {
		b := tx.Bucket([]byte(bucketRetry))
		prefix := peerPrefix(peerID)
		var keys [][]byte
		c := b.Cursor()
		for k, v := c.Seek(prefix); k != nil && hasPrefix(k, prefix); k, v = c.Next() {
			var e RetryEntry
			if err := msgpack.Unmarshal(v, &e); err == nil {
				entries = append(entries, e)
			}
			kc := make([]byte, len(k))
			copy(kc, k)
			keys = append(keys, kc)
		}
		for _, k := range keys {
			if err := b.Delete(k); err != nil {
				return err
			}
		}
		return nil
	})
}

// Expire deletes all entries older than ttl. Call periodically (e.g. every 5 min).
func (q *RetryQueue) Expire() error {
	cutoff := time.Now().Add(-ttl)
	return q.db.Update(func(tx *bbolt.Tx) error {
		b := tx.Bucket([]byte(bucketRetry))
		var stale [][]byte
		if err := b.ForEach(func(k, v []byte) error {
			var e RetryEntry
			if err := msgpack.Unmarshal(v, &e); err != nil || e.CreatedAt.Before(cutoff) {
				stale = append(stale, append([]byte(nil), k...))
			}
			return nil
		}); err != nil {
			return err
		}
		for _, k := range stale {
			if err := b.Delete(k); err != nil {
				return err
			}
		}
		return nil
	})
}

// ── helpers ──────────────────────────────────────────────────────────────────

func peerPrefix(peerID string) []byte {
	return []byte(peerID + "\x00")
}

func compositeKey(peerID, msgID string) []byte {
	return []byte(peerID + "\x00" + msgID)
}

func hasPrefix(k, prefix []byte) bool {
	if len(k) < len(prefix) {
		return false
	}
	for i, b := range prefix {
		if k[i] != b {
			return false
		}
	}
	return true
}
