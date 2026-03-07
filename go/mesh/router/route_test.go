package router_test

import (
	"testing"

	"github.com/catsi/piper/mesh/router"
)

// Graph: A --10ms--> B --10ms--> C
// A --100ms--> C (direct but worse)
// Dijkstra should find A→B→C with lower weight

func TestDijkstraFindsShortestPath(t *testing.T) {
	pt := router.NewPeerTable("A")
	pt.Merge(router.MeshPeer{
		ID: "B", HashID: 0xBB, Version: 1,
		Links: []router.LinkEntry{
			{PeerHashID: 0xAA, RTTms: 10, LossRatio: 0},
			{PeerHashID: 0xCC, RTTms: 10, LossRatio: 0},
		},
	})
	pt.Merge(router.MeshPeer{
		ID: "C", HashID: 0xCC, Version: 1,
		Links: []router.LinkEntry{
			{PeerHashID: 0xBB, RTTms: 10, LossRatio: 0},
		},
	})

	// local links from A
	localLinks := map[uint32]router.LinkEntry{
		0xBB: {PeerHashID: 0xBB, RTTms: 10, LossRatio: 0},
		0xCC: {PeerHashID: 0xCC, RTTms: 100, LossRatio: 0},
	}

	route := router.Dijkstra(0xAA, 0xCC, pt, localLinks)
	if route == nil {
		t.Fatal("expected route, got nil")
	}
	if len(route.Hops) != 2 {
		t.Fatalf("want 2 hops [B,C] got %v", route.Hops)
	}
	if route.Hops[0] != 0xBB {
		t.Fatalf("first hop want B(0xBB) got %x", route.Hops[0])
	}
}

func TestDijkstraReturnsNilWhenNoPath(t *testing.T) {
	pt := router.NewPeerTable("A")
	route := router.Dijkstra(0xAA, 0xFF, pt, nil)
	if route != nil {
		t.Fatal("expected nil route for unreachable peer")
	}
}

func TestEdgeWeight(t *testing.T) {
	// 5% loss → 5%² × 10000 = 25, RTT=50ms, tcp=0 → weight=75
	w := router.EdgeWeight(50, 0.05, "tcp")
	if w < 74 || w > 76 {
		t.Fatalf("want ~75 got %f", w)
	}

	// 15% loss → 15%² × 10000 = 225, RTT=50ms → weight=275
	w2 := router.EdgeWeight(50, 0.15, "tcp")
	if w2 < 274 || w2 > 276 {
		t.Fatalf("want ~275 got %f", w2)
	}
}

func TestHysteresisBlocksMinorImprovement(t *testing.T) {
	current := &router.Route{Score: 100}
	candidate := &router.Route{Score: 115} // only 13% better — below 25% threshold
	if router.ShouldSwitch(current, candidate) {
		t.Fatal("should not switch for <25% improvement")
	}
}

func TestHysteresisAllowsMajorImprovement(t *testing.T) {
	current := &router.Route{Score: 100}
	candidate := &router.Route{Score: 60} // 40% better — above threshold
	if !router.ShouldSwitch(current, candidate) {
		t.Fatal("should switch for >25% improvement")
	}
}
