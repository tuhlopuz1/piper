package main

// #include <stdlib.h>
import "C"

// PiperInit attaches persistent storage and loads the identity for an existing
// node handle. Call this once after PiperCreateNode, before PiperStartNode.
// Returns nil on success or a C string error message (caller must free with
// PiperFreeString).
//
//export PiperInit
func PiperInit(handle C.int, storagePath *C.char) *C.char {
	e := getEntry(handle)
	if e == nil {
		return C.CString("invalid handle")
	}
	if err := e.node.InitStorage(C.GoString(storagePath)); err != nil {
		return C.CString(err.Error())
	}
	return nil
}

// PiperPendingCount returns the number of queued (undelivered) messages for
// peerID. Returns 0 if storage was not initialised or peerID has no queue.
//
//export PiperPendingCount
func PiperPendingCount(handle C.int, peerID *C.char) C.int {
	e := getEntry(handle)
	if e == nil {
		return 0
	}
	return C.int(e.node.PendingCount(C.GoString(peerID)))
}
