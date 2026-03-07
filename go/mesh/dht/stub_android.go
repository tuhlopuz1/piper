//go:build android

// Package dht — Android stub. The libp2p DHT stack is excluded from Android
// builds because wlynxg/anet (a transitive go-libp2p dependency) uses
// go:linkname net.zoneCache which is rejected by the Android linker.
// All DHT operations are no-ops on Android; the retry queue still works.
package dht

import (
	"context"

	"github.com/catsi/piper/mesh/identity"
	"github.com/catsi/piper/mesh/router"
	"go.etcd.io/bbolt"
)

// OfflineStore is a no-op stub on Android.
type OfflineStore struct{}

// NewOfflineStore returns a stub that satisfies the OfflineStore interface.
func NewOfflineStore(_ context.Context, _ identity.Keys, _ string, _ int, _ *bbolt.DB) (*OfflineStore, error) {
	return &OfflineStore{}, nil
}

func (s *OfflineStore) Store(_ context.Context, _, _ string, _ [32]byte) error { return nil }
func (s *OfflineStore) FetchAndDeliver(_ context.Context, _ func(DeliveredMsg)) error { return nil }
func (s *OfflineStore) Bootstrap(_ context.Context, _ []router.MeshPeer)               {}
func (s *OfflineStore) Close()                                                          {}
func (s *OfflineStore) Diag() map[string]interface{} {
	return map[string]interface{}{"status": "unavailable"}
}
