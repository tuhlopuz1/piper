package core

import (
	"sync"
	"testing"
	"time"
)

// ─── Lifecycle ────────────────────────────────────────────────────────────────

func TestNodeStartStop(t *testing.T) {
	n := startTestNode(t, "Alice")
	if n.port == 0 {
		t.Error("port should be non-zero after Start")
	}
	if n.id == "" {
		t.Error("id should be non-empty after Start")
	}
}

func TestNodeDoubleStop(t *testing.T) {
	n := startTestNode(t, "Alice")
	n.Stop()
	// Second Stop should not panic (t.Cleanup will call Stop again).
}

func TestNodeIDIsStable(t *testing.T) {
	id := "fixed-id-abc"
	n := NewNodeWithID("Alice", id)
	n.SetDownloadsDir(t.TempDir())
	if err := n.Start(); err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	if n.ID() != id {
		t.Errorf("ID(): got %q, want %q", n.ID(), id)
	}
}

// ─── Two-node connectivity ────────────────────────────────────────────────────

func TestTwoNodeConnect(t *testing.T) {
	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")

	connectNodes(t, a, b)

	// Both should list each other in Peers().
	peersA := a.Peers()
	if len(peersA) == 0 {
		t.Error("Alice has no peers after connect")
	}
	peersB := b.Peers()
	if len(peersB) == 0 {
		t.Error("Bob has no peers after connect")
	}
}

func TestTwoNodePeerInfo(t *testing.T) {
	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")

	connectNodes(t, a, b)

	peerOfA := a.PeerByID(b.id)
	if peerOfA == nil {
		t.Fatal("Alice has no PeerInfo for Bob")
	}
	if peerOfA.Name != "Bob" {
		t.Errorf("peer name: got %q, want Bob", peerOfA.Name)
	}
	if peerOfA.State != PeerConnected {
		t.Errorf("peer state: got %v, want PeerConnected", peerOfA.State)
	}
}

// ─── Text messages ────────────────────────────────────────────────────────────

func TestTextMessageBroadcast(t *testing.T) {
	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")
	connectNodes(t, a, b)
	drainEvents(b) // drop the PeerJoined we already consumed in connectNodes

	a.Send("hello from Alice", "")

	e := waitEvent(t, b, 3*time.Second, func(e Event) bool {
		return e.Msg != nil && e.Msg.Type == MsgTypeText && e.Msg.Content == "hello from Alice"
	})
	if e.Msg.Name != "Alice" {
		t.Errorf("sender name: got %q, want Alice", e.Msg.Name)
	}
}

func TestDirectMessageEncrypted(t *testing.T) {
	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")
	connectNodes(t, a, b)
	drainEvents(b)

	a.Send("secret direct", b.id)

	e := waitEvent(t, b, 3*time.Second, func(e Event) bool {
		return e.Msg != nil && e.Msg.Type == MsgTypeDirect
	})
	// Node decrypts before emitting — Content should be plaintext.
	if e.Msg.Content != "secret direct" {
		t.Errorf("decrypted content: got %q, want secret direct", e.Msg.Content)
	}
	if e.Msg.PeerID != a.id {
		t.Errorf("sender PeerID: got %q, want %q", e.Msg.PeerID, a.id)
	}
}

func TestDirectMessageSelfEcho(t *testing.T) {
	// Sender should receive an echo event for their own direct message.
	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")
	connectNodes(t, a, b)
	drainEvents(a)

	a.Send("echo test", b.id)

	e := waitEvent(t, a, 3*time.Second, func(e Event) bool {
		return e.Msg != nil && e.Msg.Type == MsgTypeDirect && e.Msg.Content == "echo test"
	})
	if e.Msg.PeerID != a.id {
		t.Errorf("echo PeerID: got %q, want %q (self)", e.Msg.PeerID, a.id)
	}
}

// ─── Peer disconnect ──────────────────────────────────────────────────────────

