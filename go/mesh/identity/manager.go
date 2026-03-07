package identity

import (
	"crypto/rand"
	"fmt"
	"os"
	"path/filepath"
)

const seedFile = "identity.seed"

// Manager holds the node's persistent identity keys derived from a stable seed.
type Manager struct {
	Keys Keys
}

// Load loads (or creates) the identity seed from dir/identity.seed and derives
// all key material. Safe to call concurrently after the first call returns.
func Load(dir string) (*Manager, error) {
	path := filepath.Join(dir, seedFile)

	var seed [32]byte
	data, err := os.ReadFile(path)
	if err != nil {
		if !os.IsNotExist(err) {
			return nil, fmt.Errorf("identity: read seed: %w", err)
		}
		// First run: generate a new random seed and persist it atomically.
		if _, err := rand.Read(seed[:]); err != nil {
			return nil, fmt.Errorf("identity: generate seed: %w", err)
		}
		if err := atomicWrite(path, seed[:]); err != nil {
			return nil, fmt.Errorf("identity: write seed: %w", err)
		}
	} else {
		if len(data) != 32 {
			return nil, fmt.Errorf("identity: corrupt seed file (len=%d)", len(data))
		}
		copy(seed[:], data)
	}

	keys, err := FromSeed(seed)
	if err != nil {
		return nil, fmt.Errorf("identity: derive keys: %w", err)
	}
	return &Manager{Keys: keys}, nil
}

// atomicWrite writes data to path by writing a temp file then renaming.
func atomicWrite(path string, data []byte) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
