package healer_test

import (
	"testing"
	"time"

	"github.com/catsi/piper/mesh/healer"
)

type mockRerouter struct{ triggered []string }

func (m *mockRerouter) TriggerReroute(peerID, reason string) {
	m.triggered = append(m.triggered, peerID+":"+reason)
}

func TestWatchdogDetectsLinkDead(t *testing.T) {
	mr := &mockRerouter{}
	w := healer.NewWatchdog(mr, 50*time.Millisecond)
	w.AddPeer("peer-x")

	// Don't call OnPacketReceived — silence should trigger dead link
	time.Sleep(300 * time.Millisecond)

	if len(mr.triggered) == 0 {
		t.Fatal("expected reroute trigger")
	}
	if mr.triggered[0] != "peer-x:link_dead" {
		t.Fatalf("want peer-x:link_dead got %s", mr.triggered[0])
	}
}

func TestWatchdogResetsOnPacket(t *testing.T) {
	mr := &mockRerouter{}
	w := healer.NewWatchdog(mr, 50*time.Millisecond)
	w.AddPeer("peer-y")

	// Feed packets regularly — should NOT trigger reroute
	done := make(chan struct{})
	go func() {
		for {
			select {
			case <-done:
				return
			case <-time.After(20 * time.Millisecond):
				w.OnPacketReceived("peer-y")
			}
		}
	}()

	time.Sleep(300 * time.Millisecond)
	close(done)

	if len(mr.triggered) > 0 {
		t.Fatalf("unexpected reroute: %v", mr.triggered)
	}
}

func TestWatchdogProbeAckValidatesSeq(t *testing.T) {
	mr := &mockRerouter{}
	w := healer.NewWatchdog(mr, 50*time.Millisecond)
	w.AddPeer("peer-z")

	// Let it go degraded
	time.Sleep(120 * time.Millisecond)

	// Send wrong seq — should not reset
	w.OnProbeAck("peer-z", 9999)

	// Should still reroute eventually
	time.Sleep(200 * time.Millisecond)
	if len(mr.triggered) == 0 {
		t.Fatal("expected reroute after bad probe ack")
	}
}
