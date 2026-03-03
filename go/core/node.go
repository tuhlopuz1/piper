package core

// node.go — central P2P node.
//
// Lifecycle:
//   node := NewNode(name)
//   node.Start()                    // starts TCP listener + discovery
//   node.Send(text, "")             // broadcast to global chat
//   node.Send(text, peerID)         // encrypted personal message to one peer
//   for e := range node.Events() { ... }
//   node.Stop()

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/google/uuid"
)

// Event is the sum type emitted on Node.Events().
type Event struct {
	Msg      *Message        // non-nil for incoming/outgoing messages (after decrypt)
	Peer     *PeerEvent      // non-nil for peer join/leave notifications
	Group    *GroupEvent     // non-nil for group lifecycle events
	Transfer *TransferEvent  // non-nil for file transfer lifecycle events
}

// Node is the central P2P object. It is safe for concurrent use.
type Node struct {
	id      string  // stable UUID for this session
	name    string  // display name chosen by the user
	keyPair KeyPair // X25519 keypair (generated on startup)

	listener  net.Listener
	port      int
	discovery *Discovery
	peers     *PeerManager
	groups    *GroupManager
	transfers *TransferManager

	// connByPeerID maps peerID -> *conn (active TCP connection).
	mu           sync.Mutex
	connByPeerID map[string]*conn

	eventCh chan Event
	ctx     context.Context
	cancel  context.CancelFunc
}

// conn wraps a net.Conn and the framing reader/writer.
type conn struct {
	peerID string
	c      net.Conn
	r      *bufio.Reader
	mu     sync.Mutex // serialises writes
}

func (c *conn) send(msg Message) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.c.SetWriteDeadline(time.Now().Add(5 * time.Second))
	return WriteMsg(c.c, msg)
}

// NewNode creates a Node with the given display name.
// The node is not started until Start() is called.
func NewNode(name string) *Node {
	ctx, cancel := context.WithCancel(context.Background())

	kp, err := GenerateKeyPair()
	if err != nil {
		// Should never fail; panic is acceptable here.
		panic("piper: GenerateKeyPair: " + err.Error())
	}

	return &Node{
		id:           uuid.NewString(),
		name:         name,
		keyPair:      kp,
		peers:        NewPeerManager(),
		groups:       NewGroupManager(),
		transfers:    NewTransferManager(),
		connByPeerID: make(map[string]*conn),
		eventCh:      make(chan Event, 128),
		ctx:          ctx,
		cancel:       cancel,
	}
}

// ID returns the stable peer ID for this node.
func (n *Node) ID() string { return n.id }

// Name returns the display name for this node.
func (n *Node) Name() string { return n.name }

// Events returns the read-only event channel.
func (n *Node) Events() <-chan Event { return n.eventCh }

// Peers returns a snapshot of all known peers.
func (n *Node) Peers() []*PeerInfo { return n.peers.List() }

// PeerByID returns the PeerInfo for the given ID, or nil if not found.
func (n *Node) PeerByID(id string) *PeerInfo { return n.peers.Get(id) }

// Groups returns a snapshot of all groups this node belongs to.
func (n *Node) Groups() []*Group { return n.groups.List() }

// GroupByID returns the group for the given ID, or nil.
func (n *Node) GroupByID(id string) *Group { return n.groups.Get(id) }

// CreateGroup creates a new group with the given name and self as the sole member.
func (n *Node) CreateGroup(name string) *Group {
	gid := uuid.NewString()
	g := n.groups.Create(gid, name, n.id)
	log.Printf("[node] created group %q (%s)", name, gid[:8])
	n.emit(Event{Group: &GroupEvent{Group: g, Kind: GroupCreated}})
	return g
}

