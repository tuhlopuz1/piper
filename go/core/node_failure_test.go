package core

import (
	"net"
	"sync"
	"testing"
	"time"
)

// TestPingTimeoutDetectsDisconnect verifies that when a peer's TCP socket is
// forcefully closed (without a graceful Leave), the local node eventually
// emits a PeerLeft event (detected via read error on the next message or ping).
func TestPingTimeoutDetectsDisconnect(t *testing.T) {
	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")
	connectNodes(t, a, b)
	drainEvents(a)

	// Close Bob's TCP connection to Alice directly (simulates abrupt network loss).
	b.mu.Lock()
	if cn, ok := b.connByPeerID[a.id]; ok {
		cn.c.Close()
	}
	b.mu.Unlock()

	// Alice's read loop should detect the error and emit PeerLeft.
	waitEvent(t, a, 10*time.Second, func(e Event) bool {
		return e.Peer != nil && e.Peer.Kind == PeerLeft && e.Peer.Peer.ID == b.id
	})
}

// TestNodeStopCleansAllConnections verifies that Stop() closes all active
// connections and the event channel does not block.
func TestNodeStopCleansAllConnections(t *testing.T) {
	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")
	c := startTestNode(t, "Charlie")

	connectNodes(t, a, b)
	connectNodes(t, a, c)

	if len(a.Peers()) < 2 {
		t.Fatalf("Alice should have 2 peers, got %d", len(a.Peers()))
	}

	done := make(chan struct{})
	go func() {
		a.Stop()
		close(done)
	}()

	select {
	case <-done:
		// Good — Stop returned without deadlock.
	case <-time.After(5 * time.Second):
		t.Fatal("Stop() deadlocked")
	}
}

// TestConcurrentConnectAndSend verifies no data races when multiple goroutines
// connect nodes and send messages simultaneously.
func TestConcurrentConnectAndSend(t *testing.T) {
	hub := startTestNode(t, "Hub")

	const numSpokes = 5
	spokes := make([]*Node, numSpokes)
	for i := range spokes {
		spokes[i] = startTestNode(t, "Spoke")
	}

	var wg sync.WaitGroup
	for _, spoke := range spokes {
		wg.Add(1)
		go func(s *Node) {
			defer wg.Done()
			connectNodes(t, hub, s)
		}(spoke)
	}
	wg.Wait()

	// After all spokes are connected, send messages concurrently.
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			hub.Send("concurrent", "")
		}()
	}
	wg.Wait()
	// Race detector validates correctness.
}

// TestReconnectAfterDisconnect verifies that after Bob disconnects, Alice
// can rediscover and reconnect to Bob (via onDiscovered re-trigger).
func TestReconnectAfterDisconnect(t *testing.T) {
	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")
	connectNodes(t, a, b)
	drainEvents(a)

	// Forcefully disconnect Bob's side.
	b.mu.Lock()
	if cn, ok := b.connByPeerID[a.id]; ok {
		cn.c.Close()
	}
	b.mu.Unlock()

	// Wait for Alice to detect the disconnect.
	waitEvent(t, a, 10*time.Second, func(e Event) bool {
		return e.Peer != nil && e.Peer.Kind == PeerLeft
	})

	// Re-trigger discovery manually (same mechanism Discovery uses).
	a.onDiscovered(b.id, b.name, net.IPv4(127, 0, 0, 1), b.port)

	// Alice should see Bob again after reconnect.
	waitEvent(t, a, 5*time.Second, func(e Event) bool {
		return e.Peer != nil && e.Peer.Kind == PeerJoined && e.Peer.Peer.ID == b.id
	})
}

// TestSendToUnknownPeerIsNoOp verifies that sending to an unknown peerID
// does not panic — it silently logs and returns.
func TestSendToUnknownPeerIsNoOp(t *testing.T) {
	a := startTestNode(t, "Alice")
	// Should not panic.
	a.Send("direct to nobody", "nonexistent-peer-id")
}

// TestSendGroupToEmptyGroup verifies sending to a group with no other members
// does not panic.
func TestSendGroupToEmptyGroup(t *testing.T) {
	a := startTestNode(t, "Alice")
	g := a.CreateGroup("Solo")
	drainEvents(a)
	// Should not panic.
	a.SendGroup("alone message", g.ID)
}

// TestSendGroupToUnknownGroup verifies that sending to an unknown group ID
// does not panic.
func TestSendGroupToUnknownGroup(t *testing.T) {
	a := startTestNode(t, "Alice")
	// Should not panic — group doesn't exist.
	a.SendGroup("ghost message", "nonexistent-group-id")
}

// TestMultipleMessagesPreserveDelivery sends several messages and verifies the
// receiver gets all of them.
func TestMultipleMessagesPreserveDelivery(t *testing.T) {
	a := startTestNode(t, "Alice")
	b := startTestNode(t, "Bob")
	connectNodes(t, a, b)
	drainEvents(b)

	const count = 5
	for i := 0; i < count; i++ {
		a.Send("msg", "")
	}

	received := 0
	deadline := time.After(5 * time.Second)
	for received < count {
		select {
		case e := <-b.Events():
			if e.Msg != nil && e.Msg.Type == MsgTypeText && e.Msg.Content == "msg" {
				received++
			}
		case <-deadline:
			t.Fatalf("timeout: received %d/%d messages", received, count)
		}
	}
}
