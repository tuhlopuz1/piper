package core

import (
	"sync"
	"testing"
)

func TestGroupCreateAndGet(t *testing.T) {
	gm := NewGroupManager()
	g := gm.Create("grp-1", "Dev Team", "creator-id")

	if g == nil {
		t.Fatal("Create returned nil")
	}
	if g.ID != "grp-1" {
		t.Errorf("ID: got %q, want grp-1", g.ID)
	}
	if g.Name != "Dev Team" {
		t.Errorf("Name: got %q, want Dev Team", g.Name)
	}
	if !g.Members["creator-id"] {
		t.Error("creator should be in Members after Create")
	}

	got := gm.Get("grp-1")
	if got == nil {
		t.Fatal("Get returned nil for existing group")
	}
	if got.ID != "grp-1" {
		t.Errorf("Get ID: got %q, want grp-1", got.ID)
	}
}

func TestGroupGetUnknown(t *testing.T) {
	gm := NewGroupManager()
	got := gm.Get("nonexistent")
	if got != nil {
		t.Errorf("Get unknown group should return nil, got %+v", got)
	}
}

func TestGroupAddMember(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("grp-1", "Team", "alice")

	added := gm.AddMember("grp-1", "bob")
	if !added {
		t.Error("AddMember should return true for new member")
	}

	g := gm.Get("grp-1")
	if !g.Members["bob"] {
		t.Error("bob should be in Members after AddMember")
	}
}

func TestGroupAddMemberDuplicate(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("grp-1", "Team", "alice")
	gm.AddMember("grp-1", "bob")

	added := gm.AddMember("grp-1", "bob")
	if added {
		t.Error("AddMember for existing member should return false")
	}
}

func TestGroupAddMemberUnknownGroup(t *testing.T) {
	gm := NewGroupManager()
	added := gm.AddMember("nonexistent", "bob")
	if added {
		t.Error("AddMember to nonexistent group should return false")
	}
}

func TestGroupRemoveMember(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("grp-1", "Team", "alice")
	gm.AddMember("grp-1", "bob")

	gm.RemoveMember("grp-1", "bob")
	g := gm.Get("grp-1")
	if g.Members["bob"] {
		t.Error("bob should not be in Members after RemoveMember")
	}
	if !g.Members["alice"] {
		t.Error("alice should still be in Members after removing bob")
	}
}

func TestGroupRemoveMemberUnknownGroup(t *testing.T) {
	gm := NewGroupManager()
	// Should not panic.
	gm.RemoveMember("nonexistent", "bob")
}

func TestGroupMemberIDs(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("grp-1", "Team", "alice")
	gm.AddMember("grp-1", "bob")
	gm.AddMember("grp-1", "charlie")

	g := gm.Get("grp-1")
	ids := g.MemberIDs()
	if len(ids) != 3 {
		t.Errorf("MemberIDs length: got %d, want 3", len(ids))
	}
	idSet := make(map[string]bool)
	for _, id := range ids {
		idSet[id] = true
	}
	for _, expected := range []string{"alice", "bob", "charlie"} {
		if !idSet[expected] {
			t.Errorf("MemberIDs missing %q", expected)
		}
	}
}

func TestGroupIsMember(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("grp-1", "Team", "alice")

	if !gm.IsMember("grp-1", "alice") {
		t.Error("alice should be member")
	}
	if gm.IsMember("grp-1", "bob") {
		t.Error("bob should not be member")
	}
	if gm.IsMember("nonexistent", "alice") {
		t.Error("IsMember on nonexistent group should return false")
	}
}

func TestGroupDelete(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("grp-1", "Team", "alice")
	gm.Delete("grp-1")

	got := gm.Get("grp-1")
	if got != nil {
		t.Error("Get after Delete should return nil")
	}
}

func TestGroupDeleteNonexistent(t *testing.T) {
	gm := NewGroupManager()
	// Should not panic.
	gm.Delete("nonexistent")
}

func TestGroupList(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("grp-1", "Team A", "alice")
	gm.Create("grp-2", "Team B", "bob")

	list := gm.List()
	if len(list) != 2 {
		t.Errorf("List length: got %d, want 2", len(list))
	}
}

func TestGroupListEmpty(t *testing.T) {
	gm := NewGroupManager()
	list := gm.List()
	if list == nil {
		t.Error("List should return empty slice, not nil")
	}
}

func TestGroupConcurrency(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("grp-1", "Team", "creator")

	var wg sync.WaitGroup
	// 5 goroutines add members, 5 goroutines check membership.
	for i := 0; i < 5; i++ {
		wg.Add(2)
		go func(n int) {
			defer wg.Done()
			id := string(rune('a' + n))
			gm.AddMember("grp-1", id)
		}(i)
		go func(n int) {
			defer wg.Done()
			id := string(rune('a' + n))
			_ = gm.IsMember("grp-1", id)
			_ = gm.Get("grp-1")
		}(i)
	}
	wg.Wait()
	// Race detector validates no concurrent map access.
}

func TestGroupMultipleGroupsIsolated(t *testing.T) {
	gm := NewGroupManager()
	gm.Create("grp-1", "A", "alice")
	gm.Create("grp-2", "B", "bob")
	gm.AddMember("grp-1", "charlie")

	g2 := gm.Get("grp-2")
	if g2.Members["charlie"] {
		t.Error("charlie should only be in grp-1, not grp-2")
	}
}
