package main

// #include <stdlib.h>
// typedef void (*EventCallback)(const char* eventJSON);
// static void callEventCallback(EventCallback cb, const char* json) { cb(json); }
import "C"

import (
	"encoding/json"
	"log"
	"sync"
	"unsafe"

	"github.com/catsi/piper/core"
	"github.com/catsi/piper/mesh/proxy"
)

// ─── Handle registry ─────────────────────────────────────────────────────────
// Each PiperCreateNode call returns an integer handle that the caller uses for
// all subsequent operations. This avoids passing Go pointers across the FFI
// boundary (which is forbidden by cgo rules).

var (
	handleMu   sync.Mutex
	nextHandle C.int = 1
	nodes            = map[C.int]*nodeEntry{}
)

type nodeEntry struct {
	node     *core.Node
	proxyMgr *proxy.ProxyManager
	cb       C.EventCallback
	stopPump chan struct{}
}

// noopRouter satisfies proxy.Router with no-op forwarding until mesh routing is wired.
type noopRouter struct{}

func (noopRouter) Send(peerID string, payload []byte, bufPtr *[]byte) {}

// ─── JSON types for events ───────────────────────────────────────────────────

type ffiEvent struct {
	Type string `json:"type"` // "message", "peer", "group", "transfer"

	// Message fields
	MsgID     string `json:"msg_id,omitempty"`
	MsgType   string `json:"msg_type,omitempty"`
	PeerID    string `json:"peer_id,omitempty"`
	PeerName  string `json:"peer_name,omitempty"`
	Content   string `json:"content,omitempty"`
	To        string `json:"to,omitempty"`
	GroupID   string `json:"group_id,omitempty"`
	GroupName string `json:"group_name,omitempty"`
	Timestamp int64  `json:"ts,omitempty"`

	// Peer event fields
	PeerState string `json:"peer_state,omitempty"` // "joined", "left"

	// Group event fields
	GroupEventKind string   `json:"group_event,omitempty"` // "created","member_joined","member_left","deleted"
	Members        []string `json:"members,omitempty"`

	// Transfer fields
	TransferID    string `json:"transfer_id,omitempty"`
	TransferKind  string `json:"transfer_kind,omitempty"` // "offered","started","progress","completed","failed"
	FileName      string `json:"file_name,omitempty"`
	FileSize      int64  `json:"file_size,omitempty"`
	Sending       bool   `json:"sending,omitempty"`
	Progress      int64  `json:"progress,omitempty"`
	TransferError string `json:"transfer_error,omitempty"`
}

type ffiPeer struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	DisplayName string `json:"display_name"`
	State       string `json:"state"` // "connecting", "connected", "disconnected"
}

type ffiGroup struct {
	ID      string   `json:"id"`
	Name    string   `json:"name"`
	Members []string `json:"members"`
}

// ─── Node lifecycle ──────────────────────────────────────────────────────────

//export PiperCreateNode
func PiperCreateNode(name *C.char, nodeID *C.char) C.int {
	n := core.NewNodeWithID(C.GoString(name), C.GoString(nodeID))
	entry := &nodeEntry{
		node:     n,
		proxyMgr: proxy.NewProxyManager(noopRouter{}),
	}
	handleMu.Lock()
	h := nextHandle
	nextHandle++
	nodes[h] = entry
	handleMu.Unlock()
	return h
}

//export PiperSetNodeName
func PiperSetNodeName(handle C.int, name *C.char) {
	e := getEntry(handle)
	if e == nil {
		return
	}
	e.node.SetName(C.GoString(name))
}

//export PiperStartNode
func PiperStartNode(handle C.int) *C.char {
	e := getEntry(handle)
	if e == nil {
		return C.CString("invalid handle")
	}
	if err := e.node.Start(); err != nil {
		return C.CString(err.Error())
	}
	return nil
}

//export PiperStopNode
func PiperStopNode(handle C.int) {
	e := getEntry(handle)
	if e == nil {
		return
	}
	if e.stopPump != nil {
		close(e.stopPump)
		e.stopPump = nil
	}
	e.node.Stop()
	handleMu.Lock()
	delete(nodes, handle)
	handleMu.Unlock()
}