// InviteToGroup sends a GroupInvite to peerID and adds them to local membership.
func (n *Node) InviteToGroup(groupID, peerID string) {
	g := n.groups.Get(groupID)
	if g == nil {
		log.Printf("[node] InviteToGroup: unknown group %s", groupID[:8])
		return
	}
	peer := n.peers.Get(peerID)
	if peer == nil {
		log.Printf("[node] InviteToGroup: unknown peer %s", peerID)
		return
	}
	n.groups.AddMember(groupID, peerID)

	invite := Message{
		ID:        uuid.NewString(),
		Type:      MsgTypeGroupInvite,
		PeerID:    n.id,
		Name:      n.name,
		GroupID:   groupID,
		GroupName: g.Name,
		Members:   g.MemberIDs(),
		Timestamp: time.Now(),
	}

	n.mu.Lock()
	cn := n.connByPeerID[peerID]
	n.mu.Unlock()
	if cn != nil {
		cn.send(invite)
	}
	log.Printf("[node] invited %s to group %q", peer.DisplayName, g.Name)
	n.emit(Event{Group: &GroupEvent{Group: g, PeerID: peerID, PeerName: peer.DisplayName, Kind: GroupMemberJoined}})
}

// LeaveGroup sends GroupLeave to all members and removes self from the group.
func (n *Node) LeaveGroup(groupID string) {
	g := n.groups.Get(groupID)
	if g == nil {
		return
	}
	leaveMsg := Message{
		ID:        uuid.NewString(),
		Type:      MsgTypeGroupLeave,
		PeerID:    n.id,
		Name:      n.name,
		GroupID:   groupID,
		Timestamp: time.Now(),
	}
	n.sendToGroupMembers(g, leaveMsg)
	log.Printf("[node] left group %q", g.Name)
	n.emit(Event{Group: &GroupEvent{Group: g, PeerID: n.id, PeerName: n.name, Kind: GroupMemberLeft}})
	n.groups.Delete(groupID)
}

// SendGroup encrypts text per-member (fanout) and unicasts to each group member.
func (n *Node) SendGroup(text, groupID string) {
	g := n.groups.Get(groupID)
	if g == nil {
		return
	}

	// Echo plaintext to ourselves for display.
	echo := Message{
		ID:        uuid.NewString(),
		Type:      MsgTypeGroupText,
		PeerID:    n.id,
		Name:      n.name,
		Content:   text,
		GroupID:   groupID,
		Timestamp: time.Now(),
	}
	n.emit(Event{Msg: &echo})

	// Encrypt per-member and send.
	for memberID := range g.Members {
		if memberID == n.id {
			continue
		}
		peer := n.peers.Get(memberID)
		if peer == nil || isZeroKey(peer.SharedKey) {
			continue
		}
		nonce, ciphertext, err := Encrypt(peer.SharedKey, text)
		if err != nil {
			log.Printf("[node] group encrypt for %s: %v", memberID[:8], err)
			continue
		}
		wireMsg := Message{
			ID:        echo.ID,
			Type:      MsgTypeGroupText,
			PeerID:    n.id,
			Name:      n.name,
			Content:   ciphertext,
			To:        memberID,
			GroupID:   groupID,
			Nonce:     nonce,
			Timestamp: echo.Timestamp,
		}
		n.mu.Lock()
		cn := n.connByPeerID[memberID]
		n.mu.Unlock()
		if cn != nil {
			cn.send(wireMsg)
		}
	}
}

// sendToGroupMembers unicasts msg to all group members (except self).
func (n *Node) sendToGroupMembers(g *Group, msg Message) {
	for memberID := range g.Members {
		if memberID == n.id {
			continue
		}
		n.mu.Lock()
		cn := n.connByPeerID[memberID]
		n.mu.Unlock()
		if cn != nil {
			cn.send(msg)
		}
	}
}

// Transfers returns the TransferManager for inspecting active transfers.
func (n *Node) Transfers() *TransferManager { return n.transfers }

