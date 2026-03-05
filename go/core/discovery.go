package core

// Discovery uses two complementary mechanisms so that peers are found
// regardless of router configuration:
//
//  1. mDNS/DNS-SD (zeroconf) — works on most LANs with no router config.
//  2. LAN UDP broadcast — fallback for networks that block multicast.
//
// Both mechanisms advertise the same tuple: (peerID, displayName, tcpPort).
// When a new address is found the Node's onDiscovered callback is invoked.

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"time"

	"github.com/grandcat/zeroconf"
)

const (
	mdnsService     = "_piper._tcp"
	mdnsDomain      = "local."
	udpBroadcastPort = 47821 // arbitrary; fixed across the app
	udpBroadcastInterval = 5 * time.Second
)

// announce is the JSON payload sent via UDP broadcast.
type announce struct {
	PeerID string `json:"id"`
	Name   string `json:"name"`
	Port   int    `json:"port"`
}

// Discovery handles both mDNS and UDP-broadcast peer discovery.
type Discovery struct {
	peerID  string
	name    string
	port    int
	onFound func(peerID, name string, addr net.IP, port int)

	mdnsServer   *zeroconf.Server
	udpConn      *net.UDPConn
	cancelBroadcast context.CancelFunc
}

// NewDiscovery creates a Discovery instance.
// onFound is called (possibly concurrently) whenever a new address is found.
func NewDiscovery(peerID, name string, port int, onFound func(string, string, net.IP, int)) *Discovery {
	return &Discovery{
		peerID:  peerID,
		name:    name,
		port:    port,
		onFound: onFound,
	}
}

// Start launches both mDNS and UDP-broadcast discovery in the background.
// It is non-blocking; call Stop to shut everything down.
func (d *Discovery) Start(ctx context.Context) error {
	if err := d.startMDNS(ctx); err != nil {
		// mDNS is optional — log but don't abort
		log.Printf("[discovery] mDNS unavailable: %v", err)
	}
	if err := d.startUDP(ctx); err != nil {
		return fmt.Errorf("UDP broadcast: %w", err)
	}
	return nil
}

// Stop shuts down both mechanisms.
func (d *Discovery) Stop() {
	if d.cancelBroadcast != nil {
		d.cancelBroadcast()
	}
	if d.mdnsServer != nil {
		d.mdnsServer.Shutdown()
	}
	if d.udpConn != nil {
		d.udpConn.Close()
	}
}

// ─── mDNS ────────────────────────────────────────────────────────────────────

func (d *Discovery) startMDNS(ctx context.Context) error {
	// Register ourselves.
	// TXT records carry peerID and name so listeners can extract them
	// without making a separate TCP connection.
	txt := []string{
		"id=" + d.peerID,
		"name=" + d.name,
	}
	server, err := zeroconf.Register(d.name, mdnsService, mdnsDomain, d.port, txt, nil)
	if err != nil {
		return err
	}
	d.mdnsServer = server

	// Browse for other instances.
	go d.browseMDNS(ctx)
	return nil
}