//export PiperNodeID
func PiperNodeID(handle C.int) *C.char {
	e := getEntry(handle)
	if e == nil {
		return C.CString("")
	}
	return C.CString(e.node.ID())
}

//export PiperNodeName
func PiperNodeName(handle C.int) *C.char {
	e := getEntry(handle)
	if e == nil {
		return C.CString("")
	}
	return C.CString(e.node.Name())
}

// ─── Messaging ───────────────────────────────────────────────────────────────

//export PiperSend
func PiperSend(handle C.int, text, toPeerID *C.char) {
	e := getEntry(handle)
	if e == nil {
		return
	}
	e.node.Send(C.GoString(text), C.GoString(toPeerID))
}

//export PiperSendGroup
func PiperSendGroup(handle C.int, text, groupID *C.char) {
	e := getEntry(handle)
	if e == nil {
		return
	}
	e.node.SendGroup(C.GoString(text), C.GoString(groupID))
}

//export PiperSendFile
func PiperSendFile(handle C.int, peerID, filePath *C.char) *C.char {
	e := getEntry(handle)
	if e == nil {
		return C.CString("invalid handle")
	}
	if err := e.node.SendFile(C.GoString(peerID), C.GoString(filePath)); err != nil {
		return C.CString(err.Error())
	}
	return nil
}

//export PiperSendFileToGroup
func PiperSendFileToGroup(handle C.int, groupID, filePath *C.char) *C.char {
	e := getEntry(handle)
	if e == nil {
		return C.CString("invalid handle")
	}
	_, err := e.node.SendFileToGroup(C.GoString(groupID), C.GoString(filePath))
	if err != nil {
		return C.CString(err.Error())
	}
	return nil
}

// ─── Call signaling ──────────────────────────────────────────────────────────

//export PiperSendCallSignal
func PiperSendCallSignal(handle C.int, toPeerID, signalType, payload *C.char) *C.char {
	e := getEntry(handle)
	if e == nil {
		return C.CString("invalid handle")
	}
	if err := e.node.SendCallSignal(C.GoString(toPeerID), C.GoString(signalType), C.GoString(payload)); err != nil {
		return C.CString(err.Error())
	}
	return nil
}

// ─── Groups ──────────────────────────────────────────────────────────────────

//export PiperCreateGroup
func PiperCreateGroup(handle C.int, name *C.char) *C.char {
	e := getEntry(handle)
	if e == nil {
		return C.CString("")
	}
	g := e.node.CreateGroup(C.GoString(name))
	return C.CString(g.ID)
}

//export PiperInviteToGroup
func PiperInviteToGroup(handle C.int, groupID, peerID *C.char) {
	e := getEntry(handle)
	if e == nil {
		return
	}
	e.node.InviteToGroup(C.GoString(groupID), C.GoString(peerID))
}

//export PiperLeaveGroup
func PiperLeaveGroup(handle C.int, groupID *C.char) {
	e := getEntry(handle)
	if e == nil {
		return
	}
	e.node.LeaveGroup(C.GoString(groupID))
}

// ─── Queries ─────────────────────────────────────────────────────────────────

//export PiperListPeers
func PiperListPeers(handle C.int) *C.char {
	e := getEntry(handle)
	if e == nil {
		return C.CString("[]")
	}
	peers := e.node.Peers()
	out := make([]ffiPeer, len(peers))
	for i, p := range peers {
		out[i] = ffiPeer{
			ID:          p.ID,
			Name:        p.Name,
			DisplayName: p.DisplayName,
			State:       peerStateStr(p.State),
		}
	}
	data, _ := json.Marshal(out)
	return C.CString(string(data))
}

//export PiperListGroups
func PiperListGroups(handle C.int) *C.char {
	e := getEntry(handle)
	if e == nil {
		return C.CString("[]")
	}
	groups := e.node.Groups()
	out := make([]ffiGroup, len(groups))
	for i, g := range groups {
		out[i] = ffiGroup{
			ID:      g.ID,
			Name:    g.Name,
			Members: g.MemberIDs(),
		}
	}
	data, _ := json.Marshal(out)
	return C.CString(string(data))
}

// ─── Events callback ─────────────────────────────────────────────────────────