// SendFile initiates a file transfer to peerID. It opens the file, sends a
// FileOffer, and spawns a background goroutine that streams encrypted chunks
// once the receiver auto-accepts.
func (n *Node) SendFile(peerID, filePath string) error {
	peer := n.peers.Get(peerID)
	if peer == nil {
		return fmt.Errorf("unknown peer %s", peerID)
	}
	if isZeroKey(peer.SharedKey) {
		return fmt.Errorf("no shared key with peer %s (handshake incomplete)", peerID)
	}

	f, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("open file: %w", err)
	}
	info, err := f.Stat()
	if err != nil {
		f.Close()
		return fmt.Errorf("stat file: %w", err)
	}
	if info.IsDir() {
		f.Close()
		return fmt.Errorf("%s is a directory", filePath)
	}

	tid := uuid.NewString()
	t := n.transfers.Start(tid, peerID, info.Name(), info.Size(), true)
	t.file = f
	t.filePath = filePath

	// Send offer to receiver.
	offer := Message{
		ID:         uuid.NewString(),
		Type:       MsgTypeFileOffer,
		PeerID:     n.id,
		Name:       n.name,
		To:         peerID,
		TransferID: tid,
		FileName:   info.Name(),
		FileSize:   info.Size(),
		Timestamp:  time.Now(),
	}

	n.mu.Lock()
	cn := n.connByPeerID[peerID]
	n.mu.Unlock()
	if cn == nil {
		f.Close()
		n.transfers.Fail(tid, "no connection to peer")
		return fmt.Errorf("no connection to peer %s", peerID)
	}
	if err := cn.send(offer); err != nil {
		f.Close()
		n.transfers.Fail(tid, err.Error())
		return fmt.Errorf("send offer: %w", err)
	}

	n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferOffered}})
	log.Printf("[node] sent file offer %q (%d bytes) to %s", info.Name(), info.Size(), peer.DisplayName)

	// Spawn goroutine that waits for accept and streams chunks.
	go n.streamFileChunks(t, peer.SharedKey, cn)
	return nil
}

// streamFileChunks waits for FileAccept (via t.accepted channel), then reads
// the file in ChunkSize pieces, encrypts each with the shared key, and sends
// FileChunk messages. Finally it sends FileDone with the SHA-256 hash.
func (n *Node) streamFileChunks(t *Transfer, key [32]byte, cn *conn) {
	// Wait for FileAccept or timeout.
	select {
	case <-t.accepted:
		// Accepted — proceed.
	case <-time.After(30 * time.Second):
		n.transfers.Fail(t.ID, "accept timeout")
		t.file.Close()
		n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferFailed}})
		return
	case <-n.ctx.Done():
		t.file.Close()
		return
	}

	defer t.file.Close()
	buf := make([]byte, ChunkSize)
	seq := 0
	h := sha256.New()

	for {
		nr, readErr := t.file.Read(buf)
		if nr > 0 {
			chunk := buf[:nr]
			h.Write(chunk)

			nonce, ct, err := EncryptBytes(key, chunk)
			if err != nil {
				n.transfers.Fail(t.ID, "encrypt: "+err.Error())
				n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferFailed}})
				return
			}

			msg := Message{
				ID:         uuid.NewString(),
				Type:       MsgTypeFileChunk,
				PeerID:     n.id,
				Name:       n.name,
				To:         t.PeerID,
				TransferID: t.ID,
				ChunkSeq:   seq,
				ChunkData:  ct,
				Nonce:      nonce,
				Timestamp:  time.Now(),
			}
			if err := cn.send(msg); err != nil {
				n.transfers.Fail(t.ID, "send chunk: "+err.Error())
				n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferFailed}})
				return
			}

			seq++
			n.transfers.UpdateProgress(t.ID, t.Progress+int64(nr))
			t.Progress += int64(nr)
			n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferProgress}})
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			n.transfers.Fail(t.ID, "read file: "+readErr.Error())
			n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferFailed}})
			return
		}
	}

	// Send FileDone with hash.
	hashHex := hex.EncodeToString(h.Sum(nil))
	done := Message{
		ID:         uuid.NewString(),
		Type:       MsgTypeFileDone,
		PeerID:     n.id,
		Name:       n.name,
		To:         t.PeerID,
		TransferID: t.ID,
		FileHash:   hashHex,
		Timestamp:  time.Now(),
	}
	if err := cn.send(done); err != nil {
		n.transfers.Fail(t.ID, "send done: "+err.Error())
		n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferFailed}})
		return
	}

	n.transfers.Complete(t.ID)
	log.Printf("[node] file %q sent to %s (hash=%s)", t.FileName, t.PeerID[:8], hashHex[:16])
	n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferCompleted}})
}

