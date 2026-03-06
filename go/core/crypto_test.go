package core

import (
	"bytes"
	"testing"
)

func TestGenerateKeyPairIsRandom(t *testing.T) {
	kp1, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("GenerateKeyPair: %v", err)
	}
	kp2, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("GenerateKeyPair: %v", err)
	}
	if kp1.Private == kp2.Private {
		t.Error("two generated private keys are identical — should be random")
	}
	if kp1.Public == kp2.Public {
		t.Error("two generated public keys are identical — should be random")
	}
}

func TestEncryptDecryptRoundtrip(t *testing.T) {
	kp, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("GenerateKeyPair: %v", err)
	}
	// Use key directly (simulates a derived shared key).
	key := kp.Private

	plaintext := "hello, mesh network!"
	nonce, ciphertext, err := Encrypt(key, plaintext)
	if err != nil {
		t.Fatalf("Encrypt: %v", err)
	}
	if ciphertext == plaintext {
		t.Error("ciphertext should not equal plaintext")
	}

	got, err := Decrypt(key, nonce, ciphertext)
	if err != nil {
		t.Fatalf("Decrypt: %v", err)
	}
	if got != plaintext {
		t.Errorf("Decrypt got %q, want %q", got, plaintext)
	}
}

func TestEncryptProducesDifferentNonceEachTime(t *testing.T) {
	kp, _ := GenerateKeyPair()
	key := kp.Private

	nonce1, ct1, _ := Encrypt(key, "same text")
	nonce2, ct2, _ := Encrypt(key, "same text")

	if bytes.Equal(nonce1, nonce2) {
		t.Error("two encryptions of same plaintext produced same nonce")
	}
	if ct1 == ct2 {
		t.Error("two encryptions of same plaintext produced same ciphertext (nonce reuse?)")
	}
}

func TestEncryptBytesRoundtrip(t *testing.T) {
	kp, _ := GenerateKeyPair()
	key := kp.Private

	plain := []byte{0x01, 0x02, 0x03, 0xFF, 0x00}
	nonce, ct, err := EncryptBytes(key, plain)
	if err != nil {
		t.Fatalf("EncryptBytes: %v", err)
	}

	got, err := DecryptBytes(key, nonce, ct)
	if err != nil {
		t.Fatalf("DecryptBytes: %v", err)
	}
	if !bytes.Equal(got, plain) {
		t.Errorf("DecryptBytes got %v, want %v", got, plain)
	}
}

func TestSharedSecretSymmetric(t *testing.T) {
	kpA, _ := GenerateKeyPair()
	kpB, _ := GenerateKeyPair()

	sharedAB, err := SharedSecret(kpA.Private, kpB.Public[:])
	if err != nil {
		t.Fatalf("SharedSecret A→B: %v", err)
	}
	sharedBA, err := SharedSecret(kpB.Private, kpA.Public[:])
	if err != nil {
		t.Fatalf("SharedSecret B→A: %v", err)
	}

	if sharedAB != sharedBA {
		t.Error("ECDH shared secrets are not symmetric: SharedSecret(privA,pubB) != SharedSecret(privB,pubA)")
	}
}

func TestDecryptWrongKey(t *testing.T) {
	kpA, _ := GenerateKeyPair()
	kpB, _ := GenerateKeyPair()

	nonce, ct, _ := Encrypt(kpA.Private, "secret")
	_, err := Decrypt(kpB.Private, nonce, ct)
	if err == nil {
		t.Error("Decrypt with wrong key should return error, got nil")
	}
}

func TestDecryptTamperedCiphertext(t *testing.T) {
	kp, _ := GenerateKeyPair()
	key := kp.Private

	nonce, ct, _ := Encrypt(key, "original")
	// Flip first byte of base64 string (will produce invalid base64 or wrong ciphertext).
	tamperedBytes := []byte(ct)
	tamperedBytes[0] ^= 0xFF
	tampered := string(tamperedBytes)
	_, err := Decrypt(key, nonce, tampered)
	if err == nil {
		t.Error("Decrypt with tampered ciphertext should return error, got nil")
	}
}

func TestDecryptEmptyCiphertext(t *testing.T) {
	kp, _ := GenerateKeyPair()
	nonce, _, _ := Encrypt(kp.Private, "x")
	_, err := Decrypt(kp.Private, nonce, "")
	if err == nil {
		t.Error("Decrypt with empty ciphertext should return error")
	}
}

func TestSharedSecretUsableForEncryption(t *testing.T) {
	kpA, _ := GenerateKeyPair()
	kpB, _ := GenerateKeyPair()

	shared, _ := SharedSecret(kpA.Private, kpB.Public[:])

	nonce, ct, err := Encrypt(shared, "via shared key")
	if err != nil {
		t.Fatalf("Encrypt with shared key: %v", err)
	}
	got, err := Decrypt(shared, nonce, ct)
	if err != nil {
		t.Fatalf("Decrypt with shared key: %v", err)
	}
	if got != "via shared key" {
		t.Errorf("got %q", got)
	}
}
