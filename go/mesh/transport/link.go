package transport

import "time"

type LinkQuality struct {
	RTT       time.Duration
	LossRatio float32 // 0.0–1.0, EMA-smoothed
	Bandwidth int64   // bytes/sec
}

type Link interface {
	ID() string
	PeerID() string
	Send(pkt []byte) error
	SetOnReceive(handler func(pkt []byte))
	Quality() LinkQuality
	Close()
}