func TestPeerLeftOnDisconnect(t *testing.T) {
	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")
	connectNodes(t, a, b)
	drainEvents(a)

	// Forcefully stop b — Alice should eventually see PeerLeft.
	b.Stop()

	waitEvent(t, a, 10*time.Second, func(e Event) bool {
		return e.Peer != nil && e.Peer.Kind == PeerLeft && e.Peer.Peer.ID == b.id
	})
}

// ─── Groups ───────────────────────────────────────────────────────────────────

func TestGroupCreateAndInvite(t *testing.T) {
	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")
	connectNodes(t, a, b)
	drainEvents(b)

	g := a.CreateGroup("Dev Team")
	if g == nil {
		t.Fatal("CreateGroup returned nil")
	}
	a.InviteToGroup(g.ID, b.id)

	// Bob should receive a GroupCreated event.
	waitEvent(t, b, 3*time.Second, func(e Event) bool {
		return e.Group != nil && e.Group.Kind == GroupCreated && e.Group.Group.Name == "Dev Team"
	})
}

func TestGroupTextMessage(t *testing.T) {
	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")
	connectNodes(t, a, b)
	drainEvents(b)

	g := a.CreateGroup("Chat")
	a.InviteToGroup(g.ID, b.id)
	// Wait for Bob to join.
	waitEvent(t, b, 3*time.Second, func(e Event) bool {
		return e.Group != nil && e.Group.Kind == GroupCreated
	})
	drainEvents(b)

	a.SendGroup("group message text", g.ID)

	e := waitEvent(t, b, 3*time.Second, func(e Event) bool {
		return e.Msg != nil && e.Msg.Type == MsgTypeGroupText
	})
	if e.Msg.Content != "group message text" {
		t.Errorf("group msg content: got %q, want group message text", e.Msg.Content)
	}
}

// ─── Concurrency ─────────────────────────────────────────────────────────────

func TestConcurrentSend(t *testing.T) {
	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")
	connectNodes(t, a, b)

	const numMessages = 20
	var wg sync.WaitGroup
	for i := 0; i < numMessages; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			a.Send("concurrent", "")
		}()
	}
	wg.Wait()
	// No panics or deadlocks = pass. Race detector validates no data races.
}

// ─── Relay / mesh (requires mesh implementation) ──────────────────────────────

// TestThreeNodeRelay verifies that a message travels A → B → C when A and C
// are not directly connected. This test will FAIL until the mesh relay feature
// is implemented (MESH_PLAN.md Phase F1).
func TestThreeNodeRelay(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping relay test in short mode — requires mesh implementation")
	}

	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")   // relay
	c := startTestNode(t, "Charlie")

	// Connect only A↔B and B↔C. A and C do NOT see each other.
	connectNodes(t, a, b)
	connectNodes(t, b, c)
	drainEvents(c)

	// A broadcasts; should reach C via B.
	a.Send("relay_test", "")

	e := waitEvent(t, c, 5*time.Second, func(e Event) bool {
		return e.Msg != nil && e.Msg.Type == MsgTypeText && e.Msg.Content == "relay_test"
	})
	// After mesh is implemented, HopPath should contain B's ID.
	_ = e
}

// TestMessageDeduplication verifies the same message ID is not emitted twice.
// Requires the seenMsgIDs deduplication from MESH_PLAN.md F0-3.
func TestMessageDeduplication(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping dedup test in short mode — requires deduplication implementation")
	}

	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")
	connectNodes(t, a, b)
	drainEvents(b)

	// Send one message. Bob should receive exactly once.
	a.Send("dedup test", "")

	// Wait for first delivery.
	waitEvent(t, b, 3*time.Second, func(e Event) bool {
		return e.Msg != nil && e.Msg.Content == "dedup test"
	})

	// After a brief wait, no second event should appear.
	expectNoEvent(t, b, 500*time.Millisecond, func(e Event) bool {
		return e.Msg != nil && e.Msg.Content == "dedup test"
	})
}
