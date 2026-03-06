package core

import (
	"sync"
	"testing"
)

func TestPeerUpsertAndGet(t *testing.T) {
	pm := NewPeerManager()
	info, wasNew := pm.Upsert("id-1", "Alice", nil, PeerConnected)

	if !wasNew {
		t.Error("first Upsert should return wasNew=true")
	}
	if info.ID != "id-1" {
		t.Errorf("ID: got %q, want id-1", info.ID)
	}
	if info.Name != "Alice" {
		t.Errorf("Name: got %q, want Alice", info.Name)
	}
	if info.DisplayName != "Alice" {
		t.Errorf("DisplayName: got %q, want Alice", info.DisplayName)
	}
	if info.State != PeerConnected {
		t.Errorf("State: got %v, want PeerConnected", info.State)
	}

	got := pm.Get("id-1")
	if got == nil {
		t.Fatal("Get returned nil for existing peer")
	}
	if got.ID != "id-1" {
		t.Errorf("Get ID: got %q, want id-1", got.ID)
	}
}

func TestPeerUpsertUpdatesExisting(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", nil, PeerConnected)
	info, wasNew := pm.Upsert("id-1", "Alice Renamed", nil, PeerDisconnected)

	if wasNew {
		t.Error("second Upsert for same ID should return wasNew=false")
	}
	if info.Name != "Alice Renamed" {
		t.Errorf("updated Name: got %q, want Alice Renamed", info.Name)
	}
	if info.State != PeerDisconnected {
		t.Errorf("updated State: got %v, want PeerDisconnected", info.State)
	}
}

func TestPeerGetUnknown(t *testing.T) {
	pm := NewPeerManager()
	got := pm.Get("nonexistent")
	if got != nil {
		t.Errorf("Get unknown peer should return nil, got %+v", got)
	}
}

func TestPeerList(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", nil, PeerConnected)
	pm.Upsert("id-2", "Bob", nil, PeerConnected)
	pm.Upsert("id-3", "Charlie", nil, PeerDisconnected)

	list := pm.List()
	if len(list) != 3 {
		t.Errorf("List length: got %d, want 3", len(list))
	}
}

func TestPeerListEmpty(t *testing.T) {
	pm := NewPeerManager()
	list := pm.List()
	if list == nil {
		t.Error("List should return empty slice, not nil")
	}
	if len(list) != 0 {
		t.Errorf("List on empty manager: got %d items", len(list))
	}
}

func TestPeerSetSharedKey(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", nil, PeerConnected)

	var key [32]byte
	key[0] = 0xAB
	key[31] = 0xCD
	pm.SetSharedKey("id-1", key)

	got := pm.Get("id-1")
	if got == nil {
		t.Fatal("peer not found")
	}
	if got.SharedKey != key {
		t.Error("SharedKey was not stored correctly")
	}
}

func TestPeerSetSharedKeyUnknownPeer(t *testing.T) {
	pm := NewPeerManager()
	var key [32]byte
	// Should not panic for unknown peer.
	pm.SetSharedKey("nonexistent", key)
}

func TestPeerSetPubKey(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", nil, PeerConnected)

	pub := make([]byte, 32)
	for i := range pub {
		pub[i] = byte(i)
	}
	pm.SetPubKey("id-1", pub)

	got := pm.Get("id-1")
	if len(got.PubKey) != 32 {
		t.Errorf("PubKey length: got %d, want 32", len(got.PubKey))
	}
	if got.PubKey[15] != 15 {
		t.Error("PubKey content mismatch")
	}
}

func TestPeerSetState(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", nil, PeerConnecting)
	pm.SetState("id-1", PeerConnected)

	got := pm.Get("id-1")
	if got.State != PeerConnected {
		t.Errorf("State after SetState: got %v, want PeerConnected", got.State)
	}
}

func TestPeerRemove(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", nil, PeerConnected)
	pm.Remove("id-1")

	got := pm.Get("id-1")
	if got != nil {
		t.Error("Get after Remove should return nil")
	}
	if len(pm.List()) != 0 {
		t.Error("List after Remove should be empty")
	}
}

func TestPeerDisplayNameUniqueness(t *testing.T) {
	pm := NewPeerManager()
	// Add two peers with the same name.
	pm.Upsert("id-1", "Alice", nil, PeerConnected)
	pm.Upsert("id-2", "Alice", nil, PeerConnected)
	pm.Upsert("id-3", "Alice", nil, PeerConnected)

	p1 := pm.Get("id-1")
	p2 := pm.Get("id-2")
	p3 := pm.Get("id-3")

	names := map[string]bool{
		p1.DisplayName: true,
		p2.DisplayName: true,
		p3.DisplayName: true,
	}
	if len(names) != 3 {
		t.Errorf("display names are not unique: %q %q %q", p1.DisplayName, p2.DisplayName, p3.DisplayName)
	}
}

func TestPeerConcurrency(t *testing.T) {
	pm := NewPeerManager()
	var wg sync.WaitGroup

	// 10 goroutines each upsert a different peer and then read it.
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			id := string(rune('a'+n)) + "-id"
			name := string(rune('A' + n))
			pm.Upsert(id, name, nil, PeerConnected)
			_ = pm.Get(id)
			_ = pm.List()
		}(i)
	}
	wg.Wait()

	if len(pm.List()) != 10 {
		t.Errorf("expected 10 peers after concurrent upsert, got %d", len(pm.List()))
	}
}

func TestPeerConcurrentSharedKeyUpdates(t *testing.T) {
	pm := NewPeerManager()
	pm.Upsert("id-1", "Alice", nil, PeerConnected)

	var wg sync.WaitGroup
	var key [32]byte
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			key[0] = byte(n)
			pm.SetSharedKey("id-1", key)
			_ = pm.Get("id-1")
		}(i)
	}
	wg.Wait()
	// If the race detector doesn't fire, we're good.
}
