package core

import (
	"testing"
)

func TestTransferStartAndGet(t *testing.T) {
	tm := NewTransferManager()
	tr := tm.Start("tid-1", "peer-1", "file.txt", 1024, true)

	if tr == nil {
		t.Fatal("Start returned nil")
	}
	if tr.ID != "tid-1" {
		t.Errorf("ID: got %q, want tid-1", tr.ID)
	}
	if tr.PeerID != "peer-1" {
		t.Errorf("PeerID: got %q, want peer-1", tr.PeerID)
	}
	if tr.FileName != "file.txt" {
		t.Errorf("FileName: got %q, want file.txt", tr.FileName)
	}
	if tr.FileSize != 1024 {
		t.Errorf("FileSize: got %d, want 1024", tr.FileSize)
	}
	if !tr.Sending {
		t.Error("Sending should be true for outgoing transfer")
	}
	if tr.Done {
		t.Error("Done should be false for new transfer")
	}

	got := tm.Get("tid-1")
	if got == nil {
		t.Fatal("Get returned nil for existing transfer")
	}
	if got.ID != "tid-1" {
		t.Errorf("Get ID: got %q, want tid-1", got.ID)
	}
}

func TestTransferGetUnknown(t *testing.T) {
	tm := NewTransferManager()
	got := tm.Get("nonexistent")
	if got != nil {
		t.Errorf("Get unknown transfer should return nil, got %+v", got)
	}
}

func TestTransferSenderHasAcceptedChannel(t *testing.T) {
	tm := NewTransferManager()
	// Sending = true should have accepted channel.
	tr := tm.Start("tid-send", "p1", "f.txt", 100, true)
	if tr.accepted == nil {
		t.Error("sender transfer should have accepted channel")
	}
}

func TestTransferReceiverHasNoAcceptedChannel(t *testing.T) {
	tm := NewTransferManager()
	// Sending = false (receiver) should NOT have accepted channel.
	tr := tm.Start("tid-recv", "p1", "f.txt", 100, false)
	if tr.accepted != nil {
		t.Error("receiver transfer should not have accepted channel")
	}
}

func TestTransferUpdateProgress(t *testing.T) {
	tm := NewTransferManager()
	tm.Start("tid-1", "peer-1", "file.txt", 1024, false)

	tm.UpdateProgress("tid-1", 512)

	got := tm.Get("tid-1")
	if got.Progress != 512 {
		t.Errorf("Progress: got %d, want 512", got.Progress)
	}
}

func TestTransferUpdateProgressUnknown(t *testing.T) {
	tm := NewTransferManager()
	// Should not panic.
	tm.UpdateProgress("nonexistent", 100)
}

func TestTransferComplete(t *testing.T) {
	tm := NewTransferManager()
	tm.Start("tid-1", "peer-1", "file.txt", 1024, false)

	tm.Complete("tid-1")

	got := tm.Get("tid-1")
	if !got.Done {
		t.Error("Done should be true after Complete")
	}
	if got.Progress != got.FileSize {
		t.Errorf("Progress should equal FileSize after Complete: got %d, want %d", got.Progress, got.FileSize)
	}
	if got.Err != "" {
		t.Errorf("Err should be empty after Complete, got %q", got.Err)
	}
}

func TestTransferFail(t *testing.T) {
	tm := NewTransferManager()
	tm.Start("tid-1", "peer-1", "file.txt", 1024, false)

	tm.Fail("tid-1", "connection reset")

	got := tm.Get("tid-1")
	if !got.Done {
		t.Error("Done should be true after Fail")
	}
	if got.Err != "connection reset" {
		t.Errorf("Err: got %q, want connection reset", got.Err)
	}
}

func TestTransferFailUnknown(t *testing.T) {
	tm := NewTransferManager()
	// Should not panic.
	tm.Fail("nonexistent", "error")
}

func TestTransferCompleteUnknown(t *testing.T) {
	tm := NewTransferManager()
	// Should not panic.
	tm.Complete("nonexistent")
}

func TestTransferRemove(t *testing.T) {
	tm := NewTransferManager()
	tm.Start("tid-1", "peer-1", "file.txt", 1024, false)
	tm.Remove("tid-1")

	got := tm.Get("tid-1")
	if got != nil {
		t.Error("Get after Remove should return nil")
	}
}

func TestTransferList(t *testing.T) {
	tm := NewTransferManager()
	tm.Start("tid-1", "peer-1", "a.txt", 100, true)
	tm.Start("tid-2", "peer-2", "b.txt", 200, false)
	tm.Start("tid-3", "peer-3", "c.txt", 300, true)

	list := tm.List()
	if len(list) != 3 {
		t.Errorf("List length: got %d, want 3", len(list))
	}
}

func TestTransferListEmpty(t *testing.T) {
	tm := NewTransferManager()
	list := tm.List()
	if list == nil {
		t.Error("List should return empty slice, not nil")
	}
}

func TestTransferGroupID(t *testing.T) {
	tm := NewTransferManager()
	tr := tm.Start("tid-1", "peer-1", "file.txt", 1024, true)
	tr.GroupID = "grp-abc"

	got := tm.Get("tid-1")
	if got.GroupID != "grp-abc" {
		t.Errorf("GroupID: got %q, want grp-abc", got.GroupID)
	}
}
