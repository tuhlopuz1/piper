package core

import (
	"crypto/sha256"
	"hash"
	"os"
	"sync"
)

const (
	// ChunkSize is the raw chunk size before encryption (512 KB).
	ChunkSize = 512 * 1024

	// FileDownloadDir is the default directory for received files.
	FileDownloadDir = "piper-files"
)

// TransferEventKind categorises file transfer lifecycle events.
type TransferEventKind int

const (
	TransferOffered   TransferEventKind = iota // incoming offer received
	TransferStarted                            // transfer accepted, chunks flowing
	TransferProgress                           // progress update
	TransferCompleted                          // successfully finished
	TransferFailed                             // error occurred
)

// Transfer tracks the state of an ongoing file transfer.
type Transfer struct {
	ID             string
	PeerID         string
	GroupID        string // non-empty when this transfer is part of a group file send
	FileName       string
	FileSize       int64
	Sending        bool  // true = outgoing, false = incoming
	Progress       int64 // bytes transferred so far
	Done           bool
	Err            string // non-empty if failed
	AttachmentID   string
	AttachmentKind string
	MimeType       string
	VoiceDuration  int

	// Internal — not exposed to TUI.
	file       *os.File      // open file handle (send: read, recv: write)
	hash       hash.Hash     // running SHA-256
	filePath   string        // full path (send: source, recv: destination)
	accepted   chan struct{}  // closed when FileAccept is received (sender side)
	acceptOnce sync.Once     // guards close(accepted) against double-close panic
}

type TransferOptions struct {
	GroupID        string
	AttachmentID   string
	AttachmentKind string
	MimeType       string
	VoiceDuration  int
}

// TransferEvent is emitted on the Node event channel for transfer lifecycle changes.
type TransferEvent struct {
	Transfer *Transfer
	Kind     TransferEventKind
}

// TransferManager provides thread-safe management of active transfers.
type TransferManager struct {
	mu        sync.RWMutex
	transfers map[string]*Transfer
}

// NewTransferManager creates an empty TransferManager.
func NewTransferManager() *TransferManager {
	return &TransferManager{transfers: make(map[string]*Transfer)}
}

// Start registers a new transfer and returns it.
func (tm *TransferManager) Start(id, peerID, fileName string, fileSize int64, sending bool, opts TransferOptions) *Transfer {
	tm.mu.Lock()
	defer tm.mu.Unlock()
	t := &Transfer{
		ID:             id,
		PeerID:         peerID,
		GroupID:        opts.GroupID,
		FileName:       fileName,
		FileSize:       fileSize,
		Sending:        sending,
		AttachmentID:   opts.AttachmentID,
		AttachmentKind: opts.AttachmentKind,
		MimeType:       opts.MimeType,
		VoiceDuration:  opts.VoiceDuration,
		hash:           sha256.New(),
	}
	if sending {
		t.accepted = make(chan struct{})
	}
	tm.transfers[id] = t
	return t
}

// Get returns the transfer by ID, or nil.
func (tm *TransferManager) Get(id string) *Transfer {
	tm.mu.RLock()
	defer tm.mu.RUnlock()
	return tm.transfers[id]
}

// UpdateProgress atomically sets the progress value.
func (tm *TransferManager) UpdateProgress(id string, progress int64) {
	tm.mu.Lock()
	defer tm.mu.Unlock()
	if t, ok := tm.transfers[id]; ok {
		t.Progress = progress
	}
}

// Complete marks a transfer as done.
func (tm *TransferManager) Complete(id string) {
	tm.mu.Lock()
	defer tm.mu.Unlock()
	if t, ok := tm.transfers[id]; ok {
		t.Done = true
		t.Progress = t.FileSize
		if t.file != nil {
			t.file.Close()
			t.file = nil
		}
	}
}

// Fail marks a transfer as failed with an error message.
func (tm *TransferManager) Fail(id, errMsg string) {
	tm.mu.Lock()
	defer tm.mu.Unlock()
	if t, ok := tm.transfers[id]; ok {
		t.Done = true
		t.Err = errMsg
		if t.file != nil {
			t.file.Close()
			t.file = nil
		}
	}
}

// Remove deletes a transfer by ID.
func (tm *TransferManager) Remove(id string) {
	tm.mu.Lock()
	defer tm.mu.Unlock()
	if t, ok := tm.transfers[id]; ok {
		if t.file != nil {
			t.file.Close()
		}
		delete(tm.transfers, id)
	}
}

// List returns a snapshot of all transfers.
func (tm *TransferManager) List() []*Transfer {
	tm.mu.RLock()
	defer tm.mu.RUnlock()
	out := make([]*Transfer, 0, len(tm.transfers))
	for _, t := range tm.transfers {
		out = append(out, t)
	}
	return out
}
