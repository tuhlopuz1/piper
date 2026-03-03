package core

import "sync"

// Group represents a chat group with a set of members.
type Group struct {
	ID      string
	Name    string
	Members map[string]bool // set of peer IDs (includes self)
}

// MemberIDs returns a sorted-stable slice of member IDs.
func (g *Group) MemberIDs() []string {
	out := make([]string, 0, len(g.Members))
	for id := range g.Members {
		out = append(out, id)
	}
	return out
}

// GroupEventKind categorises group lifecycle events.
type GroupEventKind int

const (
	GroupCreated       GroupEventKind = iota
	GroupMemberJoined
	GroupMemberLeft
	GroupDeleted
)

// GroupEvent is emitted on the Node event channel when group state changes.
type GroupEvent struct {
	Group    *Group
	PeerID   string         // the peer who joined/left (empty for create/delete)
	PeerName string         // display name of the peer
	Kind     GroupEventKind
}

// GroupManager provides thread-safe CRUD for groups.
type GroupManager struct {
	mu     sync.RWMutex
	groups map[string]*Group
}

// NewGroupManager creates an empty GroupManager.
func NewGroupManager() *GroupManager {
	return &GroupManager{groups: make(map[string]*Group)}
}

// Create makes a new group with creatorID as the sole member.
func (gm *GroupManager) Create(id, name, creatorID string) *Group {
	gm.mu.Lock()
	defer gm.mu.Unlock()
	g := &Group{
		ID:      id,
		Name:    name,
		Members: map[string]bool{creatorID: true},
	}
	gm.groups[id] = g
	return g
}

// AddMember adds peerID to the group. Returns false if the group doesn't exist
// or the peer is already a member.
func (gm *GroupManager) AddMember(groupID, peerID string) bool {
	gm.mu.Lock()
	defer gm.mu.Unlock()
	g, ok := gm.groups[groupID]
	if !ok {
		return false
	}
	if g.Members[peerID] {
		return false
	}
	g.Members[peerID] = true
	return true
}

// RemoveMember removes peerID from the group.
func (gm *GroupManager) RemoveMember(groupID, peerID string) {
	gm.mu.Lock()
	defer gm.mu.Unlock()
	if g, ok := gm.groups[groupID]; ok {
		delete(g.Members, peerID)
	}
}

// Get returns the group by ID, or nil if not found.
func (gm *GroupManager) Get(groupID string) *Group {
	gm.mu.RLock()
	defer gm.mu.RUnlock()
	return gm.groups[groupID]
}

// List returns a snapshot of all groups.
func (gm *GroupManager) List() []*Group {
	gm.mu.RLock()
	defer gm.mu.RUnlock()
	out := make([]*Group, 0, len(gm.groups))
	for _, g := range gm.groups {
		out = append(out, g)
	}
	return out
}

// IsMember checks if peerID is in the group.
func (gm *GroupManager) IsMember(groupID, peerID string) bool {
	gm.mu.RLock()
	defer gm.mu.RUnlock()
	g, ok := gm.groups[groupID]
	if !ok {
		return false
	}
	return g.Members[peerID]
}

// Delete removes a group entirely.
func (gm *GroupManager) Delete(groupID string) {
	gm.mu.Lock()
	defer gm.mu.Unlock()
	delete(gm.groups, groupID)
}