// Start begins listening for incoming connections and starts discovery.
func (n *Node) Start() error {
	ln, err := net.Listen("tcp", ":0")
	if err != nil {
		return fmt.Errorf("listen: %w", err)
	}
	n.listener = ln
	n.port = ln.Addr().(*net.TCPAddr).Port
	log.Printf("[node] listening on :%d (id=%s)", n.port, n.id)

	go n.acceptLoop()
	go n.pingLoop()

	n.discovery = NewDiscovery(n.id, n.name, n.port, n.onDiscovered)
	if err := n.discovery.Start(n.ctx); err != nil {
		return fmt.Errorf("discovery: %w", err)
	}
	return nil
}

// pingLoop sends periodic pings to all connected peers to keep connections alive.
func (n *Node) pingLoop() {
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-n.ctx.Done():
			return
		case <-ticker.C:
			n.mu.Lock()
			conns := make([]*conn, 0, len(n.connByPeerID))
			for _, c := range n.connByPeerID {
				conns = append(conns, c)
			}
			n.mu.Unlock()
			ping := Message{Type: MsgTypePing, PeerID: n.id, Timestamp: time.Now()}
			for _, c := range conns {
				c.send(ping)
			}
		}
	}
}

// Stop shuts down the node cleanly.
func (n *Node) Stop() {
	n.cancel()
	if n.discovery != nil {
		n.discovery.Stop()
	}
	if n.listener != nil {
		n.listener.Close()
	}
	n.mu.Lock()
	for _, c := range n.connByPeerID {
		c.c.Close()
	}
	n.mu.Unlock()
}

// Send routes a message based on toPeerID:
//   - toPeerID == "" → global broadcast (plaintext MsgTypeText)
//   - toPeerID != "" → encrypted personal message (MsgTypeDirect) to that peer only
func (n *Node) Send(text string, toPeerID string) {
	if toPeerID == "" {
		msg := NewTextMessage(n.id, n.name, text)
		n.emit(Event{Msg: &msg}) // echo own message to UI
		n.broadcast(msg, "")
	} else {
		n.sendDirect(text, toPeerID)
	}
}

// sendDirect encrypts text and unicasts it to the specified peer.
func (n *Node) sendDirect(text, toPeerID string) {
	peer := n.peers.Get(toPeerID)
	if peer == nil {
		log.Printf("[node] sendDirect: unknown peer %s", toPeerID)
		return
	}
	if isZeroKey(peer.SharedKey) {
		log.Printf("[node] sendDirect: no shared key for %s (handshake incomplete)", toPeerID[:8])
		return
	}

	nonce, ciphertext, err := Encrypt(peer.SharedKey, text)
	if err != nil {
		log.Printf("[node] encrypt for %s: %v", toPeerID[:8], err)
		return
	}

	wireMsg := NewDirectMessage(n.id, n.name, toPeerID, ciphertext, nonce)

	// Echo plaintext version to ourselves for display.
	echo := Message{
		ID:        wireMsg.ID,
		Type:      MsgTypeDirect,
		PeerID:    n.id,
		Name:      n.name,
		Content:   text, // plaintext — never leave the local process
		To:        toPeerID,
		Timestamp: wireMsg.Timestamp,
	}
	n.emit(Event{Msg: &echo})

	// Send encrypted wire message.
	n.mu.Lock()
	cn := n.connByPeerID[toPeerID]
	n.mu.Unlock()
	if cn == nil {
		log.Printf("[node] sendDirect: no connection to %s", toPeerID[:8])
		return
	}
	if err := cn.send(wireMsg); err != nil {
		log.Printf("[node] sendDirect write to %s: %v", toPeerID[:8], err)
	}
}

