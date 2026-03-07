package router_test

import (
	"testing"

	"github.com/catsi/piper/mesh/router"
)

func TestUpsertNewPeer(t *testing.T) {
	pt := router.NewPeerTable("self-id")
	peer := router.MeshPeer{ID: "peer-a", HashID: 0xAAAA, Name: "Alice", Version: 1}
	changed := pt.Merge(peer)
	if !changed {
		t.Fatal("new peer should trigger changed=true")
	}
	got := pt.Get("peer-a")
	if got == nil {
		t.Fatal("peer not found after merge")
	}
}

func TestMergeRejectsOlderVersion(t *testing.T) {
	pt := router.NewPeerTable("self")
	pt.Merge(router.MeshPeer{ID: "b", HashID: 0xBB, Version: 5})
	changed := pt.Merge(router.MeshPeer{ID: "b", HashID: 0xBB, Version: 3})
	if changed {
		t.Fatal("older version must not overwrite")
	}
}

func TestMergeAcceptsNewerVersion(t *testing.T) {
	pt := router.NewPeerTable("self")
	pt.Merge(router.MeshPeer{ID: "c", HashID: 0xCC, Version: 1})
	changed := pt.Merge(router.MeshPeer{ID: "c", HashID: 0xCC, Version: 2})
	if !changed {
		t.Fatal("newer version must be accepted")
	}
}

func TestGetByHash(t *testing.T) {
	pt := router.NewPeerTable("self")
	pt.Merge(router.MeshPeer{ID: "d", HashID: 0xDDDD, Version: 1})
	got := pt.GetByHash(0xDDDD)
	if got == nil || got.ID != "d" {
		t.Fatalf("GetByHash failed, got %v", got)
	}
}