//export PiperSetEventCallback
func PiperSetEventCallback(handle C.int, cb C.EventCallback) {
	e := getEntry(handle)
	if e == nil {
		return
	}
	// Stop any existing event pump.
	if e.stopPump != nil {
		close(e.stopPump)
	}
	e.cb = cb
	e.stopPump = make(chan struct{})
	go eventPump(e)
}

func eventPump(e *nodeEntry) {
	events := e.node.Events()
	for {
		select {
		case <-e.stopPump:
			return
		case ev, ok := <-events:
			if !ok {
				return
			}
			if e.cb == nil {
				continue
			}
			fev := convertEvent(ev)
			data, err := json.Marshal(fev)
			if err != nil {
				log.Printf("[ffi] marshal event: %v", err)
				continue
			}
			cstr := C.CString(string(data))
			// NOTE: Do NOT free cstr here. The Dart NativeCallable.listener
			// callback runs asynchronously — it returns immediately, and Dart
			// reads the string later on its event loop. Freeing here would be
			// use-after-free. Dart frees via PiperFreeString after copying.
			C.callEventCallback(e.cb, cstr)
		}
	}
}

// ─── Configuration ───────────────────────────────────────────────────────────

//export PiperSetDownloadsDir
func PiperSetDownloadsDir(handle C.int, dir *C.char) {
	e := getEntry(handle)
	if e == nil {
		return
	}
	e.node.SetDownloadsDir(C.GoString(dir))
}

// ─── DHT + BLE bootstrap ─────────────────────────────────────────────────────

// PiperGetPeerTable returns the full DHT peer table as a JSON array of
// {id, name, ip, port} objects. Use this to seed BLE / WiFi Direct payloads
// for cross-subnet mesh bootstrap.
//
//export PiperGetPeerTable
func PiperGetPeerTable(handle C.int) *C.char {
	e := getEntry(handle)
	if e == nil {
		return C.CString("[]")
	}
	records := e.node.PeerTable()
	data, _ := json.Marshal(records)
	return C.CString(string(data))
}

// PiperGetLocalInfo returns our own connection endpoint as a JSON object
// {id, name, ip, port}. Dart/Flutter uses this to build the BLE advertisement
// payload so peers in other subnets can find and TCP-connect to us.
//
//export PiperGetLocalInfo
func PiperGetLocalInfo(handle C.int) *C.char {
	e := getEntry(handle)
	if e == nil {
		return C.CString("{}")
	}
	ep := e.node.LocalEndpoint()
	data, _ := json.Marshal(ep)
	return C.CString(string(data))
}

// PiperInjectPeers accepts a JSON array of {id, name, ip, port} records
// discovered via BLE / WiFi Direct and feeds them into the Go discovery
// pipeline exactly like mDNS/UDP peers.
//
//export PiperInjectPeers
func PiperInjectPeers(handle C.int, recordsJSON *C.char) {
	e := getEntry(handle)
	if e == nil {
		return
	}
	var records []core.PeerRecord
	if err := json.Unmarshal([]byte(C.GoString(recordsJSON)), &records); err != nil {
		log.Printf("[ffi] PiperInjectPeers unmarshal: %v", err)
		return
	}
	e.node.InjectPeers(records)
}

// ─── Mesh proxy ─────────────────────────────────────────────────────────────

// PiperOpenProxy opens a localhost UDP proxy for the given peer and returns
// the port number, or -1 on error. The caller must pass the ICE password
// extracted from the remote SDP so that STUN responses are properly signed.
//
//export PiperOpenProxy
func PiperOpenProxy(handle C.int, peerID, remoteIcePwd *C.char) C.int {
	e := getEntry(handle)
	if e == nil {
		return -1
	}
	port, err := e.proxyMgr.OpenProxy(C.GoString(peerID), C.GoString(remoteIcePwd))
	if err != nil {
		return -1
	}
	return C.int(port)
}

// PiperCloseProxy closes the UDP proxy previously opened for peerID.
//
//export PiperCloseProxy
func PiperCloseProxy(handle C.int, peerID *C.char) {
	e := getEntry(handle)
	if e == nil {
		return
	}
	e.proxyMgr.CloseProxy(C.GoString(peerID))
}

