package healer_test

import (
	"testing"
	"time"

	"github.com/catsi/piper/mesh/healer"
)

type mockRecomputer struct{ called []string }

func (m *mockRecomputer) Recompute(peerID string) { m.called = append(m.called, peerID) }

func TestRerouterDeduplicates(t *testing.T) {
	mc := &mockRecomputer{}
	r := healer.NewRerouter(mc, 50*time.Millisecond)

	r.TriggerReroute("peer-a", "link_dead")
	r.TriggerReroute("peer-a", "link_dead") // duplicate — should be ignored
	r.TriggerReroute("peer-a", "link_dead")

	time.Sleep(200 * time.Millisecond)

	if len(mc.called) != 1 {
		t.Fatalf("want 1 Recompute call, got %d", len(mc.called))
	}
}
