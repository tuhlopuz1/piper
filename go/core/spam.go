package core

import (
	"sync"
	"time"
)

// spamWindowDur is the sliding window duration for per-peer message rate limiting.
const spamWindowDur = 10 * time.Second

// spamMaxPerWindow is the maximum number of messages accepted from a single peer
// within spamWindowDur before the node starts dropping messages from that peer.
const spamMaxPerWindow = 60

// spamBucket is a simple fixed-window counter for one peer.
// It resets on the first message after the window has expired.
type spamBucket struct {
	mu      sync.Mutex
	count   int
	resetAt time.Time
}

// allow returns true if the message should be processed, false if it should be
// dropped as a spam/flood. Thread-safe.
func (b *spamBucket) allow() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	now := time.Now()
	if now.After(b.resetAt) {
		b.count = 0
		b.resetAt = now.Add(spamWindowDur)
	}
	b.count++
	return b.count <= spamMaxPerWindow
}

// allowFromPeer looks up or creates the spamBucket for the given peer and
// returns whether the incoming message should be accepted.
func (n *Node) allowFromPeer(peerID string) bool {
	n.spamMu.Lock()
	b, ok := n.spamLimiters[peerID]
	if !ok {
		b = &spamBucket{}
		n.spamLimiters[peerID] = b
	}
	n.spamMu.Unlock()
	return b.allow()
}