// ─── accept loop ─────────────────────────────────────────────────────────────

func (n *Node) acceptLoop() {
	for {
		c, err := n.listener.Accept()
		if err != nil {
			select {
			case <-n.ctx.Done():
				return
			default:
				log.Printf("[node] accept error: %v", err)
				continue
			}
		}
		go n.handleIncoming(c)
	}
}

// handleIncoming processes a new inbound TCP connection.
// The remote side sends the first Hello; we reply with ours.
func (n *Node) handleIncoming(raw net.Conn) {
	cn := &conn{c: raw, r: bufio.NewReader(raw)}

	raw.SetReadDeadline(time.Now().Add(5 * time.Second))
	hello, err := ReadMsg(cn.r)
	raw.SetReadDeadline(time.Time{})
	if err != nil || hello.Type != MsgTypeHello {
		log.Printf("[node] bad hello from %s: %v", raw.RemoteAddr(), err)
		raw.Close()
		return
	}
	cn.peerID = hello.PeerID

	// Reply with our Hello (carries our public key).
	if err := cn.send(NewHelloMessage(n.id, n.name, n.keyPair.Public[:])); err != nil {
		log.Printf("[node] hello reply to %s: %v", raw.RemoteAddr(), err)
		raw.Close()
		return
	}

	n.completeHandshake(cn, hello.Name, hello.PubKey, raw.RemoteAddr())
	n.readLoop(cn)
}

// dialPeer makes an outbound TCP connection to a discovered peer.
// We send the first Hello; the remote replies with theirs.
func (n *Node) dialPeer(peerID, name string, addr net.IP, port int) {
	n.mu.Lock()
	if _, exists := n.connByPeerID[peerID]; exists {
		n.mu.Unlock()
		return
	}
	n.mu.Unlock()

	target := fmt.Sprintf("%s:%d", addr.String(), port)
	dialer := net.Dialer{Timeout: 5 * time.Second}
	raw, err := dialer.DialContext(n.ctx, "tcp", target)
	if err != nil {
		log.Printf("[node] dial %s: %v", target, err)
		return
	}
	cn := &conn{peerID: peerID, c: raw, r: bufio.NewReader(raw)}

	// Send our Hello first.
	if err := cn.send(NewHelloMessage(n.id, n.name, n.keyPair.Public[:])); err != nil {
		log.Printf("[node] hello to %s: %v", target, err)
		raw.Close()
		return
	}

	// Read their Hello reply.
	raw.SetReadDeadline(time.Now().Add(5 * time.Second))
	reply, err := ReadMsg(cn.r)
	raw.SetReadDeadline(time.Time{})
	if err != nil || reply.Type != MsgTypeHello {
		log.Printf("[node] hello reply from %s: %v", target, err)
		raw.Close()
		return
	}
	cn.peerID = reply.PeerID // use the canonical ID from their Hello

	n.completeHandshake(cn, reply.Name, reply.PubKey, raw.RemoteAddr())
	n.readLoop(cn)
}

