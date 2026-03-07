package transport

import (
	"net"
	"time"
)

const wifiDirectRTTPenalty = 10 * time.Millisecond

// WifiDirectLink wraps TCPLink with a fixed RTT penalty to account for
// WiFi P2P overhead. All data methods delegate to the embedded TCPLink.
type WifiDirectLink struct {
	*TCPLink
}

func NewWifiDirectLink(id, peerID string, conn net.Conn) *WifiDirectLink {
	return &WifiDirectLink{TCPLink: NewTCPLink(id, peerID, conn)}
}

// Quality returns the underlying TCPLink quality with a minimum RTT of
// wifiDirectRTTPenalty so the router accounts for WiFi P2P overhead.
func (w *WifiDirectLink) Quality() LinkQuality {
	q := w.TCPLink.Quality()
	if q.RTT < wifiDirectRTTPenalty {
		q.RTT = wifiDirectRTTPenalty
	}
	return q
}
