package proxy

import "sync"

type ProxyManager struct {
	mu      sync.Mutex
	proxies map[string]*PeerProxy
	router  Router
}

func NewProxyManager(r Router) *ProxyManager {
	return &ProxyManager{proxies: make(map[string]*PeerProxy), router: r}
}

func (m *ProxyManager) OpenProxy(peerID, remoteIcePwd string) (int, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if existing, ok := m.proxies[peerID]; ok {
		return existing.LocalAddr().Port, nil
	}

	pp, err := NewPeerProxy(peerID, remoteIcePwd, m.router)
	if err != nil {
		return -1, err
	}
	m.proxies[peerID] = pp
	return pp.LocalAddr().Port, nil
}

func (m *ProxyManager) CloseProxy(peerID string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if pp, ok := m.proxies[peerID]; ok {
		pp.Close()
		delete(m.proxies, peerID)
	}
}

func (m *ProxyManager) Deliver(peerID string, payload []byte) {
	m.mu.Lock()
	pp := m.proxies[peerID]
	m.mu.Unlock()
	if pp != nil {
		pp.DeliverFromMesh(payload)
	}
}
