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
	"strings"
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
	IP     string `json:"ip,omitempty"` // sender's preferred LAN IP; receiver uses this instead of raddr.IP
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

// preferredIfaces returns UP non-loopback interfaces that look like physical
// WiFi/Ethernet adapters. It skips virtual/software interfaces (VMware,
// VirtualBox, Hyper-V vEthernet, Docker, TAP/TUN, VPN tunnels) that would
// cause us to broadcast from — or advertise — the wrong IP.
//
// If no physical interface is found we fall back to all valid UP interfaces
// so the app still works on unusual setups.
func preferredIfaces() []net.Interface {
	all, err := net.Interfaces()
	if err != nil {
		return nil
	}

	// Name substrings that identify virtual/software interfaces (case-insensitive).
	skipNames := []string{
		"vmware", "vmnet", "vbox", "virtualbox",
		"vethernet", "veth", "docker", "br-",
		"virbr", "hyperv", "hyper-v",
		"tailscale", "zerotier",
		"tun", "tap", "utun",
		"pptp", "l2tp", "ipsec",
		"isatap", "teredo", "6to4",
	}

	var preferred, fallback []net.Interface
	for _, iface := range all {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		if iface.Flags&net.FlagBroadcast == 0 && iface.Flags&net.FlagMulticast == 0 {
			continue
		}
		if !ifaceHasIPv4(iface) {
			continue
		}
		fallback = append(fallback, iface)
		nameLower := strings.ToLower(iface.Name)
		virtual := false
		for _, skip := range skipNames {
			if strings.Contains(nameLower, skip) {
				virtual = true
				break
			}
		}
		if !virtual {
			preferred = append(preferred, iface)
		}
	}
	if len(preferred) > 0 {
		return preferred
	}
	return fallback
}

func ifaceHasIPv4(iface net.Interface) bool {
	addrs, err := iface.Addrs()
	if err != nil {
		return false
	}
	for _, a := range addrs {
		ipnet, ok := a.(*net.IPNet)
		if ok && ipnet.IP.To4() != nil && !ipnet.IP.IsLoopback() {
			return true
		}
	}
	return false
}

// ownIP returns our IPv4 address on the preferred (physical) network interface.
// It is called each broadcast tick so the advertised IP stays current when
// the machine switches networks.
func ownIP() net.IP {
	for _, iface := range preferredIfaces() {
		addrs, _ := iface.Addrs()
		for _, a := range addrs {
			ipnet, ok := a.(*net.IPNet)
			if ok && ipnet.IP.To4() != nil && !ipnet.IP.IsLoopback() {
				return ipnet.IP.To4()
			}
		}
	}
	return nil
}

// Rescan triggers an immediate UDP broadcast so peers are found faster after
// the user manually requests a refresh. The regular ticker continues as usual.
func (d *Discovery) Rescan() {
	if d.udpConn == nil {
		return
	}
	a := announce{PeerID: d.peerID, Name: d.name, Port: d.port}
	if ip := ownIP(); ip != nil {
		a.IP = ip.String()
	}
	payload, _ := json.Marshal(a)
	d.broadcastPayload(payload)
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
	// Our own payload for unicast replies. Built inline each time a peer
	// contacts us so the IP is always fresh.
	makeSelfPayload := func() []byte {
		a := announce{PeerID: d.peerID, Name: d.name, Port: d.port}
		if ip := ownIP(); ip != nil {
			a.IP = ip.String()
		}
		b, _ := json.Marshal(a)
		return b
	}
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
		// Prefer the IP the sender explicitly advertised (derived from their
		// preferred physical interface) over raddr.IP, which may come from a
		// virtual adapter if the machine has multiple network interfaces.
		ip := raddr.IP
		if a.IP != "" {
			if parsed := net.ParseIP(a.IP); parsed != nil {
				if v4 := parsed.To4(); v4 != nil {
					ip = v4
				}
			}
		}
		d.onFound(a.PeerID, a.Name, ip, a.Port)

		// Send a unicast reply directly to the sender so they can discover
		// us even when their OS firewall blocks inbound broadcast packets.
		// Because the sender previously sent outbound UDP from this address,
		// their firewall treats our reply as a response and lets it through.
		d.udpConn.SetWriteDeadline(time.Now().Add(time.Second))
		d.udpConn.WriteToUDP(makeSelfPayload(), raddr)
	}
}

func (d *Discovery) sendUDP(ctx context.Context) {
	ticker := time.NewTicker(udpBroadcastInterval)
	defer ticker.Stop()

	for {
		// Rebuild each tick: if the machine switches networks the advertised
		// IP updates automatically within one broadcast interval.
		a := announce{PeerID: d.peerID, Name: d.name, Port: d.port}
		if ip := ownIP(); ip != nil {
			a.IP = ip.String()
		}
		payload, _ := json.Marshal(a)
		d.broadcastPayload(payload)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (d *Discovery) broadcastPayload(payload []byte) {
	for _, iface := range preferredIfaces() {
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
			// Subnet broadcast: IP | ~mask  (e.g. 192.168.1.255)
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
