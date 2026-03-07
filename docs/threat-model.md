# Piper — Threat Model

## Context

Piper is a decentralized LAN messenger with no central server. Peers discover each
other via mDNS, UDP broadcast, BLE, and WiFi Direct, then connect over TCP.
This document describes the security properties of the current implementation.

---

## What We Protect Against

### 1. Passive eavesdropping on LAN traffic
All direct and group messages are encrypted end-to-end using:
- **X25519 Diffie-Hellman** key exchange (RFC 7748) — ephemeral keypair per session
- **ChaCha20-Poly1305 AEAD** cipher (RFC 7539) — authenticated encryption
- **12-byte random nonce** per message — prevents identical ciphertexts for identical plaintexts

A passive observer capturing TCP packets cannot read message content or file data.
File transfer chunks are encrypted with the same per-peer shared secret.

### 2. Message tampering in transit
The ChaCha20-Poly1305 authentication tag covers both the nonce and ciphertext.
Any bit flip in the transmitted data causes decryption to fail and the message to
be silently dropped. An attacker cannot modify message content without detection.

### 3. Replay of captured sessions
Each node generates a fresh X25519 keypair on every startup. Captured traffic from
a previous session cannot be decrypted with a new session's shared secret. There is
no persistent long-term encryption key on disk.

### 4. Relay loop amplification
Message deduplication via per-node `seenMsgs` (keyed by message UUID, TTL 2 min)
prevents broadcast storms when the same message arrives via multiple relay paths.

---

## What We Partially Protect Against

### 5. Peer identity spoofing
Each peer has a stable UUID advertised over mDNS/BLE. On first connection, peers
exchange X25519 public keys in the Hello handshake; the shared secret is bound to
that key.

**Limitation:** The public key is not signed against the UUID. An attacker who can
intercept discovery traffic before the legitimate peer appears could advertise the
same UUID with a different public key. This is a TOFU (Trust On First Use) model.

**Mitigation in practice:** On a typical LAN the legitimate peer connects first;
subsequent connection attempts from the same UUID are de-duplicated. Risk is low
in cooperative environments.

### 6. Unauthorized mesh participation
Only peers reachable on the local network (mDNS, BLE scan range, same WiFi) can
join the mesh. There is no internet-facing endpoint.

**Limitation:** Any device on the same LAN or BLE range can participate. There is
no explicit allowlist.

---

## What We Do Not Protect Against

### 7. Active MITM by a LAN-level attacker
Without a PKI or persistent key pinning, an active attacker who can intercept and
respond to Hello messages before the legitimate peer does can substitute their own
public key and perform a man-in-the-middle attack on the ECDH exchange.

### 8. Global broadcast confidentiality
Broadcast text messages (sent to all peers, e.g. "public chat") are transmitted in
plaintext. This is intentional: broadcasts are designed for local group visibility.
Only direct (peer-to-peer) and group messages carry encryption.

### 9. DoS and message flooding
There is no rate limiting on incoming connections or messages. A malicious peer on
the same LAN could send high-volume traffic to degrade performance. The dedup filter
prevents relay amplification but does not cap raw ingestion rate.

### 10. Persistent group membership integrity
Group invites are not cryptographically signed by the group creator. A peer who
learns a group ID could send a valid-looking invite to another peer.

---

## Assumptions

| Assumption | Rationale |
|---|---|
| Participants are cooperative | LAN/office/hackathon scenario with known users |
| Physical network access is controlled | Attacker cannot join the WiFi/BLE range |
| First connection is legitimate | TOFU model holds when peers connect before attackers |

Piper is designed for **trusted local networks**, not for adversarial internet
deployment. Adding a PKI layer (e.g. pre-shared QR-code fingerprints) would close
the MITM gap for higher-security use cases.

---

## Cryptographic Primitives Summary

| Primitive | Algorithm | Standard | Purpose |
|---|---|---|---|
| Key exchange | X25519 | RFC 7748 | Establish shared secret per peer |
| Symmetric encryption | ChaCha20-Poly1305 | RFC 7539 | Encrypt + authenticate messages |
| Hash (file integrity) | SHA-256 | FIPS 180-4 | Verify received file chunks |
| Nonce | 12 bytes CSPRNG | — | Prevent ciphertext reuse |
