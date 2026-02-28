package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"piper/discovery"
	"piper/ipc"
	"piper/transport"

	"github.com/google/uuid"
)

func main() {
	name := flag.String("name", defaultName(), "Display name shown to other peers")
	flag.Parse()

	id := uuid.NewString()
	log.Printf("[piper] id=%s name=%s", id, *name)

	// Free TCP port for peer-to-peer connections
	tcpPort, err := freePort()
	if err != nil {
		log.Fatalf("[piper] cannot get free port: %v", err)
	}

	// IPC hub: manages WebSocket clients and HTTP API for Flutter
	hub := ipc.NewHub()
	go hub.Run()

	// Peer manager: handles TCP connections to/from other Piper instances
	pm := transport.NewManager(id, *name, hub)

	// Start TCP server for incoming peer connections
	go func() {
		if err := pm.ListenAndServe(tcpPort); err != nil {
			log.Printf("[piper] TCP server stopped: %v", err)
		}
	}()

	// Start mDNS discovery: advertise ourselves and find peers
	disc, err := discovery.New(
		id, *name, tcpPort,
		func(info discovery.PeerInfo) { pm.Connect(info) },
	)
	if err != nil {
		log.Fatalf("[piper] mDNS init error: %v", err)
	}
	go disc.Run()

	// Start IPC HTTP/WebSocket server for Flutter
	ipcPort, err := hub.ListenAndServe(pm)
	if err != nil {
		log.Fatalf("[piper] IPC server error: %v", err)
	}

	// Tell Flutter which port to connect to (read from stdout)
	fmt.Printf("PORT=%d\n", ipcPort)
	os.Stdout.Sync()

	// Wait for shutdown signal
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	<-sig

	log.Println("[piper] shutting down...")
	disc.Shutdown()
	pm.Shutdown()
}

func defaultName() string {
	if h, err := os.Hostname(); err == nil {
		return h
	}
	return "piper-device"
}

func freePort() (int, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	port := l.Addr().(*net.TCPAddr).Port
	_ = l.Close()
	return port, nil
}
