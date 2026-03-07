package transport_test

import (
	"net"
	"sync"
	"testing"
	"time"

	"github.com/catsi/piper/mesh/transport"
)

func TestWifiDirectLinkQualityPenalty(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	go func() {
		conn, _ := ln.Accept()
		conn.Close()
	}()

	conn, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()

	link := transport.NewWifiDirectLink("a", "b", conn)
	q := link.Quality()
	if q.RTT < 10*time.Millisecond {
		t.Fatalf("expected RTT >= 10ms penalty, got %v", q.RTT)
	}
}

func TestWifiDirectLinkSendReceive(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	received := make(chan []byte, 1)
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		conn, _ := ln.Accept()
		srv := transport.NewWifiDirectLink("server", "client", conn)
		srv.SetOnReceive(func(pkt []byte) {
			cp := make([]byte, len(pkt))
			copy(cp, pkt)
			received <- cp
		})
		srv.Start()
		<-time.After(2 * time.Second)
		srv.Close()
	}()

	conn, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	cli := transport.NewWifiDirectLink("client", "server", conn)
	cli.Start()

	msg := []byte("wifi-direct ping")
	if err := cli.Send(msg); err != nil {
		t.Fatal(err)
	}

	select {
	case got := <-received:
		if string(got) != string(msg) {
			t.Fatalf("want %q got %q", msg, got)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("timeout")
	}

	cli.Close()
	wg.Wait()
}