func (d *Discovery) browseMDNS(ctx context.Context) {
	entries := make(chan *zeroconf.ServiceEntry, 16)
	go func() {
		for entry := range entries {
			id, name := "", entry.HostName
			for _, txt := range entry.Text {
				if len(txt) > 3 && txt[:3] == "id=" {
					id = txt[3:]
				}
				if len(txt) > 5 && txt[:5] == "name=" {
					name = txt[5:]
				}
			}
			if id == "" || id == d.peerID {
				continue // no id in TXT or ourselves
			}
			ip := firstIP(entry.AddrIPv4, entry.AddrIPv6)
			if ip == nil {
				continue
			}
			d.onFound(id, name, ip, entry.Port)
		}
	}()

	resolver, err := zeroconf.NewResolver(nil)
	if err != nil {
		log.Printf("[discovery] mDNS resolver: %v", err)
		return
	}
	for {
		if err := resolver.Browse(ctx, mdnsService, mdnsDomain, entries); err != nil {
			log.Printf("[discovery] mDNS browse: %v", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(10 * time.Second):
			// retry
		}
	}
}

func firstIP(v4, v6 []net.IP) net.IP {
	for _, ip := range v4 {
		if !ip.IsLoopback() {
			return ip
		}
	}
	for _, ip := range v6 {
		if !ip.IsLoopback() {
			return ip
		}
	}
	return nil
}

// ─── UDP broadcast ───────────────────────────────────────────────────────────

func (d *Discovery) startUDP(ctx context.Context) error {
	// Use ListenConfig with SO_REUSEADDR so multiple instances can share the port.
	lc := net.ListenConfig{}
	pc, err := lc.ListenPacket(ctx, "udp4", fmt.Sprintf(":%d", udpBroadcastPort))
	if err != nil {
		// Port already in use is tolerable — another instance on same host.
		pc, err = lc.ListenPacket(ctx, "udp4", ":0")
		if err != nil {
			return err
		}
	}
	conn := pc.(*net.UDPConn)
	d.udpConn = conn

	broadcastCtx, cancel := context.WithCancel(ctx)
	d.cancelBroadcast = cancel

	go d.listenUDP(broadcastCtx)
	go d.sendUDP(broadcastCtx)
	return nil
}

func (d *Discovery) listenUDP(ctx context.Context) {
	buf := make([]byte, 512)
	// Our own payload for unicast replies.
	selfPayload, _ := json.Marshal(announce{PeerID: d.peerID, Name: d.name, Port: d.port})
	for {
		d.udpConn.SetReadDeadline(time.Now().Add(2 * time.Second))
		n, raddr, err := d.udpConn.ReadFromUDP(buf)
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
				continue
			}
		}
		var a announce
		if err := json.Unmarshal(buf[:n], &a); err != nil {
			continue
		}
		if a.PeerID == d.peerID {
			continue // ourselves
		}
		d.onFound(a.PeerID, a.Name, raddr.IP, a.Port)

		// Send a unicast reply directly to the sender so they can discover
		// us even when their OS firewall blocks inbound broadcast packets.
		// Because the sender previously sent outbound UDP from this address,
		// their firewall treats our reply as a response and lets it through.
		d.udpConn.SetWriteDeadline(time.Now().Add(time.Second))
		d.udpConn.WriteToUDP(selfPayload, raddr)
	}
}

func (d *Discovery) sendUDP(ctx context.Context) {
	ticker := time.NewTicker(udpBroadcastInterval)
	defer ticker.Stop()

	payload, _ := json.Marshal(announce{PeerID: d.peerID, Name: d.name, Port: d.port})

	for {
		d.broadcastPayload(payload)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (d *Discovery) broadcastPayload(payload []byte) {
	// Always try the global broadcast address — works on most Android devices
	// even when per-subnet broadcast is filtered.
	globalDst := &net.UDPAddr{IP: net.IPv4bcast, Port: udpBroadcastPort}
	d.udpConn.SetWriteDeadline(time.Now().Add(time.Second))
	d.udpConn.WriteToUDP(payload, globalDst)

	ifaces, err := net.Interfaces()
	if err != nil {
		return
	}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 {
			continue
		}
		// Accept interfaces with either Broadcast or Multicast flag —
		// some Android WiFi drivers only report FlagMulticast on wlan0.
		if iface.Flags&net.FlagBroadcast == 0 && iface.Flags&net.FlagMulticast == 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			ipnet, ok := a.(*net.IPNet)
			if !ok {
				continue
			}
			ip4 := ipnet.IP.To4()
			if ip4 == nil || ip4.IsLoopback() {
				continue
			}
			// Compute subnet broadcast address: IP | ~mask
			broadcast := make(net.IP, 4)
			for i := range broadcast {
				broadcast[i] = ip4[i] | ^ipnet.Mask[i]
			}
			dst := &net.UDPAddr{IP: broadcast, Port: udpBroadcastPort}
			d.udpConn.SetWriteDeadline(time.Now().Add(time.Second))
			d.udpConn.WriteToUDP(payload, dst)
		}
	}
}
