package core

import (
	"testing"
	"time"
)

func TestNewNode(t *testing.T) {
	n := NewNode("TestUser")
	defer n.Stop()

	if n.Name() != "TestUser" {
		t.Fatalf("Name = %q, want %q", n.Name(), "TestUser")
	}
	if n.ID() == "" {
		t.Fatal("ID should not be empty")
	}
}

func TestNewNodeWithID(t *testing.T) {
	n := NewNodeWithID("TestUser", "fixed-id")
	defer n.Stop()

	if n.ID() != "fixed-id" {
		t.Fatalf("ID = %q, want %q", n.ID(), "fixed-id")
	}
}

func TestNewNodeWithID_GeneratesIfEmpty(t *testing.T) {
	n := NewNodeWithID("TestUser", "")
	defer n.Stop()

	if n.ID() == "" {
		t.Fatal("ID should be auto-generated when empty")
	}
}

func TestNode_SetName(t *testing.T) {
	n := NewNode("OldName")
	defer n.Stop()
	n.SetName("NewName")

	if n.Name() != "NewName" {
		t.Fatalf("Name = %q, want %q", n.Name(), "NewName")
	}
}

func TestNode_SetDownloadsDir(t *testing.T) {
	n := NewNode("Test")
	defer n.Stop()
	n.SetDownloadsDir("/tmp/test-downloads")

	if n.downloadsDir != "/tmp/test-downloads" {
		t.Fatalf("downloadsDir = %q, want %q", n.downloadsDir, "/tmp/test-downloads")
	}
}

func TestNode_EmptyPeersAndGroups(t *testing.T) {
	n := NewNode("Test")
	defer n.Stop()

	if len(n.Peers()) != 0 {
		t.Fatalf("Peers len = %d, want 0", len(n.Peers()))
	}
	if len(n.Groups()) != 0 {
		t.Fatalf("Groups len = %d, want 0", len(n.Groups()))
	}
	if n.PeerByID("nonexistent") != nil {
		t.Fatal("PeerByID should return nil")
	}
	if n.GroupByID("nonexistent") != nil {
		t.Fatal("GroupByID should return nil")
	}
}

func TestNode_CreateGroup(t *testing.T) {
	n := NewNode("Test")
	defer n.Stop()

	g := n.CreateGroup("Friends")
	if g == nil {
		t.Fatal("CreateGroup returned nil")
	}
	if g.Name != "Friends" {
		t.Fatalf("Name = %q, want %q", g.Name, "Friends")
	}
	if !g.Members[n.ID()] {
		t.Fatal("creator should be member")
	}

	if n.GroupByID(g.ID) == nil {
		t.Fatal("GroupByID should find the created group")
	}
	if len(n.Groups()) != 1 {
		t.Fatalf("Groups len = %d, want 1", len(n.Groups()))
	}

	select {
	case e := <-n.Events():
		if e.Group == nil || e.Group.Kind != GroupCreated {
			t.Fatal("expected GroupCreated event")
		}
	case <-time.After(time.Second):
		t.Fatal("timeout waiting for GroupCreated event")
	}
}

func TestNode_Transfers(t *testing.T) {
	n := NewNode("Test")
	defer n.Stop()

	tm := n.Transfers()
	if tm == nil {
		t.Fatal("Transfers() returned nil")
	}
	if len(tm.List()) != 0 {
		t.Fatal("initial transfers should be empty")
	}
}

func TestNode_LocalEndpoint(t *testing.T) {
	n := NewNode("Test")
	defer n.Stop()

	if err := n.Start(); err != nil {
		t.Fatalf("Start: %v", err)
	}

	ep := n.LocalEndpoint()
	if ep.ID != n.ID() {
		t.Fatalf("LocalEndpoint ID = %q, want %q", ep.ID, n.ID())
	}
	if ep.Name != "Test" {
		t.Fatalf("LocalEndpoint Name = %q, want %q", ep.Name, "Test")
	}
	if ep.Port == 0 {
		t.Fatal("LocalEndpoint Port should not be 0 after Start")
	}
}

