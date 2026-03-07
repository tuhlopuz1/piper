package healer

import (
	"sync"
	"time"
)

type Recomputer interface {
	Recompute(peerID string)
}

type RerouteEvent struct {
	PeerID string
	Reason string
}

type RerouterImpl struct {
	recomputer Recomputer
	cooldown   time.Duration
	mu         sync.Mutex
	active     map[string]bool
	events     chan RerouteEvent
}

func NewRerouter(r Recomputer, cooldown time.Duration) *RerouterImpl {
	rt := &RerouterImpl{
		recomputer: r,
		cooldown:   cooldown,
		active:     make(map[string]bool),
		events:     make(chan RerouteEvent, 64),
	}
	go rt.loop()
	return rt
}

func (r *RerouterImpl) TriggerReroute(peerID, reason string) {
	r.mu.Lock()
	if r.active[peerID] {
		r.mu.Unlock()
		return
	}
	r.active[peerID] = true
	r.mu.Unlock()
	r.events <- RerouteEvent{PeerID: peerID, Reason: reason}
}

func (r *RerouterImpl) loop() {
	for ev := range r.events {
		r.recomputer.Recompute(ev.PeerID)
		time.Sleep(r.cooldown) // cooldown before next reroute for same peer
		r.mu.Lock()
		delete(r.active, ev.PeerID)
		r.mu.Unlock()
	}
}
