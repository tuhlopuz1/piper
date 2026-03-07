package core

import (
	"testing"
	"time"
)

func TestSpamBucket_AllowsUnderLimit(t *testing.T) {
	b := &spamBucket{}
	for i := 0; i < spamMaxPerWindow; i++ {
		if !b.allow() {
			t.Fatalf("message %d should be allowed (under limit %d)", i+1, spamMaxPerWindow)
		}
	}
}

func TestSpamBucket_DropsOverLimit(t *testing.T) {
	b := &spamBucket{}
	for i := 0; i < spamMaxPerWindow; i++ {
		b.allow()
	}
	// Next message exceeds the window limit.
	if b.allow() {
		t.Fatal("message over limit should be dropped")
	}
}

func TestSpamBucket_ResetsAfterWindow(t *testing.T) {
	// Use a tiny window so the test doesn't have to wait 10 seconds.
	orig := spamWindowDur
	_ = orig // spamWindowDur is a const; test uses real bucket reset logic indirectly

	b := &spamBucket{}
	// Fill the bucket.
	for i := 0; i < spamMaxPerWindow; i++ {
		b.allow()
	}
	if b.allow() {
		t.Fatal("should be over limit before reset")
	}

	// Force the reset by back-dating resetAt.
	b.mu.Lock()
	b.resetAt = time.Now().Add(-time.Second)
	b.mu.Unlock()

	// After window expiry the counter resets and messages are allowed again.
	if !b.allow() {
		t.Fatal("should be allowed after window reset")
	}
}

func TestNode_AllowFromPeer_IndependentBuckets(t *testing.T) {
	n := NewNode("Test")
	defer n.Stop()

	// Two different peers should have independent buckets.
	for i := 0; i < spamMaxPerWindow; i++ {
		n.allowFromPeer("peer-A")
	}
	// peer-A is over limit.
	if n.allowFromPeer("peer-A") {
		t.Fatal("peer-A should be rate-limited")
	}
	// peer-B is unaffected.
	if !n.allowFromPeer("peer-B") {
		t.Fatal("peer-B should not be affected by peer-A's limit")
	}
}