func TestNode_PeerTable_Empty(t *testing.T) {
	n := NewNode("Test")
	defer n.Stop()

	table := n.PeerTable()
	if len(table) != 0 {
		t.Fatalf("PeerTable len = %d, want 0", len(table))
	}
}

func TestNode_MarkSeen_Dedup(t *testing.T) {
	n := NewNode("Test")
	defer n.Stop()

	if !n.markSeen("msg-1") {
		t.Fatal("first markSeen should return true")
	}
	if n.markSeen("msg-1") {
		t.Fatal("second markSeen should return false (duplicate)")
	}
	if !n.markSeen("msg-2") {
		t.Fatal("different msgID should return true")
	}
}

// TestTwoNodes_Connect verifies that two nodes on localhost can discover each
// other via direct TCP connection (bypassing mDNS/UDP discovery), exchange
// Hello handshakes, and communicate via broadcast messages.
func TestTwoNodes_Connect(t *testing.T) {
	nodeA := NewNode("Alice")
	nodeB := NewNode("Bob")

	if err := nodeA.Start(); err != nil {
		t.Fatalf("nodeA.Start: %v", err)
	}
	defer nodeA.Stop()

	if err := nodeB.Start(); err != nil {
		t.Fatalf("nodeB.Start: %v", err)
	}
	defer nodeB.Stop()

	// Inject B's endpoint into A to trigger connection without mDNS/UDP.
	epB := nodeB.LocalEndpoint()
	nodeA.InjectPeers([]PeerRecord{epB})

	// Wait for A to see B as a peer.
	deadline := time.After(5 * time.Second)
	for {
		select {
		case <-deadline:
			t.Fatal("timeout waiting for peers to connect")
		default:
		}

		if nodeA.PeerByID(nodeB.ID()) != nil && nodeB.PeerByID(nodeA.ID()) != nil {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}

	// Verify peer states.
	peerB := nodeA.PeerByID(nodeB.ID())
	if peerB.State != PeerConnected {
		t.Fatalf("peerB state = %d, want %d", peerB.State, PeerConnected)
	}
	if peerB.DisplayName != "Bob" {
		t.Fatalf("peerB DisplayName = %q, want %q", peerB.DisplayName, "Bob")
	}

	peerA := nodeB.PeerByID(nodeA.ID())
	if peerA.State != PeerConnected {
		t.Fatalf("peerA state = %d, want %d", peerA.State, PeerConnected)
	}

	// A sends a broadcast message.
	nodeA.Send("Hello from Alice", "")

	// B should receive it.
	deadline2 := time.After(5 * time.Second)
	for {
		select {
		case e := <-nodeB.Events():
			if e.Msg != nil && e.Msg.Type == MsgTypeText && e.Msg.Content == "Hello from Alice" {
				return // success
			}
		case <-deadline2:
			t.Fatal("timeout waiting for broadcast message")
		}
	}
}

// TestTwoNodes_DirectMessage verifies encrypted personal messaging.
func TestTwoNodes_DirectMessage(t *testing.T) {
	nodeA := NewNode("Alice")
	nodeB := NewNode("Bob")

	if err := nodeA.Start(); err != nil {
		t.Fatalf("nodeA.Start: %v", err)
	}
	defer nodeA.Stop()

	if err := nodeB.Start(); err != nil {
		t.Fatalf("nodeB.Start: %v", err)
	}
	defer nodeB.Stop()

	epB := nodeB.LocalEndpoint()
	nodeA.InjectPeers([]PeerRecord{epB})
	waitPeers(t, nodeA, nodeB, 5*time.Second)

	// A sends encrypted direct message to B.
	nodeA.Send("Secret from Alice", nodeB.ID())

	// B should receive decrypted text.
	deadline := time.After(5 * time.Second)
	for {
		select {
		case e := <-nodeB.Events():
			if e.Msg != nil && e.Msg.Type == MsgTypeDirect && e.Msg.Content == "Secret from Alice" {
				if e.Msg.PeerID != nodeA.ID() {
					t.Fatalf("msg PeerID = %q, want %q", e.Msg.PeerID, nodeA.ID())
				}
				return
			}
		case <-deadline:
			t.Fatal("timeout waiting for direct message")
		}
	}
}

// TestTwoNodes_BidirectionalDirect verifies that both nodes can send and
// receive direct encrypted messages.
func TestTwoNodes_BidirectionalDirect(t *testing.T) {
	nodeA := NewNode("Alice")
	nodeB := NewNode("Bob")

	if err := nodeA.Start(); err != nil {
		t.Fatalf("nodeA.Start: %v", err)
	}
	defer nodeA.Stop()

	if err := nodeB.Start(); err != nil {
		t.Fatalf("nodeB.Start: %v", err)
	}
	defer nodeB.Stop()

	epB := nodeB.LocalEndpoint()
	nodeA.InjectPeers([]PeerRecord{epB})
	waitPeers(t, nodeA, nodeB, 5*time.Second)

	// A -> B
	nodeA.Send("msg-A-to-B", nodeB.ID())
	waitForDirectMsg(t, nodeB, "msg-A-to-B", 5*time.Second)

	// B -> A
	nodeB.Send("msg-B-to-A", nodeA.ID())
	waitForDirectMsg(t, nodeA, "msg-B-to-A", 5*time.Second)
}

// TestTwoNodes_BroadcastFloodDedup verifies that broadcast messages are
// deduplicated so the same message is not processed twice.
func TestTwoNodes_BroadcastFloodDedup(t *testing.T) {
	nodeA := NewNode("Alice")
	nodeB := NewNode("Bob")

	if err := nodeA.Start(); err != nil {
		t.Fatalf("nodeA.Start: %v", err)
	}
	defer nodeA.Stop()

	if err := nodeB.Start(); err != nil {
		t.Fatalf("nodeB.Start: %v", err)
	}
	defer nodeB.Stop()

	epB := nodeB.LocalEndpoint()
	nodeA.InjectPeers([]PeerRecord{epB})
	waitPeers(t, nodeA, nodeB, 5*time.Second)

	// A sends broadcast.
	nodeA.Send("dedup-test", "")

	// B should receive exactly one copy.
	received := 0
	deadline := time.After(2 * time.Second)
loop:
	for {
		select {
		case e := <-nodeB.Events():
			if e.Msg != nil && e.Msg.Type == MsgTypeText && e.Msg.Content == "dedup-test" {
				received++
			}
		case <-deadline:
			break loop
		}
	}
	if received != 1 {
		t.Fatalf("received %d copies of broadcast, want 1", received)
	}
}

func TestNode_LeaveGroup(t *testing.T) {
	n := NewNode("Test")
	defer n.Stop()

	g := n.CreateGroup("TempGroup")
	<-n.Events()

	n.LeaveGroup(g.ID)

	if n.GroupByID(g.ID) != nil {
		t.Fatal("group should be deleted after leaving")
	}
}

func TestIsZeroKey(t *testing.T) {
	var zero [32]byte
	if !isZeroKey(zero) {
		t.Fatal("zero key should be detected as zero")
	}

	nonZero := [32]byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1}
	if isZeroKey(nonZero) {
		t.Fatal("non-zero key should not be detected as zero")
	}
}

