package store

import (
	"go.etcd.io/bbolt"
)

const (
	BucketRetry   = "retry"
	BucketDHTSeen = "dht_seen"
)

// Open opens (or creates) the bbolt database at path and initialises all
// required buckets. The caller is responsible for closing the returned DB.
func Open(path string) (*bbolt.DB, error) {
	db, err := bbolt.Open(path, 0600, nil)
	if err != nil {
		return nil, err
	}
	if err := db.Update(func(tx *bbolt.Tx) error {
		for _, name := range []string{BucketRetry, BucketDHTSeen} {
			if _, err := tx.CreateBucketIfNotExists([]byte(name)); err != nil {
				return err
			}
		}
		return nil
	}); err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}
