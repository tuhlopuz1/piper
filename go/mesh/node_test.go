package mesh_test

import (
	"testing"

	"github.com/catsi/piper/mesh"
)

func TestNodeStartStop(t *testing.T) {
	n := mesh.NewNode("test-node")
	if err := n.Start(); err != nil {
		t.Fatal(err)
	}
	id := n.ID()
	if id == "" {
		t.Fatal("node ID must not be empty")
	}
	n.Stop()
}

func TestNodeOpenCloseProxy(t *testing.T) {
	n := mesh.NewNode("proxy-test")
	n.Start()
	defer n.Stop()

	port, err := n.OpenProxy("some-peer", "ice-password-xyz")
	if err != nil {
		t.Fatal(err)
	}
	if port <= 0 {
		t.Fatal("invalid port")
	}
	n.CloseProxy("some-peer")
}
