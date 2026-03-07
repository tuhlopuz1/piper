package core

import (
	"bytes"
	"testing"
)

func TestGenerateKeyPair(t *testing.T) {
	kp1, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("GenerateKeyPair: %v", err)
	}
	kp2, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("GenerateKeyPair second: %v", err)
	}

	if kp1.Private == kp2.Private {
		t.Fatal("two keypairs have identical private keys")
	}
	if kp1.Public == kp2.Public {
		t.Fatal("two keypairs have identical public keys")
	}

	var zero [32]byte
	if kp1.Public == zero {
		t.Fatal("public key is all zeros")
	}
}

func TestSharedSecret_Symmetric(t *testing.T) {
	alice, _ := GenerateKeyPair()
	bob, _ := GenerateKeyPair()

	secretAB, err := SharedSecret(alice.Private, bob.Public[:])
	if err != nil {
		t.Fatalf("SharedSecret A->B: %v", err)
	}
	secretBA, err := SharedSecret(bob.Private, alice.Public[:])
	if err != nil {
		t.Fatalf("SharedSecret B->A: %v", err)
	}

	if secretAB != secretBA {
		t.Fatal("shared secrets do not match")
	}

	var zero [32]byte
	if secretAB == zero {
		t.Fatal("shared secret is all zeros")
	}
}

func TestSharedSecret_DifferentPeers(t *testing.T) {
	alice, _ := GenerateKeyPair()
	bob, _ := GenerateKeyPair()
	charlie, _ := GenerateKeyPair()

	secretAB, _ := SharedSecret(alice.Private, bob.Public[:])
	secretAC, _ := SharedSecret(alice.Private, charlie.Public[:])

	if secretAB == secretAC {
		t.Fatal("shared secrets with different peers should differ")
	}
}

func TestEncryptDecrypt_String(t *testing.T) {
	alice, _ := GenerateKeyPair()
	bob, _ := GenerateKeyPair()
	key, _ := SharedSecret(alice.Private, bob.Public[:])

	plaintext := "Hello, Piper!"
	nonce, ciphertext, err := Encrypt(key, plaintext)
	if err != nil {
		t.Fatalf("Encrypt: %v", err)
	}

	if len(nonce) != 12 {
		t.Fatalf("nonce length = %d, want 12", len(nonce))
	}
	if ciphertext == plaintext {
		t.Fatal("ciphertext equals plaintext")
	}

	got, err := Decrypt(key, nonce, ciphertext)
	if err != nil {
		t.Fatalf("Decrypt: %v", err)
	}
	if got != plaintext {
		t.Fatalf("Decrypt = %q, want %q", got, plaintext)
	}
}

func TestDecrypt_WrongKey(t *testing.T) {
	alice, _ := GenerateKeyPair()
	bob, _ := GenerateKeyPair()
	charlie, _ := GenerateKeyPair()

	keyAB, _ := SharedSecret(alice.Private, bob.Public[:])
	keyAC, _ := SharedSecret(alice.Private, charlie.Public[:])

	nonce, ciphertext, _ := Encrypt(keyAB, "secret message")

	_, err := Decrypt(keyAC, nonce, ciphertext)
	if err == nil {
		t.Fatal("Decrypt with wrong key should fail")
	}
}

func TestDecrypt_TamperedNonce(t *testing.T) {
	key := [32]byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
		17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32}

	nonce, ciphertext, _ := Encrypt(key, "test")
	nonce[0] ^= 0xFF

	_, err := Decrypt(key, nonce, ciphertext)
	if err == nil {
		t.Fatal("Decrypt with tampered nonce should fail")
	}
}

func TestEncryptDecryptBytes(t *testing.T) {
	key := [32]byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
		17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32}

	plaintext := []byte("binary data \x00\x01\x02")
	nonce, ciphertext, err := EncryptBytes(key, plaintext)
	if err != nil {
		t.Fatalf("EncryptBytes: %v", err)
	}

	got, err := DecryptBytes(key, nonce, ciphertext)
	if err != nil {
		t.Fatalf("DecryptBytes: %v", err)
	}
	if !bytes.Equal(got, plaintext) {
		t.Fatalf("DecryptBytes = %v, want %v", got, plaintext)
	}
}

func TestEncryptBytes_UniqueNonces(t *testing.T) {
	key := [32]byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
		17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32}

	nonce1, _, _ := EncryptBytes(key, []byte("data"))
	nonce2, _, _ := EncryptBytes(key, []byte("data"))

	if bytes.Equal(nonce1, nonce2) {
		t.Fatal("two encryptions produced identical nonces")
	}
}

func TestEncryptDecrypt_EmptyString(t *testing.T) {
	key := [32]byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
		17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32}

	nonce, ciphertext, err := Encrypt(key, "")
	if err != nil {
		t.Fatalf("Encrypt empty: %v", err)
	}
	got, err := Decrypt(key, nonce, ciphertext)
	if err != nil {
		t.Fatalf("Decrypt empty: %v", err)
	}
	if got != "" {
		t.Fatalf("expected empty string, got %q", got)
	}
}

func TestEncryptDecrypt_LargePayload(t *testing.T) {
	key := [32]byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
		17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32}

	plaintext := make([]byte, 1024*1024)
	for i := range plaintext {
		plaintext[i] = byte(i % 256)
	}

	nonce, ciphertext, err := EncryptBytes(key, plaintext)
	if err != nil {
		t.Fatalf("EncryptBytes large: %v", err)
	}
	got, err := DecryptBytes(key, nonce, ciphertext)
	if err != nil {
		t.Fatalf("DecryptBytes large: %v", err)
	}
	if !bytes.Equal(got, plaintext) {
		t.Fatal("large payload round-trip failed")
	}
}
