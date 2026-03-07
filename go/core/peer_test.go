package core

import (
	"net"
	"sync"
	"testing"
)

func fakeAddr(addr string) net.Addr {
	a, _ := net.ResolveTCPAddr("tcp", addr)
	return a
}

func TestPeerManager_Upsert_New(t *testing.T) {
	pm := NewPeerManager()
	info, isNew := pm.Upsert("id-1", "Alice", fakeAddr("127.0.0.1:5000"), PeerConnected)

	if !isNew {
		t.Fatal("expected isNew=true for first insert")
	}
	if info.ID != "id-1" {
		t.Fatalf("ID = %q, want %q", info.ID, "id-1")
	}
	if info.Name != "Alice" {
		t.Fatalf("Name = %q, want %q", info.Name, "Alice")
	}
	if info.DisplayName != "Alice" {
		t.Fatalf("DisplayName = %q, want %q", info.DisplayName, "Alice")
	}
	if info.State != PeerConnected {
		t.Fatalf("State = %d, want %d", info.State, PeerConnected)
	}
}

func TestPeerManager_Upsert_Update(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", fakeAddr("127.0.0.1:5000"), PeerConnecting)
	info, isNew := pm.Upsert("id-1", "Alice2", fakeAddr("127.0.0.1:5001"), PeerConnected)

	if isNew {
		t.Fatal("expected isNew=false for update")
	}
	if info.Name != "Alice2" {
		t.Fatalf("Name = %q, want %q", info.Name, "Alice2")
	}
	if info.State != PeerConnected {
		t.Fatalf("State = %d, want %d", info.State, PeerConnected)
	}
}

func TestPeerManager_DisplayNameCollision(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", fakeAddr("127.0.0.1:5000"), PeerConnected)
	info2, _ := pm.Upsert("id-2", "Alice", fakeAddr("127.0.0.1:5001"), PeerConnected)

	if info2.DisplayName != "Alice#2" {
		t.Fatalf("DisplayName = %q, want %q", info2.DisplayName, "Alice#2")
	}

	info3, _ := pm.Upsert("id-3", "Alice", fakeAddr("127.0.0.1:5002"), PeerConnected)
	if info3.DisplayName != "Alice#3" {
		t.Fatalf("DisplayName = %q, want %q", info3.DisplayName, "Alice#3")
	}
}

func TestPeerManager_Get(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", nil, PeerConnected)

	got := pm.Get("id-1")
	if got == nil {
		t.Fatal("Get returned nil for existing peer")
	}
	if got.Name != "Alice" {
		t.Fatalf("Name = %q, want %q", got.Name, "Alice")
	}

	if pm.Get("nonexistent") != nil {
		t.Fatal("Get should return nil for unknown peer")
	}
}

func TestPeerManager_SetSharedKey(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", nil, PeerConnected)

	key := [32]byte{1, 2, 3}
	pm.SetSharedKey("id-1", key)

	got := pm.Get("id-1")
	if got.SharedKey != key {
		t.Fatal("SharedKey not set correctly")
	}

	pm.SetSharedKey("nonexistent", key)
}

func TestPeerManager_SetPubKey(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", nil, PeerConnected)

	pub := []byte{0xAA, 0xBB}
	pm.SetPubKey("id-1", pub)

	got := pm.Get("id-1")
	if len(got.PubKey) != 2 || got.PubKey[0] != 0xAA {
		t.Fatal("PubKey not set correctly")
	}
}

func TestPeerManager_SetState(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", nil, PeerConnecting)
	pm.SetState("id-1", PeerDisconnected)

	got := pm.Get("id-1")
	if got.State != PeerDisconnected {
		t.Fatalf("State = %d, want %d", got.State, PeerDisconnected)
	}
}

func TestPeerManager_List(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", nil, PeerConnected)
	pm.Upsert("id-2", "Bob", nil, PeerConnected)

	list := pm.List()
	if len(list) != 2 {
		t.Fatalf("List len = %d, want 2", len(list))
	}
}

func TestPeerManager_Remove(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", nil, PeerConnected)
	pm.Remove("id-1")

	if pm.Get("id-1") != nil {
		t.Fatal("peer should be removed")
	}
	if len(pm.List()) != 0 {
		t.Fatal("list should be empty after remove")
	}

	pm.Remove("nonexistent")
}

func TestPeerManager_ConcurrentAccess(t *testing.T) {
	pm := NewPeerManager()
	var wg sync.WaitGroup

	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			id := string(rune('A' + i%26))
			pm.Upsert(id, "name", nil, PeerConnected)
			pm.Get(id)
			pm.List()
			pm.SetState(id, PeerDisconnected)
		}(i)
	}

	wg.Wait()
}