// completeHandshake registers the connection, computes the ECDH shared key,
// and emits a PeerJoined event.
func (n *Node) completeHandshake(cn *conn, name string, theirPubKey []byte, addr net.Addr) {
	n.mu.Lock()
	if _, exists := n.connByPeerID[cn.peerID]; exists {
		n.mu.Unlock()
		cn.c.Close()
		return
	}
	n.connByPeerID[cn.peerID] = cn
	n.mu.Unlock()

	info, isNew := n.peers.Upsert(cn.peerID, name, addr, PeerConnected)

	// Store pubkey and derive shared secret.
	if len(theirPubKey) == 32 {
		n.peers.SetPubKey(cn.peerID, theirPubKey)
		shared, err := SharedSecret(n.keyPair.Private, theirPubKey)
		if err != nil {
			log.Printf("[node] ECDH with %s: %v", cn.peerID[:8], err)
		} else {
			n.peers.SetSharedKey(cn.peerID, shared)
			log.Printf("[node] ECDH shared key established with %s (%s)", info.DisplayName, cn.peerID[:8])
		}
	} else {
		log.Printf("[node] peer %s sent no pubkey; direct messages will be unavailable", cn.peerID[:8])
	}

	if isNew {
		n.emit(Event{Peer: &PeerEvent{Peer: info, Kind: PeerJoined}})
	}
}

// ─── read loop ────────────────────────────────────────────────────────────────

func (n *Node) readLoop(cn *conn) {
	defer func() {
		cn.c.Close()
		n.removeConn(cn.peerID, cn)
	}()

	for {
		cn.c.SetReadDeadline(time.Now().Add(60 * time.Second))
		msg, err := ReadMsg(cn.r)
		if err != nil {
			if !errors.Is(err, io.EOF) && n.ctx.Err() == nil {
				log.Printf("[node] read from %s: %v", cn.peerID[:8], err)
			}
			return
		}
		cn.c.SetReadDeadline(time.Time{})

		switch msg.Type {
		case MsgTypeText:
			n.emit(Event{Msg: &msg})

		case MsgTypeDirect:
			if msg.To != n.id {
				// Not addressed to us — shouldn't happen with unicast, but guard anyway.
				continue
			}
			peer := n.peers.Get(msg.PeerID)
			if peer == nil || isZeroKey(peer.SharedKey) {
				log.Printf("[node] direct msg from unknown/no-key peer %s", msg.PeerID[:8])
				continue
			}
			plaintext, err := Decrypt(peer.SharedKey, msg.Nonce, msg.Content)
			if err != nil {
				log.Printf("[node] decrypt from %s: %v", msg.PeerID[:8], err)
				continue
			}
			msg.Content = plaintext // replace ciphertext with plaintext before emitting
			n.emit(Event{Msg: &msg})

		case MsgTypeGroupInvite:
			n.handleGroupInvite(msg, cn)

		case MsgTypeGroupJoin:
			n.handleGroupJoin(msg)

		case MsgTypeGroupLeave:
			n.handleGroupLeave(msg)

		case MsgTypeGroupText:
			n.handleGroupText(msg)

		case MsgTypeFileOffer:
			n.handleFileOffer(msg, cn)

		case MsgTypeFileAccept:
			n.handleFileAccept(msg)

		case MsgTypeFileChunk:
			n.handleFileChunk(msg)

		case MsgTypeFileDone:
			n.handleFileDone(msg)

		case MsgTypePing:
			cn.send(Message{Type: MsgTypePong, PeerID: n.id, Timestamp: time.Now()})

		case MsgTypePong:
			// Keepalive reply — nothing to do; the successful read already
			// reset the deadline.

		case MsgTypeLeave:
			return
		}
	}
}

// ─── group message handlers ───────────────────────────────────────────────────

func (n *Node) handleGroupInvite(msg Message, cn *conn) {
	// Create or update group locally.
	g := n.groups.Get(msg.GroupID)
	if g == nil {
		g = n.groups.Create(msg.GroupID, msg.GroupName, n.id)
	}
	// Populate members from invite.
	for _, mid := range msg.Members {
		n.groups.AddMember(msg.GroupID, mid)
	}
	n.groups.AddMember(msg.GroupID, n.id)

	log.Printf("[node] received invite to group %q from %s", msg.GroupName, msg.Name)

	// Send GroupJoin back to the inviter.
	joinMsg := Message{
		ID:        uuid.NewString(),
		Type:      MsgTypeGroupJoin,
		PeerID:    n.id,
		Name:      n.name,
		GroupID:   msg.GroupID,
		Timestamp: time.Now(),
	}
	cn.send(joinMsg)

	n.emit(Event{Group: &GroupEvent{Group: g, Kind: GroupCreated}})
}

