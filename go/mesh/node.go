package mesh

import (
	"github.com/catsi/piper/core"
	"github.com/catsi/piper/mesh/healer"
	"github.com/catsi/piper/mesh/proxy"
	"github.com/catsi/piper/mesh/router"
	"github.com/google/uuid"
)

type Node struct {
	id   string
	name string

	table    *router.PeerTable
	proxyMgr *proxy.ProxyManager
	watchdog *healer.Watchdog
	rerouter *healer.RerouterImpl

	// Delegate messaging to core.Node until full cutover
	legacy *core.Node
	events chan core.Event
}

func NewNode(name string) *Node {
	return NewNodeWithID(name, uuid.New().String())
}

func NewNodeWithID(name, id string) *Node {
	n := &Node{
		id:     id,
		name:   name,
		events: make(chan core.Event, 256),
	}
	n.table = router.NewPeerTable(id)
	return n
}

func (n *Node) Start() error {
	n.legacy = core.NewNodeWithID(n.name, n.id)
	if err := n.legacy.Start(); err != nil {
		return err
	}

	// Initialize mesh subsystems
	rt := &meshRouter{node: n}
	n.proxyMgr = proxy.NewProxyManager(rt)
	n.rerouter = healer.NewRerouter(rt, 500_000_000) // 500ms
	n.watchdog = healer.NewWatchdog(n.rerouter, 500_000_000)

	// Forward legacy events to our channel
	go func() {
		for ev := range n.legacy.Events() {
			n.events <- ev
		}
	}()
	return nil
}

func (n *Node) Stop() {
	n.watchdog.Stop()
	n.legacy.Stop()
}

func (n *Node) ID() string   { return n.id }
func (n *Node) Name() string { return n.name }

func (n *Node) OpenProxy(peerID, remoteIcePwd string) (int, error) {
	return n.proxyMgr.OpenProxy(peerID, remoteIcePwd)
}

func (n *Node) CloseProxy(peerID string) {
	n.proxyMgr.CloseProxy(peerID)
}

// Delegate all messaging to legacy core.Node
func (n *Node) Send(text, toPeerID string)              { n.legacy.Send(text, toPeerID) }
func (n *Node) SendGroup(text, groupID string)          { n.legacy.SendGroup(text, groupID) }
func (n *Node) SendCallSignal(to, t, p string) error    { return n.legacy.SendCallSignal(to, t, p) }
func (n *Node) PeerTable() []core.PeerRecord            { return n.legacy.PeerTable() }
func (n *Node) InjectPeers(r []core.PeerRecord)         { n.legacy.InjectPeers(r) }
func (n *Node) LocalEndpoint() core.PeerRecord          { return n.legacy.LocalEndpoint() }
func (n *Node) Events() <-chan core.Event                { return n.events }
func (n *Node) Peers() []*core.PeerInfo                 { return n.legacy.Peers() }
func (n *Node) Groups() []*core.Group                   { return n.legacy.Groups() }
func (n *Node) SetName(name string)                     { n.name = name; n.legacy.SetName(name) }
func (n *Node) SetDownloadsDir(dir string)              { n.legacy.SetDownloadsDir(dir) }
func (n *Node) CreateGroup(name string) *core.Group     { return n.legacy.CreateGroup(name) }
func (n *Node) InviteToGroup(gid, pid string)           { n.legacy.InviteToGroup(gid, pid) }
func (n *Node) LeaveGroup(groupID string)               { n.legacy.LeaveGroup(groupID) }
func (n *Node) SendFile(peerID, path string) error      { return n.legacy.SendFile(peerID, path) }
func (n *Node) SendFileToGroup(gid, path string) (int, error) {
	return n.legacy.SendFileToGroup(gid, path)
}

// meshRouter implements proxy.Router and healer.Recomputer
type meshRouter struct{ node *Node }

func (r *meshRouter) Send(peerID string, payload []byte, bufPtr *[]byte) { /* Phase 6 */ }
func (r *meshRouter) Recompute(peerID string)                            { /* Phase 6 */ }