func TestParseCallMeta(t *testing.T) {
	callID, seq := parseCallMeta(`{"call_id":"abc-123","seq":5}`)
	if callID != "abc-123" {
		t.Fatalf("callID = %q, want %q", callID, "abc-123")
	}
	if seq != 5 {
		t.Fatalf("seq = %d, want 5", seq)
	}

	callID, seq = parseCallMeta("not json")
	if callID != "" || seq != 0 {
		t.Fatal("invalid JSON should return empty values")
	}

	callID, seq = parseCallMeta(`{}`)
	if callID != "" || seq != 0 {
		t.Fatal("missing fields should return empty values")
	}
}

// ─── helpers ──────────────────────────────────────────────────────────────────

func waitPeers(t *testing.T, a, b *Node, timeout time.Duration) {
	t.Helper()
	deadline := time.After(timeout)
	for {
		select {
		case <-deadline:
			t.Fatal("timeout waiting for peers to connect")
		default:
		}
		if a.PeerByID(b.ID()) != nil && b.PeerByID(a.ID()) != nil {
			pA := b.PeerByID(a.ID())
			pB := a.PeerByID(b.ID())
			if pA.State == PeerConnected && pB.State == PeerConnected &&
				!isZeroKey(pA.SharedKey) && !isZeroKey(pB.SharedKey) {
				return
			}
		}
		time.Sleep(50 * time.Millisecond)
	}
}

