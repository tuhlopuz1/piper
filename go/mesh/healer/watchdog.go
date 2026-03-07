package healer

import (
	"sync"
	"time"
)

type LinkState uint8

const (
	LinkHealthy  LinkState = iota
	LinkDegraded
	LinkDead
)

type Rerouter interface {
	TriggerReroute(peerID, reason string)
}

type linkHealth struct {
	state     LinkState
	lastAckAt time.Time
	failCount int
	probeSeq  uint32
}

type Watchdog struct {
	rerouter Rerouter
	tick     time.Duration
	mu       sync.Mutex
	links    map[string]*linkHealth
	stopCh   chan struct{}
}

// silentThreshold: silence > 2 ticks → degraded; 2 more ticks → dead
const degradedAfter = 2
const deadAfter = 2

func NewWatchdog(r Rerouter, tick time.Duration) *Watchdog {
	w := &Watchdog{
		rerouter: r,
		tick:     tick,
		links:    make(map[string]*linkHealth),
		stopCh:   make(chan struct{}),
	}
	go w.loop()
	return w
}

func (w *Watchdog) AddPeer(peerID string) {
	w.mu.Lock()
	w.links[peerID] = &linkHealth{state: LinkHealthy, lastAckAt: time.Now()}
	w.mu.Unlock()
}

func (w *Watchdog) RemovePeer(peerID string) {
	w.mu.Lock()
	delete(w.links, peerID)
	w.mu.Unlock()
}

func (w *Watchdog) OnPacketReceived(peerID string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if h, ok := w.links[peerID]; ok {
		h.lastAckAt = time.Now()
		if h.state == LinkDegraded {
			h.state = LinkHealthy
			h.failCount = 0
		}
	}
}

func (w *Watchdog) OnProbeAck(peerID string, seq uint32) {
	w.mu.Lock()
	defer w.mu.Unlock()
	h, ok := w.links[peerID]
	if !ok {
		return
	}
	if h.probeSeq != seq {
		return // stale/wrong seq — ignore
	}
	h.lastAckAt = time.Now()
	h.state = LinkHealthy
	h.failCount = 0
}

func (w *Watchdog) Stop() { close(w.stopCh) }

func (w *Watchdog) loop() {
	t := time.NewTicker(w.tick)
	defer t.Stop()
	silentTicks := make(map[string]int)

	for {
		select {
		case <-w.stopCh:
			return
		case now := <-t.C:
			w.mu.Lock()
			for id, h := range w.links {
				if now.Sub(h.lastAckAt) > w.tick {
					silentTicks[id]++
				} else {
					silentTicks[id] = 0
				}

				switch h.state {
				case LinkHealthy:
					if silentTicks[id] >= degradedAfter {
						h.state = LinkDegraded
						h.failCount = 0
						h.probeSeq++
					}
				case LinkDegraded:
					h.failCount++
					if h.failCount >= deadAfter {
						h.state = LinkDead
						w.mu.Unlock()
						w.rerouter.TriggerReroute(id, "link_dead")
						w.mu.Lock()
					}
				case LinkDead:
					// wait for gossip recovery
				}
			}
			w.mu.Unlock()
		}
	}
}