func (n *Node) handleGroupJoin(msg Message) {
	if !n.groups.AddMember(msg.GroupID, msg.PeerID) {
		return
	}
	g := n.groups.Get(msg.GroupID)
	peerName := msg.Name
	if p := n.peers.Get(msg.PeerID); p != nil {
		peerName = p.DisplayName
	}
	log.Printf("[node] %s joined group %q", peerName, g.Name)
	n.emit(Event{Group: &GroupEvent{Group: g, PeerID: msg.PeerID, PeerName: peerName, Kind: GroupMemberJoined}})
}

func (n *Node) handleGroupLeave(msg Message) {
	g := n.groups.Get(msg.GroupID)
	if g == nil {
		return
	}
	n.groups.RemoveMember(msg.GroupID, msg.PeerID)
	peerName := msg.Name
	if p := n.peers.Get(msg.PeerID); p != nil {
		peerName = p.DisplayName
	}
	log.Printf("[node] %s left group %q", peerName, g.Name)
	n.emit(Event{Group: &GroupEvent{Group: g, PeerID: msg.PeerID, PeerName: peerName, Kind: GroupMemberLeft}})
}

func (n *Node) handleGroupText(msg Message) {
	if msg.To != n.id {
		return
	}
	peer := n.peers.Get(msg.PeerID)
	if peer == nil || isZeroKey(peer.SharedKey) {
		log.Printf("[node] group text from unknown/no-key peer %s", msg.PeerID[:8])
		return
	}
	plaintext, err := Decrypt(peer.SharedKey, msg.Nonce, msg.Content)
	if err != nil {
		log.Printf("[node] group decrypt from %s: %v", msg.PeerID[:8], err)
		return
	}
	msg.Content = plaintext
	n.emit(Event{Msg: &msg})
}

// ─── file transfer handlers ─────────────────────────────────────────────────

func (n *Node) handleFileOffer(msg Message, cn *conn) {
	peer := n.peers.Get(msg.PeerID)
	if peer == nil || isZeroKey(peer.SharedKey) {
		log.Printf("[node] file offer from unknown/no-key peer %s", msg.PeerID[:8])
		return
	}

	// Auto-accept: create download directory and destination file.
	if err := os.MkdirAll(FileDownloadDir, 0o755); err != nil {
		log.Printf("[node] mkdir %s: %v", FileDownloadDir, err)
		return
	}

	destPath := filepath.Join(FileDownloadDir, msg.FileName)
	f, err := os.Create(destPath)
	if err != nil {
		log.Printf("[node] create %s: %v", destPath, err)
		return
	}

	t := n.transfers.Start(msg.TransferID, msg.PeerID, msg.FileName, msg.FileSize, false)
	t.file = f
	t.filePath = destPath

	log.Printf("[node] accepted file %q (%d bytes) from %s", msg.FileName, msg.FileSize, msg.Name)
	n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferOffered}})

	// Send FileAccept back.
	accept := Message{
		ID:         uuid.NewString(),
		Type:       MsgTypeFileAccept,
		PeerID:     n.id,
		Name:       n.name,
		To:         msg.PeerID,
		TransferID: msg.TransferID,
		Timestamp:  time.Now(),
	}
	cn.send(accept)
}

func (n *Node) handleFileAccept(msg Message) {
	t := n.transfers.Get(msg.TransferID)
	if t == nil || !t.Sending {
		return
	}
	log.Printf("[node] file %q accepted by %s", t.FileName, msg.Name)
	n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferStarted}})
	// Signal the streaming goroutine to start sending chunks.
	close(t.accepted)
}

