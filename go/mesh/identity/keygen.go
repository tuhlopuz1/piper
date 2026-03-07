package identity

import (
	"crypto/ed25519"
	"crypto/sha256"
	"io"

	"golang.org/x/crypto/curve25519"
	"golang.org/x/crypto/hkdf"
)

const (
	infoX25519  = "piper-x25519-v1"
	infoEd25519 = "piper-ed25519-v1"
)

// Keys holds the derived identity key material for one node.
type Keys struct {
	X25519Priv [32]byte
	X25519Pub  [32]byte
	Ed25519Priv ed25519.PrivateKey
	Ed25519Pub  ed25519.PublicKey
}

// FromSeed derives X25519 and Ed25519 identity keys from a 32-byte master seed
// using HKDF-SHA256.
func FromSeed(seed [32]byte) (Keys, error) {
	x25519Priv, err := deriveScalar(seed, infoX25519)
	if err != nil {
		return Keys{}, err
	}
	ed25519Seed, err := deriveScalar(seed, infoEd25519)
	if err != nil {
		return Keys{}, err
	}

	var k Keys

	// X25519
	k.X25519Priv = x25519Priv
	curve25519.ScalarBaseMult(&k.X25519Pub, &k.X25519Priv)

	// Ed25519
	edPriv := ed25519.NewKeyFromSeed(ed25519Seed[:])
	k.Ed25519Priv = edPriv
	k.Ed25519Pub = edPriv.Public().(ed25519.PublicKey)

	return k, nil
}

func deriveScalar(seed [32]byte, info string) ([32]byte, error) {
	r := hkdf.New(sha256.New, seed[:], nil, []byte(info))
	var out [32]byte
	if _, err := io.ReadFull(r, out[:]); err != nil {
		return [32]byte{}, err
	}
	return out, nil
}
