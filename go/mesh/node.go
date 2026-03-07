package mesh

import (
	"context"
	"log"
	"path/filepath"
	"time"

	"github.com/catsi/piper/core"
	piperdht "github.com/catsi/piper/mesh/dht"
	"github.com/catsi/piper/mesh/healer"
	"github.com/catsi/piper/mesh/identity"
	"github.com/catsi/piper/mesh/proxy"
	"github.com/catsi/piper/mesh/queue"
	"github.com/catsi/piper/mesh/router"
	"github.com/catsi/piper/mesh/store"
	"github.com/google/uuid"
	"github.com/libp2p/go-libp2p/core/host"
	"go.etcd.io/bbolt"
)

type Node struct {
	id   string
	name string

	// Storage (optional — nil until InitStorage is called)
	storagePath string
	db          *bbolt.DB

	// Identity (loaded after InitStorage)
	identMgr *identity.Manager

	// Retry queue (initialised after InitStorage)
	retryQ *queue.RetryQueue

	// DHT store-and-forward (initialised in Start if storage is available)
	dhtHost      host.Host
	offlineStore *piperdht.OfflineStore

	// Node lifecycle context (cancelled in Stop)
	ctx    context.Context
	cancel context.CancelFunc

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

// NewNodeWithStorage creates a Node and immediately opens the bbolt database
// at storagePath/piper.db, deriving identity keys from the persistent seed.
func NewNodeWithStorage(name, id, storagePath string) (*Node, error) {
	n := NewNodeWithID(name, id)
	if err := n.InitStorage(storagePath); err != nil {
		return nil, err
	}
	return n, nil
}

// InitStorage opens the bbolt database and loads the persistent identity.
// Safe to call at most once per Node.
func (n *Node) InitStorage(storagePath string) error {
	db, err := store.Open(filepath.Join(storagePath, "piper.db"))
	if err != nil {
		return err
	}
	n.storagePath = storagePath
	n.db = db
	n.retryQ = queue.New(db)

	mgr, err := identity.Load(storagePath)
	if err != nil {
		db.Close()
		return err
	}
	n.identMgr = mgr
	return nil
}

// IdentityManager returns the loaded identity manager, or nil if storage was
// not initialised.
func (n *Node) IdentityManager() *identity.Manager {
	return n.identMgr
}

func (n *Node) Start() error {
	n.ctx, n.cancel = context.WithCancel(context.Background())

	n.legacy = core.NewNodeWithID(n.name, n.id)
	if err := n.legacy.Start(); err != nil {
		n.cancel()
		return err
	}

	// Initialize mesh subsystems.
	rt := &meshRouter{node: n}
	n.proxyMgr = proxy.NewProxyManager(rt)
	n.rerouter = healer.NewRerouter(rt, 500_000_000)
	n.watchdog = healer.NewWatchdog(n.rerouter, 500_000_000)

	// Forward legacy events; flush retry queue on PeerJoined.
	go func() {
		for ev := range n.legacy.Events() {
			if ev.Peer != nil && ev.Peer.Kind == core.PeerJoined && n.retryQ != nil {
				go n.flushRetryQueue(ev.Peer.Peer.ID)
			}
			n.events <- ev
		}
	}()

	// Retry queue expiry ticker.
	if n.retryQ != nil {
		go n.expireTicker()
	}

	// DHT initialisation: start after a 3-second gossip settle delay so
	// the peer table is populated before bootstrapping.
	if n.identMgr != nil && n.db != nil {
		go n.initDHT()
	}

	return nil
}

// initDHT starts the libp2p host + kad-dht, bootstraps from the peer table,
// and fetches any pending messages from our DHT inbox.
func (n *Node) initDHT() {
	time.Sleep(3 * time.Second)

	// Use meshPort+1 for the DHT host.
	meshPort := n.legacy.LocalEndpoint().Port
	h, err := piperdht.NewHost(n.identMgr.Keys, meshPort+1)
	if err != nil {
		log.Printf("[mesh] initDHT: NewHost: %v", err)
		return
	}
	n.dhtHost = h

	kadDHT, err := piperdht.NewKadDHT(n.ctx, h)
	if err != nil {
		log.Printf("[mesh] initDHT: NewKadDHT: %v", err)
		h.Close()
		return
	}

	n.offlineStore = piperdht.NewOfflineStore(n.identMgr.Keys, n.id, kadDHT, n.db)

	// Bootstrap from known peers that advertise identity keys.
	bootstrapPeers := piperdht.BootstrapPeers(n.table.All(), 1)
	for _, pInfo := range bootstrapPeers {
		if err := h.Connect(n.ctx, pInfo); err != nil {
			log.Printf("[mesh] initDHT: connect to %s: %v", pInfo.ID, err)
		}
	}
	if err := kadDHT.Bootstrap(n.ctx); err != nil {
		log.Printf("[mesh] initDHT: Bootstrap: %v", err)
	}

	// Fetch pending messages from our DHT inbox.
	if err := n.offlineStore.FetchAndDeliver(n.ctx, n.emitDHTMessage); err != nil {
		log.Printf("[mesh] initDHT: FetchAndDeliver: %v", err)
	}
}

// emitDHTMessage converts a DHT-delivered message into a core.Event.
func (n *Node) emitDHTMessage(msg piperdht.DeliveredMsg) {
	ev := core.Event{
		Msg: &core.Message{
			ID:      msg.MsgID,
			Type:    core.MsgTypeDirect,
			PeerID:  msg.SenderPeerID,
			Content: msg.Text,
			To:      n.id,
		},
	}
	select {
	case n.events <- ev:
	default:
		log.Printf("[mesh] emitDHTMessage: event buffer full, dropping msg %s", msg.MsgID)
	}
}

func (n *Node) Stop() {
	if n.cancel != nil {
		n.cancel()
	}
	n.watchdog.Stop()
	n.legacy.Stop()
	if n.dhtHost != nil {
		n.dhtHost.Close()
	}
	if n.db != nil {
		n.db.Close()
	}
}

func (n *Node) ID() string   { return n.id }
func (n *Node) Name() string { return n.name }

func (n *Node) OpenProxy(peerID, remoteIcePwd string) (int, error) {
	return n.proxyMgr.OpenProxy(peerID, remoteIcePwd)
}

func (n *Node) CloseProxy(peerID string) {
	n.proxyMgr.CloseProxy(peerID)
}

// Send sends a direct message. If the peer is offline and storage is
// available, the message is queued for later delivery.
func (n *Node) Send(text, toPeerID string) {
	if toPeerID == "" || n.isPeerConnected(toPeerID) {
		n.legacy.Send(text, toPeerID)
		return
	}
	if n.retryQ == nil {
		// No storage: fall through to legacy (which will likely fail silently).
		n.legacy.Send(text, toPeerID)
		return
	}
	entry := queue.RetryEntry{
		MsgID:  uuid.New().String(),
		PeerID: toPeerID,
		Text:   text,
	}
	if err := n.retryQ.Enqueue(entry); err != nil {
		log.Printf("[mesh] retryQ.Enqueue: %v", err)
	}
}

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
func (n *Node) Rescan()                                 { n.legacy.Rescan() }
func (n *Node) SendFileToGroup(gid, path string) (int, error) {
	return n.legacy.SendFileToGroup(gid, path)
}

// PendingCount returns how many messages are queued for peerID.
func (n *Node) PendingCount(peerID string) int {
	if n.retryQ == nil {
		return 0
	}
	entries, err := n.retryQ.Flush(peerID)
	if err != nil {
		return 0
	}
	// Re-enqueue since Flush deletes.
	for _, e := range entries {
		_ = n.retryQ.Enqueue(e)
	}
	return len(entries)
}

// DHTDiag returns diagnostic information about the DHT subsystem.
func (n *Node) DHTDiag() map[string]interface{} {
	diag := map[string]interface{}{"status": "unavailable"}
	if n.dhtHost == nil {
		return diag
	}
	peers := n.dhtHost.Network().Peers()
	addrs := n.dhtHost.Addrs()
	addrStrs := make([]string, len(addrs))
	for i, a := range addrs {
		addrStrs[i] = a.String()
	}
	diag["status"] = "ok"
	diag["peer_id"] = n.dhtHost.ID().String()
	diag["dht_peers"] = len(peers)
	diag["addrs"] = addrStrs
	return diag
}

// ── internal helpers ─────────────────────────────────────────────────────────

func (n *Node) isPeerConnected(peerID string) bool {
	for _, p := range n.legacy.Peers() {
		if p.ID == peerID && p.State == core.PeerConnected {
			return true
		}
	}
	return false
}

func (n *Node) flushRetryQueue(peerID string) {
	entries, err := n.retryQ.Flush(peerID)
	if err != nil {
		log.Printf("[mesh] retryQ.Flush(%s): %v", peerID, err)
		return
	}
	for _, e := range entries {
		n.legacy.Send(e.Text, e.PeerID)
	}
	if len(entries) > 0 {
		log.Printf("[mesh] flushed %d queued msgs to %s", len(entries), peerID)
	}
}

func (n *Node) expireTicker() {
	t := time.NewTicker(5 * time.Minute)
	defer t.Stop()
	for {
		select {
		case <-n.ctx.Done():
			return
		case <-t.C:
			if err := n.retryQ.Expire(); err != nil {
				log.Printf("[mesh] retryQ.Expire: %v", err)
			}
		}
	}
}

// escalateToDHT publishes all queued messages for peerID to the DHT.
// Called by meshRouter.Recompute when the link is declared dead.
func (n *Node) escalateToDHT(peerID string) {
	if n.offlineStore == nil || n.retryQ == nil {
		return
	}
	peer := n.table.Get(peerID)
	if peer == nil || len(peer.IdentityX25519Pub) != 32 {
		return // recipient's identity unknown — can't seal
	}
	var recipientPub [32]byte
	copy(recipientPub[:], peer.IdentityX25519Pub)

	entries, err := n.retryQ.Flush(peerID)
	if err != nil {
		log.Printf("[mesh] escalateToDHT: flush: %v", err)
		return
	}
	for _, e := range entries {
		storeCtx, cancel := context.WithTimeout(n.ctx, 30*time.Second)
		if err := n.offlineStore.Store(storeCtx, e.MsgID, e.Text, recipientPub); err != nil {
			log.Printf("[mesh] escalateToDHT: store %s: %v", e.MsgID, err)
		}
		cancel()
	}
	if len(entries) > 0 {
		log.Printf("[mesh] escalated %d msgs for %s to DHT", len(entries), peerID)
	}
}

// meshRouter implements proxy.Router and healer.Recomputer
type meshRouter struct{ node *Node }

func (r *meshRouter) Send(peerID string, payload []byte, bufPtr *[]byte) { /* Phase 6 */ }

// Recompute is called when a link is declared dead. Escalate queued messages
// to the DHT so they survive sender going offline.
func (r *meshRouter) Recompute(peerID string) {
	go r.node.escalateToDHT(peerID)
}
