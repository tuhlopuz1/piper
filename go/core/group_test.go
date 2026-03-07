package core

import (
	"sort"
	"sync"
	"testing"
)

func TestGroupManager_Create(t *testing.T) {
	gm := NewGroupManager()
	g := gm.Create("g1", "Test Group", "creator-id")

	if g.ID != "g1" {
		t.Fatalf("ID = %q, want %q", g.ID, "g1")
	}
	if g.Name != "Test Group" {
		t.Fatalf("Name = %q, want %q", g.Name, "Test Group")
	}
	if !g.Members["creator-id"] {
		t.Fatal("creator should be a member")
	}
	if len(g.Members) != 1 {
		t.Fatalf("Members len = %d, want 1", len(g.Members))
	}
}

func TestGroupManager_AddMember(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("g1", "Group", "creator")

	ok := gm.AddMember("g1", "peer-1")
	if !ok {
		t.Fatal("AddMember should return true for new member")
	}

	ok = gm.AddMember("g1", "peer-1")
	if ok {
		t.Fatal("AddMember should return false for existing member")
	}

	ok = gm.AddMember("nonexistent", "peer-1")
	if ok {
		t.Fatal("AddMember should return false for nonexistent group")
	}
}

func TestGroupManager_RemoveMember(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("g1", "Group", "creator")
	gm.AddMember("g1", "peer-1")
	gm.RemoveMember("g1", "peer-1")

	if gm.IsMember("g1", "peer-1") {
		t.Fatal("peer-1 should be removed")
	}
	if !gm.IsMember("g1", "creator") {
		t.Fatal("creator should still be a member")
	}

	gm.RemoveMember("nonexistent", "peer-1")
}

func TestGroupManager_Get(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("g1", "Group", "creator")

	g := gm.Get("g1")
	if g == nil {
		t.Fatal("Get returned nil for existing group")
	}
	if g.Name != "Group" {
		t.Fatalf("Name = %q, want %q", g.Name, "Group")
	}

	if gm.Get("nonexistent") != nil {
		t.Fatal("Get should return nil for unknown group")
	}
}

func TestGroupManager_List(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("g1", "Group1", "c1")
	gm.Create("g2", "Group2", "c2")

	list := gm.List()
	if len(list) != 2 {
		t.Fatalf("List len = %d, want 2", len(list))
	}
}

func TestGroupManager_IsMember(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("g1", "Group", "creator")
	gm.AddMember("g1", "peer-1")

	if !gm.IsMember("g1", "creator") {
		t.Fatal("creator should be a member")
	}
	if !gm.IsMember("g1", "peer-1") {
		t.Fatal("peer-1 should be a member")
	}
	if gm.IsMember("g1", "stranger") {
		t.Fatal("stranger should not be a member")
	}
	if gm.IsMember("nonexistent", "creator") {
		t.Fatal("IsMember should return false for nonexistent group")
	}
}

func TestGroupManager_Delete(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("g1", "Group", "creator")
	gm.Delete("g1")

	if gm.Get("g1") != nil {
		t.Fatal("group should be deleted")
	}
	if len(gm.List()) != 0 {
		t.Fatal("list should be empty after delete")
	}

	gm.Delete("nonexistent")
}

func TestGroup_MemberIDs(t *testing.T) {
	gm := NewGroupManager()
	g := gm.Create("g1", "Group", "a")
	gm.AddMember("g1", "c")
	gm.AddMember("g1", "b")

	ids := g.MemberIDs()
	sort.Strings(ids)
	if len(ids) != 3 {
		t.Fatalf("MemberIDs len = %d, want 3", len(ids))
	}
	if ids[0] != "a" || ids[1] != "b" || ids[2] != "c" {
		t.Fatalf("MemberIDs = %v, want [a b c]", ids)
	}
}

func TestGroupManager_ConcurrentAccess(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("g1", "Group", "creator")

	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			id := string(rune('A' + i%26))
			gm.AddMember("g1", id)
			gm.IsMember("g1", id)
			gm.List()
			gm.Get("g1")
		}(i)
	}
	wg.Wait()
}
