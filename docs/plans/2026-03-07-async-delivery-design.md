# Async Message Delivery — Design & Implementation Plan

**Date:** 2026-03-07
**Branch:** `try_dht_and_mesh`
**Status:** Phase 1 implemented, Phases 2-5 pending
**Scope:** `MsgTypeDirect` only (personal encrypted messages)

---

## Goals

1. **Local Retry Queue** — if a peer is offline, queue the message locally and flush it automatically when the peer reconnects.
2. **DHT Store-and-Forward** — if the sender goes offline before the recipient comes back, other nodes hold the encrypted message in a Kademlia DHT until the recipient fetches it.

---

## Architecture

```
Flutter App
    │  path_provider → storagePath
    │  FFI: PiperInit(handle, storagePath)
    ▼
mesh.Node
    ├── identity.Manager      persistent X25519 + Ed25519 from master seed
    ├── queue.RetryQueue       bbolt-backed, per-peer, MsgTypeDirect only
    ├── dht.OfflineStore       go-libp2p-kad-dht, sealed-box E2E
    └── core.Node (legacy)     existing transport, unchanged until Phase 5
```

---

## Cryptography

| Key | Algorithm | Purpose |
|-----|-----------|---------|
| Master seed | 32 bytes CSPRNG, stored as `identity.seed` | Root of all identity key material |
| X25519 identity | HKDF-SHA256(seed, `piper-x25519-v1`) | DHT sealed-box encryption |
| Ed25519 identity | HKDF-SHA256(seed, `piper-ed25519-v1`) | DHT record signing; libp2p PeerID |

**Sealed-box** (no libsodium dependency, uses existing primitives):
```
Seal(recipientX25519Pub, plaintext):
    ek_priv, ek_pub = ephemeral X25519 keypair
    shared          = X25519(ek_priv, recipientX25519Pub)
    nonce           = SHA256(ek_pub || recipientX25519Pub)[:12]
    ct              = ChaCha20-Poly1305.Seal(key=shared, nonce, plaintext)
    return ek_pub(32) || ct

Open(myX25519Priv, myX25519Pub, sealedBox):
    ek_pub = sealedBox[:32]
    shared = X25519(myX25519Priv, ek_pub)
    nonce  = SHA256(ek_pub || myX25519Pub)[:12]
    return ChaCha20-Poly1305.Open(shared, nonce, sealedBox[32:])
```

---

## DHT Design (go-libp2p-kad-dht)

**Two-level key scheme:**

```
/piper/inbox/v1/{hex20(SHA256(recipientX25519Pub)[:20])}
    → DHTInbox{ Items:[{MsgID, ExpiresAt}], Signature }
    Custom Selector: set-union merge (CRDT grow-only set)

/piper/msg/v1/{msgID}
    → DHTRecord{ SealedBox, ExpiresAt, SenderEd25519Pub, Signature }
    Immutable after write; expires via TTL (48h)
```

**Sender flow (Bob offline):**
1. `mesh.Node.Send` → peer disconnected → `RetryQueue.Enqueue`
2. `Watchdog` declares `LinkDead` → `offline.Store` encrypts + publishes to DHT

**Recipient flow (Bob reconnects):**
1. `Node.Start` → load identity key → bootstrap kad-dht from PeerTable
2. `FetchAndDeliver` → GET inbox index → GET each message payload → decrypt → emit event
3. Publish pruned inbox (claimed IDs removed) + mark seen in bbolt

**Security:**
- Every DHT record signed with sender's Ed25519 key; storing nodes verify before accepting
- Per-sender write rate limit: 10 DHT writes/min per recipient key
- Max 100 pending messages per recipient key (oldest evicted)
- `ExpiresAt` in signed payload; nodes reject expired and far-future records (cap 48h)
- Replay: `dht_seen` bbolt bucket persists delivered message IDs across restarts

**Deduplication race (direct + DHT both deliver):**
- `core.Node.seenMsgs` drops in-session duplicates
- `dht_seen` bbolt bucket drops cross-restart duplicates
- Claim is always sent after DHT delivery to clean up DHT storage

---

## Storage (bbolt)

Single file: `{storagePath}/piper.db`

| Bucket | Key | Value |
|--------|-----|-------|
| `retry` | `{peerID}\x00{msgID}` | msgpack(RetryEntry) |
| `dht_seen` | `{msgID}` | 8-byte LE Unix expiry |

---

## New Dependencies

