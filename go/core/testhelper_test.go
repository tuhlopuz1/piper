package core

// testhelper_test.go — shared utilities for Node integration tests.
// All helpers are in package core (same package as production code) so they
// can access unexported fields (n.port, n.id, n.onDiscovered, etc.).

import (
	"net"
	"testing"
	"time"
)

// startTestNode creates a Node, starts it, and registers t.Cleanup to stop it.
// Downloads go to a temp directory to avoid polluting the working directory.
// Discovery (mDNS + UDP broadcast) is stopped immediately after Start to avoid
// Windows Firewall prompts — tests connect nodes manually via connectNodes().
func startTestNode(t *testing.T, name string) *Node {
	t.Helper()
	n := NewNode(name)
	n.SetDownloadsDir(t.TempDir())
	if err := n.Start(); err != nil {
		t.Fatalf("startTestNode(%q): Start: %v", name, err)
	}
	// Stop discovery right away — not needed in tests, causes firewall prompts on Windows.
	if n.discovery != nil {
		n.discovery.Stop()
	}
	t.Cleanup(func() { n.Stop() })
	return n
}

// connectNodes directly dials b from a and vice-versa by bypassing mDNS.
// It calls onDiscovered (the same callback Discovery uses) on both nodes,
// then waits up to 5 seconds for the PeerJoined events to arrive on each.
func connectNodes(t *testing.T, a, b *Node) {
	t.Helper()
	loopback := net.IPv4(127, 0, 0, 1)

	// Trigger dial from a→b and b→a.
	a.onDiscovered(b.id, b.name, loopback, b.port)
	b.onDiscovered(a.id, a.name, loopback, a.port)

	// Wait for both to confirm the handshake.
	waitEvent(t, a, 5*time.Second, func(e Event) bool {
		return e.Peer != nil && e.Peer.Kind == PeerJoined && e.Peer.Peer.ID == b.id
	})
	waitEvent(t, b, 5*time.Second, func(e Event) bool {
		return e.Peer != nil && e.Peer.Kind == PeerJoined && e.Peer.Peer.ID == a.id
	})
}

// waitEvent reads events from n until predicate returns true or timeout fires.
// It calls t.Fatal on timeout.
func waitEvent(t *testing.T, n *Node, timeout time.Duration, predicate func(Event) bool) Event {
	t.Helper()
	deadline := time.After(timeout)
	for {
		select {
		case e := <-n.Events():
			if predicate(e) {
				return e
			}
		case <-deadline:
			t.Fatalf("waitEvent: timeout after %v", timeout)
			return Event{}
		}
	}
}

// drainEvents discards all events currently buffered on n's channel.
func drainEvents(n *Node) {
	for {
		select {
		case <-n.Events():
		default:
			return
		}
	}
}

// expectNoEvent asserts that no event matching predicate arrives within timeout.
func expectNoEvent(t *testing.T, n *Node, timeout time.Duration, predicate func(Event) bool) {
	t.Helper()
	deadline := time.After(timeout)
	for {
		select {
		case e := <-n.Events():
			if predicate(e) {
				t.Errorf("expectNoEvent: received unexpected event %+v", e)
				return
			}
		case <-deadline:
			return // good — nothing arrived
		}
	}
}
