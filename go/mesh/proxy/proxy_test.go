package proxy_test

import (
	"testing"

	"github.com/catsi/piper/mesh/proxy"
)

func TestProxyManagerOpenClose(t *testing.T) {
	mr := &mockRouter{}
	mgr := proxy.NewProxyManager(mr)

	port, err := mgr.OpenProxy("peer-a", "password-a")
	if err != nil {
		t.Fatal(err)
	}
	if port <= 0 || port > 65535 {
		t.Fatalf("invalid port %d", port)
	}

	// Opening same peer twice returns same port
	port2, err := mgr.OpenProxy("peer-a", "password-a")
	if err != nil {
		t.Fatal(err)
	}
	if port2 != port {
		t.Fatalf("want same port, got %d vs %d", port, port2)
	}

	mgr.CloseProxy("peer-a")

	// After close, new OpenProxy gets a new port
	port3, err := mgr.OpenProxy("peer-a", "password-a")
	if err != nil {
		t.Fatal(err)
	}
	if port3 == port {
		t.Fatal("after close, expected new port")
	}
	mgr.CloseProxy("peer-a")
}