| Package | Why |
|---------|-----|
| `go.etcd.io/bbolt` | Persistent retry queue + DHT seen cache |
| `go-libp2p` | libp2p host for kad-dht transport |
| `go-libp2p-kad-dht` | Kademlia DHT routing and storage |

All crypto (`hkdf`, `curve25519`, `chacha20poly1305`, `ed25519`) already in module.

---

## Implementation Phases

### Phase 1 — Storage Foundation ✅ DONE
**New:** `go/mesh/store/db.go` — bbolt wrapper, bucket init
**Modified:** `go/ffi/bridge.go` + `storage.go` — `PiperInit(handle, storagePath)` FFI, opens DB
**Modified:** `go/mesh/node.go` — `NewNodeWithStorage(name, id, path)` constructor

### Phase 2 — Persistent Identity
**New:** `go/mesh/identity/`
- `manager.go` — `Manager` struct, `Load(dir)`, atomic seed file I/O
- `keygen.go` — `FromSeed(seed)` via HKDF, derives X25519 + Ed25519 keypairs
- `sealedbox.go` — `Seal` / `Open` using ephemeral ECDH + ChaCha20-Poly1305

**Modified:**
- `go/mesh/router/peer_table.go` — add `IdentityX25519Pub`, `IdentityEd25519Pub` to `MeshPeer` (msgpack `omitempty`)
- `go/mesh/node.go` — load identity in `Start()`, expose `IdentityManager()`
- `go/ffi/storage.go` — `loadIdentity(dir)` method, called from `PiperInit`
- `go/ffi/bridge.go` — `identMgr *identity.Manager` on `nodeEntry`

### Phase 3 — Persistent Retry Queue
**New:** `go/mesh/queue/`
- `retry_queue.go` — bbolt-backed queue, `Enqueue` / `Flush` / `Expire`

**Modified:**
- `go/mesh/node.go` — intercept `Send` for offline peers, flush on `PeerJoined` event, expire ticker

Key behaviour:
```go
func (n *Node) Send(text, toPeerID string) {
    if toPeerID == "" || n.isPeerConnected(toPeerID) {
        n.legacy.Send(text, toPeerID)
        return
    }
    n.retryQ.Enqueue(RetryEntry{PeerID: toPeerID, Msg: ...})
}
// on PeerJoined event → flushRetryQueue(peerID) → legacy.Send each entry
```

Limits: 200 messages/peer, 24h TTL, expire ticker every 5 min.

### Phase 4 — DHT Store-and-Forward
**New:** `go/mesh/dht/`
- `host.go` — libp2p host from Ed25519 identity key, listens on `meshPort+1`
- `validator.go` — `PiperValidator` (Ed25519 verify + TTL check + inbox set-union merge)
- `records.go` — `DHTInbox`, `DHTRecord`, `DHTInboxItem` types + key helpers
- `store.go` — `OfflineStore.Store(ctx, msg, recipientPeer)` — seal + sign + PutValue
- `fetch.go` — `OfflineStore.FetchAndDeliver(ctx, deliver)` — GetValue + Open + dedup + claim

**Modified:**
- `go/mesh/node.go` — init libp2p host + kad-dht in `Start()`, bootstrap after 3s gossip settle; escalate to DHT after `Watchdog` LinkDead
- `go/ffi/bridge.go` — `PiperDHTDiag` returns real stats

### Phase 5 — Integration & Diagnostics
**Modified:**
- `go/mesh/node.go` — full wiring: `identity` + `retryQ` + `dhtHost` + `offline` all initialised in `Start()`; cross-restart dedup via `dht_seen` bucket
- `go/ffi/bridge.go` — `PiperPendingCount(handle, peerID)` FFI; updated `PiperMeshDiag`

Flutter UI states: ⏳ queued → 📡 stored in DHT → ✓ delivered

---

## Data Flow

```
SEND to offline peer:
  mesh.Node.Send
    ├─ connected?  YES → legacy.Send → TCP
    └─ NO → RetryQueue.Enqueue (bbolt)
               │
               ├─ [PeerJoined]    → flush → legacy.Send
               └─ [LinkDead]      → offline.Store:
                                       Seal(peerX25519Pub, msg)
                                       Sign(myEd25519Key, record)
                                       kad-dht PutValue x2 (inbox + payload)

FETCH on reconnect:
  Node.Start
    └─ FetchAndDeliver:
         kad-dht GetValue(inboxKey)
           └─ for each msgID:
                GetValue(msgKey) → verify sig → Open(myX25519Priv) → emit event
                markSeen(bbolt) → pruneClaimed(inboxKey)
```