func (n *Node) handleFileChunk(msg Message) {
	t := n.transfers.Get(msg.TransferID)
	if t == nil || t.Sending || t.Done {
		return
	}
	peer := n.peers.Get(msg.PeerID)
	if peer == nil || isZeroKey(peer.SharedKey) {
		return
	}

	plaintext, err := DecryptBytes(peer.SharedKey, msg.Nonce, msg.ChunkData)
	if err != nil {
		log.Printf("[node] decrypt chunk %d of %s: %v", msg.ChunkSeq, t.FileName, err)
		n.transfers.Fail(t.ID, "decrypt chunk: "+err.Error())
		n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferFailed}})
		return
	}

	if t.file != nil {
		if _, err := t.file.Write(plaintext); err != nil {
			log.Printf("[node] write chunk %d of %s: %v", msg.ChunkSeq, t.FileName, err)
			n.transfers.Fail(t.ID, "write: "+err.Error())
			n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferFailed}})
			return
		}
	}
	t.hash.Write(plaintext)
	n.transfers.UpdateProgress(t.ID, t.Progress+int64(len(plaintext)))
	t.Progress += int64(len(plaintext))
	n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferProgress}})
}

func (n *Node) handleFileDone(msg Message) {
	t := n.transfers.Get(msg.TransferID)
	if t == nil || t.Sending || t.Done {
		return
	}

	// Verify SHA-256 hash.
	got := hex.EncodeToString(t.hash.Sum(nil))
	if msg.FileHash != "" && got != msg.FileHash {
		errMsg := fmt.Sprintf("hash mismatch: expected %s, got %s", msg.FileHash[:16], got[:16])
		log.Printf("[node] file %q: %s", t.FileName, errMsg)
		n.transfers.Fail(t.ID, errMsg)
		n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferFailed}})
		return
	}

	n.transfers.Complete(t.ID)
	log.Printf("[node] file %q received from %s (hash=%s)", t.FileName, msg.Name, got[:16])
	n.emit(Event{Transfer: &TransferEvent{Transfer: t, Kind: TransferCompleted}})
}

// removeConn cleans up after a closed connection. It only emits PeerLeft if
// the connection being removed is still the one registered in connByPeerID.
// During simultaneous connection races a newer connection may already have
// replaced the old one — in that case we silently discard the stale cleanup.
func (n *Node) removeConn(peerID string, cn *conn) {
	n.mu.Lock()
	registered := n.connByPeerID[peerID]
	if registered != cn {
		// A newer connection has already replaced this one — don't emit PeerLeft.
		n.mu.Unlock()
		return
	}
	delete(n.connByPeerID, peerID)
	n.mu.Unlock()
	n.peers.SetState(peerID, PeerDisconnected)
	if info := n.peers.Get(peerID); info != nil {
		n.emit(Event{Peer: &PeerEvent{Peer: info, Kind: PeerLeft}})
	}
}

// broadcast sends msg to all connected peers except skipID.
func (n *Node) broadcast(msg Message, skipID string) {
	n.mu.Lock()
	conns := make([]*conn, 0, len(n.connByPeerID))
	for id, c := range n.connByPeerID {
		if id != skipID {
			conns = append(conns, c)
		}
	}
	n.mu.Unlock()
	for _, c := range conns {
		if err := c.send(msg); err != nil {
			log.Printf("[node] broadcast to %s: %v", c.peerID[:8], err)
		}
	}
}

func (n *Node) emit(e Event) {
	select {
	case n.eventCh <- e:
	default:
		// Drop if nobody is consuming (e.g. during shutdown).
	}
}

func (n *Node) onDiscovered(peerID, name string, addr net.IP, port int) {
	if peerID == n.id {
		return
	}
	go n.dialPeer(peerID, name, addr, port)
}

// isZeroKey reports whether a [32]byte key is all zeros (i.e. not yet set).
func isZeroKey(key [32]byte) bool {
	for _, b := range key {
		if b != 0 {
			return false
		}
	}
	return true
}
