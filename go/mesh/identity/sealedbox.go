package identity

import (
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"fmt"

	"golang.org/x/crypto/chacha20poly1305"
	"golang.org/x/crypto/curve25519"
)

// Seal encrypts plaintext for recipientPub using an ephemeral X25519 keypair.
// Wire format: ek_pub(32) || chacha20poly1305_ciphertext
func Seal(recipientPub [32]byte, plaintext []byte) ([]byte, error) {
	// Generate ephemeral keypair
	var ekPriv [32]byte
	if _, err := rand.Read(ekPriv[:]); err != nil {
		return nil, fmt.Errorf("sealedbox: rand: %w", err)
	}
	var ekPub [32]byte
	curve25519.ScalarBaseMult(&ekPub, &ekPriv)

	// Shared secret
	shared, err := curve25519.X25519(ekPriv[:], recipientPub[:])
	if err != nil {
		return nil, fmt.Errorf("sealedbox: X25519: %w", err)
	}

	// Nonce = SHA256(ek_pub || recipient_pub)[:12]
	nonce := deriveNonce(ekPub, recipientPub)

	aead, err := chacha20poly1305.New(shared)
	if err != nil {
		return nil, fmt.Errorf("sealedbox: aead: %w", err)
	}

	ct := aead.Seal(nil, nonce, plaintext, nil)
	out := make([]byte, 0, 32+len(ct))
	out = append(out, ekPub[:]...)
	out = append(out, ct...)
	return out, nil
}

// Open decrypts a sealedbox produced by Seal.
func Open(myPriv, myPub [32]byte, sealedBox []byte) ([]byte, error) {
	if len(sealedBox) < 32 {
		return nil, errors.New("sealedbox: too short")
	}
	var ekPub [32]byte
	copy(ekPub[:], sealedBox[:32])

	shared, err := curve25519.X25519(myPriv[:], ekPub[:])
	if err != nil {
		return nil, fmt.Errorf("sealedbox: X25519: %w", err)
	}

	nonce := deriveNonce(ekPub, myPub)

	aead, err := chacha20poly1305.New(shared)
	if err != nil {
		return nil, fmt.Errorf("sealedbox: aead: %w", err)
	}

	plain, err := aead.Open(nil, nonce, sealedBox[32:], nil)
	if err != nil {
		return nil, fmt.Errorf("sealedbox: open: %w", err)
	}
	return plain, nil
}

func deriveNonce(ekPub, recipientPub [32]byte) []byte {
	h := sha256.New()
	h.Write(ekPub[:])
	h.Write(recipientPub[:])
	return h.Sum(nil)[:12]
}