// PiperMeshDiag returns a JSON snapshot of mesh diagnostic info.
// Caller MUST call PiperFreeString() after use.
//
//export PiperMeshDiag
func PiperMeshDiag(handle C.int) *C.char {
	e := getEntry(handle)
	if e == nil {
		return C.CString("{}")
	}
	data, _ := json.Marshal(map[string]string{"status": "ok"})
	return C.CString(string(data))
}

// PiperRescan triggers an immediate discovery broadcast so peers are found
// faster after the user manually requests a refresh in the UI.
//
//export PiperRescan
func PiperRescan(handle C.int) {
	e := getEntry(handle)
	if e == nil {
		return
	}
	e.node.Rescan()
}

// ─── Memory management ──────────────────────────────────────────────────────

//export PiperFreeString
func PiperFreeString(s *C.char) {
	if s != nil {
		C.free(unsafe.Pointer(s))
	}
}

// ─── Internal helpers ────────────────────────────────────────────────────────

func getEntry(handle C.int) *nodeEntry {
	handleMu.Lock()
	defer handleMu.Unlock()
	return nodes[handle]
}

func convertEvent(ev core.Event) ffiEvent {
	var f ffiEvent

	if ev.Msg != nil {
		m := ev.Msg
		// Call signaling messages are routed as "call" events, not "message".
		switch m.Type {
		case core.MsgTypeCallOffer, core.MsgTypeCallAnswer,
			core.MsgTypeCallReject, core.MsgTypeCallEnd, core.MsgTypeCallIce,
			core.MsgTypeCallBusy, core.MsgTypeCallAck:
			f.Type = "call"
			f.MsgType = string(m.Type)
			f.PeerID = m.PeerID
			f.PeerName = m.Name
			f.Content = m.Content // decrypted JSON payload
		default:
			f.Type = "message"
			f.MsgID = m.ID
			f.MsgType = string(m.Type)
			f.PeerID = m.PeerID
			f.PeerName = m.Name
			f.Content = m.Content
			f.To = m.To
			f.GroupID = m.GroupID
			f.Timestamp = m.Timestamp.UnixMilli()
		}
	}

	if ev.Peer != nil {
		f.Type = "peer"
		f.PeerID = ev.Peer.Peer.ID
		f.PeerName = ev.Peer.Peer.DisplayName
		switch ev.Peer.Kind {
		case core.PeerJoined:
			f.PeerState = "joined"
		case core.PeerLeft:
			f.PeerState = "left"
		}
	}

	if ev.Group != nil {
		f.Type = "group"
		f.GroupID = ev.Group.Group.ID
		f.GroupName = ev.Group.Group.Name
		f.PeerID = ev.Group.PeerID
		f.PeerName = ev.Group.PeerName
		f.Members = ev.Group.Group.MemberIDs()
		switch ev.Group.Kind {
		case core.GroupCreated:
			f.GroupEventKind = "created"
		case core.GroupMemberJoined:
			f.GroupEventKind = "member_joined"
		case core.GroupMemberLeft:
			f.GroupEventKind = "member_left"
		case core.GroupDeleted:
			f.GroupEventKind = "deleted"
		}
	}

	if ev.Transfer != nil {
		t := ev.Transfer.Transfer
		f.Type = "transfer"
		f.TransferID = t.ID
		f.PeerID = t.PeerID
		f.GroupID = t.GroupID
		f.FileName = t.FileName
		f.FileSize = t.FileSize
		f.Sending = t.Sending
		f.Progress = t.Progress
		f.TransferError = t.Err
		switch ev.Transfer.Kind {
		case core.TransferOffered:
			f.TransferKind = "offered"
		case core.TransferStarted:
			f.TransferKind = "started"
		case core.TransferProgress:
			f.TransferKind = "progress"
		case core.TransferCompleted:
			f.TransferKind = "completed"
		case core.TransferFailed:
			f.TransferKind = "failed"
		}
	}

	return f
}

func peerStateStr(s core.PeerState) string {
	switch s {
	case core.PeerConnecting:
		return "connecting"
	case core.PeerConnected:
		return "connected"
	case core.PeerDisconnected:
		return "disconnected"
	default:
		return "unknown"
	}
}

func main() {}