func waitForDirectMsg(t *testing.T, receiver *Node, expectedContent string, timeout time.Duration) {
	t.Helper()
	deadline := time.After(timeout)
	for {
		select {
		case e := <-receiver.Events():
			if e.Msg != nil && e.Msg.Type == MsgTypeDirect && e.Msg.Content == expectedContent {
				return
			}
		case <-deadline:
			t.Fatalf("timeout waiting for direct message %q", expectedContent)
		}
	}
}

// TestThreeNodes_RelayFailover verifies that:
//  1. Broadcasts relay correctly through an intermediate node (A → B → C).
//  2. After the relay node B is stopped, A and C can reconnect directly and
//     continue communicating without the relay.
func TestThreeNodes_RelayFailover(t *testing.T) {
	nodeA := NewNode("Alice")
	nodeB := NewNode("Bob") // relay — stopped mid-test
	nodeC := NewNode("Carol")

	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		if err := n.Start(); err != nil {
			t.Fatalf("Start: %v", err)
		}
	}
	defer nodeA.Stop()
	// nodeB is stopped manually in Phase 3; no defer.
	defer nodeC.Stop()

	epA := nodeA.LocalEndpoint()
	epB := nodeB.LocalEndpoint()
	epC := nodeC.LocalEndpoint()

	// Phase 1 — chain topology: A ↔ B ↔ C
	// A and C know only B; they are not directly connected.
	nodeA.InjectPeers([]PeerRecord{epB})
	nodeB.InjectPeers([]PeerRecord{epA, epC})
	nodeC.InjectPeers([]PeerRecord{epB})

	waitPeers(t, nodeA, nodeB, 5*time.Second)
	waitPeers(t, nodeB, nodeC, 5*time.Second)

	// Phase 2 — broadcast from A reaches C via relay through B.
	nodeA.Send("relay-hello", "")

	gotRelay := false
	deadline := time.After(5 * time.Second)
relayLoop:
	for {
		select {
		case e := <-nodeC.Events():
			if e.Msg != nil && e.Msg.Type == MsgTypeText && e.Msg.Content == "relay-hello" {
				gotRelay = true
				break relayLoop
			}
		case <-deadline:
			break relayLoop
		}
	}
	if !gotRelay {
		t.Fatal("relay: nodeC did not receive broadcast relayed through nodeB")
	}

	// Phase 3 — kill the relay node.
	nodeB.Stop()
	time.Sleep(300 * time.Millisecond)

	// Phase 4 — A and C discover each other directly.
	nodeA.InjectPeers([]PeerRecord{epC})
	nodeC.InjectPeers([]PeerRecord{epA})
	waitPeers(t, nodeA, nodeC, 5*time.Second)

	// Phase 5 — communication restored without relay.
	nodeA.Send("direct-hello", "")

	gotDirect := false
	deadline2 := time.After(5 * time.Second)
directLoop:
	for {
		select {
		case e := <-nodeC.Events():
			if e.Msg != nil && e.Msg.Type == MsgTypeText && e.Msg.Content == "direct-hello" {
				gotDirect = true
				break directLoop
			}
		case <-deadline2:
			break directLoop
		}
	}
	if !gotDirect {
		t.Fatal("failover: nodeC did not receive broadcast after relay nodeB was stopped")
	}
}
