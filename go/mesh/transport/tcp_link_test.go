package transport_test

import (
	"net"
	"sync"
	"testing"
	"time"

	"github.com/catsi/piper/mesh/transport"
)

func TestTCPLinkSendReceive(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	var wg sync.WaitGroup
	received := make(chan []byte, 1)

	// Server side
	wg.Add(1)
	go func() {
		defer wg.Done()
		conn, _ := ln.Accept()
		serverLink := transport.NewTCPLink("server", "client", conn)
		serverLink.SetOnReceive(func(pkt []byte) {
			cp := make([]byte, len(pkt))
			copy(cp, pkt)
			received <- cp
		})
		serverLink.Start()
		<-time.After(2 * time.Second)
		serverLink.Close()
	}()

	// Client side
	conn, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	clientLink := transport.NewTCPLink("client", "server", conn)
	clientLink.Start()

	msg := []byte("ping from client")
	if err := clientLink.Send(msg); err != nil {
		t.Fatal(err)
	}

	select {
	case got := <-received:
		if string(got) != string(msg) {
			t.Fatalf("want %q got %q", msg, got)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("timeout waiting for message")
	}

	clientLink.Close()
	wg.Wait()
}
