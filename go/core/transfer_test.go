package core

import (
	"sync"
	"testing"
)

func TestTransferManager_Start(t *testing.T) {
	tm := NewTransferManager()
	tr := tm.Start("t1", "peer-1", "file.txt", 1024, true)

	if tr.ID != "t1" {
		t.Fatalf("ID = %q, want %q", tr.ID, "t1")
	}
	if tr.PeerID != "peer-1" {
		t.Fatalf("PeerID = %q, want %q", tr.PeerID, "peer-1")
	}
	if tr.FileName != "file.txt" {
		t.Fatalf("FileName = %q, want %q", tr.FileName, "file.txt")
	}
	if tr.FileSize != 1024 {
		t.Fatalf("FileSize = %d, want %d", tr.FileSize, 1024)
	}
	if !tr.Sending {
		t.Fatal("Sending should be true")
	}
	if tr.Done {
		t.Fatal("Done should be false initially")
	}
	if tr.Progress != 0 {
		t.Fatalf("Progress = %d, want 0", tr.Progress)
	}
	if tr.accepted == nil {
		t.Fatal("accepted channel should be created for sending transfer")
	}
}

func TestTransferManager_Start_Receiving(t *testing.T) {
	tm := NewTransferManager()
	tr := tm.Start("t1", "peer-1", "file.txt", 1024, false)

	if tr.Sending {
		t.Fatal("Sending should be false for receiving transfer")
	}
	if tr.accepted != nil {
		t.Fatal("accepted channel should be nil for receiving transfer")
	}
}

func TestTransferManager_Get(t *testing.T) {
	tm := NewTransferManager()
	tm.Start("t1", "peer-1", "file.txt", 1024, false)

	got := tm.Get("t1")
	if got == nil {
		t.Fatal("Get returned nil for existing transfer")
	}
	if got.FileName != "file.txt" {
		t.Fatalf("FileName = %q, want %q", got.FileName, "file.txt")
	}

	if tm.Get("nonexistent") != nil {
		t.Fatal("Get should return nil for unknown transfer")
	}
}

func TestTransferManager_UpdateProgress(t *testing.T) {
	tm := NewTransferManager()
	tm.Start("t1", "peer-1", "file.txt", 1024, false)

	tm.UpdateProgress("t1", 512)
	got := tm.Get("t1")
	if got.Progress != 512 {
		t.Fatalf("Progress = %d, want 512", got.Progress)
	}

	tm.UpdateProgress("nonexistent", 100)
}

func TestTransferManager_Complete(t *testing.T) {
	tm := NewTransferManager()
	tm.Start("t1", "peer-1", "file.txt", 1024, false)
	tm.UpdateProgress("t1", 500)

	tm.Complete("t1")
	got := tm.Get("t1")
	if !got.Done {
		t.Fatal("Done should be true after Complete")
	}
	if got.Progress != 1024 {
		t.Fatalf("Progress = %d, want %d (FileSize)", got.Progress, 1024)
	}
	if got.Err != "" {
		t.Fatalf("Err = %q, want empty", got.Err)
	}

	tm.Complete("nonexistent")
}

func TestTransferManager_Fail(t *testing.T) {
	tm := NewTransferManager()
	tm.Start("t1", "peer-1", "file.txt", 1024, false)

	tm.Fail("t1", "connection lost")
	got := tm.Get("t1")
	if !got.Done {
		t.Fatal("Done should be true after Fail")
	}
	if got.Err != "connection lost" {
		t.Fatalf("Err = %q, want %q", got.Err, "connection lost")
	}

	tm.Fail("nonexistent", "error")
}

func TestTransferManager_Remove(t *testing.T) {
	tm := NewTransferManager()
	tm.Start("t1", "peer-1", "file.txt", 1024, false)
	tm.Remove("t1")

	if tm.Get("t1") != nil {
		t.Fatal("transfer should be removed")
	}

	tm.Remove("nonexistent")
}

func TestTransferManager_List(t *testing.T) {
	tm := NewTransferManager()
	tm.Start("t1", "p1", "a.txt", 100, true)
	tm.Start("t2", "p2", "b.txt", 200, false)

	list := tm.List()
	if len(list) != 2 {
		t.Fatalf("List len = %d, want 2", len(list))
	}
}

func TestTransferManager_ConcurrentAccess(t *testing.T) {
	tm := NewTransferManager()
	var wg sync.WaitGroup

	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			id := string(rune('A' + i%26))
			tm.Start(id, "peer", "file.txt", 1024, i%2 == 0)
			tm.Get(id)
			tm.UpdateProgress(id, int64(i*10))
			tm.List()
		}(i)
	}
	wg.Wait()
}
