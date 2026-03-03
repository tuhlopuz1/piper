package core

// crypto.go provides end-to-end encryption primitives used for direct (personal) messages.
//
// Key exchange:  X25519 Diffie-Hellman  (golang.org/x/crypto/curve25519)
// Cipher:        ChaCha20-Poly1305 AEAD (golang.org/x/crypto/chacha20poly1305)
//
// Protocol:
//  1. Each node generates an ephemeral X25519 keypair on startup.
//  2. The public key is advertised in the Hello handshake message.
//  3. After both sides exchange Hellos, each derives the same 32-byte shared
//     secret via X25519(myPrivate, theirPublic).
//  4. That shared secret is used directly as the ChaCha20-Poly1305 key.
//  5. Every direct message gets a fresh random 12-byte nonce, sent alongside
//     the base64-encoded ciphertext in the wire message.

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"

	"golang.org/x/crypto/chacha20poly1305"
	"golang.org/x/crypto/curve25519"
)

// KeyPair is an X25519 keypair.
type KeyPair struct {
	Private [32]byte
	Public  [32]byte
}

// GenerateKeyPair creates a new random X25519 keypair.
func GenerateKeyPair() (KeyPair, error) {
	var kp KeyPair
	if _, err := rand.Read(kp.Private[:]); err != nil {
		return kp, fmt.Errorf("rand: %w", err)
	}
	pub, err := curve25519.X25519(kp.Private[:], curve25519.Basepoint)
	if err != nil {
		return kp, fmt.Errorf("X25519 basepoint: %w", err)
	}
	copy(kp.Public[:], pub)
	return kp, nil
}

// SharedSecret computes the X25519 Diffie-Hellman shared secret.
// myPriv is our private key; theirPub is the peer's public key (32 bytes).
func SharedSecret(myPriv [32]byte, theirPub []byte) ([32]byte, error) {
	var result [32]byte
	shared, err := curve25519.X25519(myPriv[:], theirPub)
	if err != nil {
		return result, fmt.Errorf("X25519: %w", err)
	}
	copy(result[:], shared)
	return result, nil
}

// Encrypt encrypts plaintext using ChaCha20-Poly1305 with a fresh random nonce.
// Returns (nonce bytes, base64-encoded ciphertext, error).
func Encrypt(key [32]byte, plaintext string) (nonce []byte, ciphertext string, err error) {
	aead, err := chacha20poly1305.New(key[:])
	if err != nil {
		return nil, "", fmt.Errorf("new aead: %w", err)
	}
	nonce = make([]byte, aead.NonceSize())
	if _, err = rand.Read(nonce); err != nil {
		return nil, "", fmt.Errorf("rand nonce: %w", err)
	}
	ct := aead.Seal(nil, nonce, []byte(plaintext), nil)
	return nonce, base64.StdEncoding.EncodeToString(ct), nil
}

// Decrypt decrypts a ChaCha20-Poly1305 encrypted message.
// ciphertext is the base64-encoded value returned by Encrypt.
func Decrypt(key [32]byte, nonce []byte, ciphertext string) (string, error) {
	aead, err := chacha20poly1305.New(key[:])
	if err != nil {
		return "", fmt.Errorf("new aead: %w", err)
	}
	ct, err := base64.StdEncoding.DecodeString(ciphertext)
	if err != nil {
		return "", fmt.Errorf("base64 decode: %w", err)
	}
	pt, err := aead.Open(nil, nonce, ct, nil)
	if err != nil {
		return "", fmt.Errorf("open: %w", err)
	}
	return string(pt), nil
}

// EncryptBytes encrypts raw bytes with ChaCha20-Poly1305.
// Unlike Encrypt, no base64 wrapping is applied — returns raw ciphertext.
func EncryptBytes(key [32]byte, plaintext []byte) (nonce, ciphertext []byte, err error) {
	aead, err := chacha20poly1305.New(key[:])
	if err != nil {
		return nil, nil, fmt.Errorf("new aead: %w", err)
	}
	nonce = make([]byte, aead.NonceSize())
	if _, err = rand.Read(nonce); err != nil {
		return nil, nil, fmt.Errorf("rand nonce: %w", err)
	}
	ciphertext = aead.Seal(nil, nonce, plaintext, nil)
	return nonce, ciphertext, nil
}

// DecryptBytes decrypts raw ciphertext bytes encrypted by EncryptBytes.
func DecryptBytes(key [32]byte, nonce, ciphertext []byte) ([]byte, error) {
	aead, err := chacha20poly1305.New(key[:])
	if err != nil {
		return nil, fmt.Errorf("new aead: %w", err)
	}
	pt, err := aead.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return nil, fmt.Errorf("open: %w", err)
	}
	return pt, nil
}
