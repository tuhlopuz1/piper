package dht

import (
	"crypto/ed25519"
	"errors"
	"strings"
	"time"

	"github.com/vmihailenco/msgpack/v5"
)

// PiperValidator implements record.Validator for the "piper" DHT namespace.
// It is registered with dht.NamespacedValidator("piper", PiperValidator{}).
type PiperValidator struct{}

func (PiperValidator) Validate(key string, value []byte) error {
	switch {
	case strings.HasPrefix(key, "/piper/msg/v1/"):
		return validateMsgRecord(value)
	case strings.HasPrefix(key, "/piper/inbox/v1/"):
		return validateInboxRecord(value)
	default:
		return errors.New("piper: unknown key type")
	}
}

// Select picks the best value for a given key.
// For msg keys: first valid (immutable records).
// For inbox keys: the record with the most items (CRDT grow-only set).
func (PiperValidator) Select(key string, values [][]byte) (int, error) {
	if strings.HasPrefix(key, "/piper/msg/v1/") {
		for i, v := range values {
			if validateMsgRecord(v) == nil {
				return i, nil
			}
		}
		return 0, errors.New("piper: no valid msg record")
	}
	// Inbox: pick the one with the most items.
	best, bestCount := 0, -1
	for i, v := range values {
		if validateInboxRecord(v) != nil {
			continue
		}
		var inbox DHTInbox
		if msgpack.Unmarshal(v, &inbox) != nil {
			continue
		}
		if len(inbox.Items) > bestCount {
			best = i
			bestCount = len(inbox.Items)
		}
	}
	if bestCount < 0 {
		return 0, errors.New("piper: no valid inbox record")
	}
	return best, nil
}

// ── validation helpers ───────────────────────────────────────────────────────

func validateMsgRecord(value []byte) error {
	var rec DHTRecord
	if err := msgpack.Unmarshal(value, &rec); err != nil {
		return err
	}
	now := time.Now()
	if now.After(rec.ExpiresAt) {
		return errors.New("piper: msg record expired")
	}
	if rec.ExpiresAt.After(now.Add(49 * time.Hour)) {
		return errors.New("piper: msg TTL too far in future")
	}
	if len(rec.SenderEd25519Pub) != ed25519.PublicKeySize {
		return errors.New("piper: invalid sender pub key size")
	}
	payload, err := sigPayloadMsg(rec)
	if err != nil {
		return err
	}
	if !ed25519.Verify(rec.SenderEd25519Pub, payload, rec.Signature) {
		return errors.New("piper: msg signature invalid")
	}
	return nil
}

func validateInboxRecord(value []byte) error {
	var inbox DHTInbox
	if err := msgpack.Unmarshal(value, &inbox); err != nil {
		return err
	}
	if len(inbox.SenderPub) != ed25519.PublicKeySize {
		return errors.New("piper: inbox: invalid pub key size")
	}
	payload, err := sigPayloadInbox(inbox.Items)
	if err != nil {
		return err
	}
	if !ed25519.Verify(inbox.SenderPub, payload, inbox.Signature) {
		return errors.New("piper: inbox signature invalid")
	}
	return nil
}

// sigPayloadMsg returns the canonical bytes to sign for a DHTRecord.
func sigPayloadMsg(rec DHTRecord) ([]byte, error) {
	return msgpack.Marshal(struct {
		Box  []byte
		Exp  time.Time
		Pub  []byte
		PID  string
	}{rec.SealedBox, rec.ExpiresAt, rec.SenderEd25519Pub, rec.SenderPeerID})
}

// sigPayloadInbox returns the canonical bytes to sign for a DHTInbox.
func sigPayloadInbox(items []DHTInboxItem) ([]byte, error) {
	return msgpack.Marshal(items)
}
