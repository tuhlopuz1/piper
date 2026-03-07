# Piper — Architecture

## System Overview

Piper is a fully decentralized LAN messenger. There is no central server, no cloud relay, and no internet dependency. All communication happens directly between devices over the local network (Wi-Fi, Wi-Fi Direct, or BLE).

```
Device A                         Device B
┌──────────────────┐             ┌──────────────────┐
│  Flutter App     │             │  Flutter App     │
│  (UI layer)      │             │  (UI layer)      │
│        │ FFI     │             │        │ FFI     │
│  Go Backend      │◄────TCP────►│  Go Backend      │
│  core/node.go    │             │  core/node.go    │
└──────────────────┘             └──────────────────┘

         ▲ discovery (mDNS / UDP broadcast / BLE / Wi-Fi Direct)
         ▼
  Same LAN / BLE range
```

---

## Layers

### 1. Discovery Layer (`core/discovery.go`, Flutter services)

Piper uses four complementary discovery mechanisms so that peers are found regardless of router configuration:

| Mechanism | Protocol | Range | Fallback priority |
|-----------|----------|-------|-------------------|
| mDNS/DNS-SD | `_piper._tcp.local.` | Same LAN | Primary |
| UDP broadcast | Port 47821, 5 s interval | Same subnet | Fallback |
| BLE | GATT advertisement | ~10 m | Cross-subnet |
| Wi-Fi Direct | P2P group | Direct link | No router needed |

Each advertisement carries `(peerID, displayName, tcpPort)`. When a new address is found, `node.onDiscovered` is called and the node attempts a TCP connection.

**Peer exchange (DHT-lite):** After connecting, nodes exchange their known peer lists via `peer_exchange` messages. This allows peers who haven't directly discovered each other to learn about intermediate nodes and bootstrap a multi-hop path.

---

### 2. Transport Layer (`mesh/transport/`)

The `Link` interface abstracts any point-to-point connection:

```
type Link interface {
    PeerID()   string
    Send([]byte) error
    SetOnReceive(func([]byte))
    Close() error
}
```

Implementations:
- `TCPLink` — primary transport over TCP with length-prefixed frames
- `WiFiDirectLink` — Wi-Fi Direct (Android) P2P transport

---

### 3. Protocol Layer (`core/message.go`)

Wire format: **length-prefixed framed JSON** over TCP.

```
┌──────────────────┬──────────────────────────────┐
│  4 bytes (BE)    │  JSON payload (up to 4 MB)   │
│  payload length  │                              │
└──────────────────┴──────────────────────────────┘
```

Message structure:

```json
{
  "id":        "uuid-v4",
  "type":      "direct",
  "from":      "sender-peer-id",
  "to":        "recipient-peer-id",
  "name":      "Alice",
  "content":   "<base64 ciphertext>",
  "nonce":     "<base64 12-byte nonce>",
  "timestamp": 1700000000
}
```

**Message types and routing:**

```
hello          — sent immediately after TCP connect; carries X25519 pubkey
text           — broadcast plaintext (global chat)
direct         — encrypted personal message
group_invite   — invite peer to encrypted group
group_join     — peer accepted group invite
group_leave    — peer left group
group_text     — encrypted message to group members
relay          — wraps any message for multi-hop forwarding
file_offer     — propose file transfer (name, size, transferID)
file_accept    — receiver accepts offer
file_chunk     — one encrypted 512 KB chunk (index, data, hash)
file_done      — all chunks sent; carries final SHA-256
file_reject    — receiver declined
call_offer     — WebRTC SDP offer
call_answer    — WebRTC SDP answer
call_ice       — ICE candidate
call_end       — hang up
call_reject    — declined
call_busy      — peer already in call
call_ack       — delivery acknowledgement for call signaling
peer_exchange  — DHT gossip: list of known peers
ping / pong    — keepalive (30 s interval)
leave          — graceful disconnect
```

---

### 4. Crypto Layer (`core/crypto.go`)

```
Session startup:
  node A generates X25519 keypair (private_A, public_A)
  node B generates X25519 keypair (private_B, public_B)

Hello handshake:
  A ──hello{pubkey=public_A}──► B
  B ──hello{pubkey=public_B}──► A

Key derivation:
  shared_secret = X25519(private_A, public_B)
                = X25519(private_B, public_A)  ← same on both sides

Encryption (per message):
  nonce    = 12 random bytes (CSPRNG)
  ciphertext = ChaCha20-Poly1305.Seal(plaintext, key=shared_secret, nonce)
  wire     = base64(nonce) + base64(ciphertext)
```

File chunks use the same per-peer shared secret. Each chunk also carries its SHA-256 hash for integrity verification independent of the encryption layer.

---

### 5. Mesh / Routing Layer (`mesh/`)

When a direct TCP path between two peers doesn't exist (e.g., they are in different subnets connected only through a relay node), Piper routes messages via intermediate nodes.

```
Peer A ──────► Relay C ──────► Peer B
 (no direct path)
```

#### Relay protocol

The sender wraps the original message in a `relay` envelope:

```json
{
  "type": "relay",
  "to":   "peer-b-id",
  "relay_payload": "<base64 original message>"
}
```

The relay node (`C`) unwraps the envelope, looks up the next-hop for `peer-b-id`, and forwards it. TTL is enforced implicitly via the deduplication cache.

#### Gossip peer table (`mesh/router/`)

Nodes maintain a `PeerTable` updated via gossip:

```
Gossip cycle (push/pull):
  every pushInterval: broadcast full or delta peer list to all links
  every pullInterval: request full peer list from random link

GossipPacket {
  From    string     — sender node ID
  SeqNum  uint32     — monotonic sequence (dedup + ordering)
  Peers   []MeshPeer — known peers with last-seen timestamps
  IsDelta bool       — true = incremental update
}
```

#### Route table (`mesh/router/route.go`)

Shortest-path routing (hop count). Updated whenever the peer table changes. Routes are re-evaluated by the healer on link failure.

#### Watchdog + Rerouter (`mesh/healer/`)

```
Watchdog tick (configurable, default ~5 s):
  for each link:
    if silent > 2 ticks  → mark LinkDegraded
    if silent > 4 ticks  → mark LinkDead → TriggerReroute(peerID)

Rerouter:
  on TriggerReroute(peerID):
    find alternative path in route table
    redirect traffic to new next-hop
```

---

### 6. Reliability

#### Message deduplication

Every broadcast message carries a UUID. Each node maintains a `seenMsgs` map:

```
seenMsgs: map[messageID]time.Time
TTL: 2 minutes
```

If a message ID is already in `seenMsgs`, it is silently dropped. This prevents:
- Broadcast storms in mesh topologies
- Relay loops (A→B→C→A→…)

#### Spam / rate limiting (`core/spam.go`)

Per-peer sliding-window counter:

```
window:  10 seconds
limit:   60 messages per window
action:  drop excess messages silently
```

#### File transfer reliability (`core/transfer.go`, `core/node.go`)

```
Protocol:
  1. Sender: file_offer {id, name, size}
  2. Receiver: file_accept or file_reject
  3. Sender: file_chunk × N  (512 KB each, encrypted, SHA-256 per chunk)
  4. Sender: file_done {sha256_of_full_file}
  5. Receiver: verifies final hash

Throttling:  5 MB/s outbound (token bucket)
Integrity:   SHA-256 per chunk + full-file hash at completion
Resumption:  transfer ID tracked; partial state preserved on disconnect
```

---

### 7. Topology and Node Lifecycle

```
Node joins:
  1. Generate UUID + X25519 keypair
  2. Start TCP listener (random port)
  3. Start mDNS + UDP broadcast advertisement
  4. BLE advertisement (mobile)
  5. Connect to discovered peers, perform Hello handshake
  6. Receive peer_exchange from neighbors → discover indirect peers

Node leaves (graceful):
  1. Send `leave` message to all connected peers
  2. Peers mark node as PeerDisconnected
  3. Watchdog detects silence → TriggerReroute for affected paths

Node leaves (abrupt / crash):
  1. TCP read error detected on remote side
  2. Peer marked PeerDisconnected
  3. Watchdog triggers reroute after 2-4 tick silence
  4. Gossip propagates updated peer table (node removed)

Relay node failure:
  1. Watchdog on sender detects LinkDead for relay
  2. Rerouter finds alternative path (different relay or direct)
  3. If no path exists, message queued / user notified
```

---

### 8. Call Architecture

Voice/video calls use WebRTC for media transport. Piper's mesh layer handles signaling:

```
Caller A                  Mesh / relay               Callee B
   │                                                      │
   │── call_offer {sdp, is_video} ────────────────────►  │
   │                                                      │
   │◄─ call_answer {sdp} ──────────────────────────────  │
   │                                                      │
   │── call_ice {candidate} ─────────────────────────►   │  (ICE trickle)
   │◄─ call_ice {candidate} ──────────────────────────   │
   │                                                      │
   │◄══════════════ WebRTC media (DTLS-SRTP) ═══════════► │
   │                                                      │
   │── call_end ─────────────────────────────────────►   │
```

All signaling messages (`call_offer`, `call_answer`, `call_ice`) are encrypted with the per-peer ChaCha20-Poly1305 key before being sent as `direct` messages. Media flows directly between peers over WebRTC (DTLS-SRTP); Piper nodes are not involved in media forwarding.

**Jitter / buffer strategy:**
- Adaptive jitter buffer in Flutter's WebRTC stack (libwebrtc)
- Packet loss concealment (PLC) handled by Opus codec
- No retransmission for media (latency-sensitive); only signaling uses ack

---

### 9. Security Architecture

See full threat model: [threat-model.md](threat-model.md)

| Layer | Mechanism |
|-------|-----------|
| Key exchange | X25519 ECDH (ephemeral per session) |
| Message encryption | ChaCha20-Poly1305 AEAD |
| File integrity | SHA-256 per chunk + full file |
| Replay prevention | Fresh keypair on every startup |
| Loop prevention | UUID dedup cache (TTL 2 min) |
| Spam prevention | 60 msg/10 s per-peer rate limit |
| Identity | TOFU (Trust On First Use) via UUID + pubkey |

---

### 10. Component Diagram (detailed)

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter App                              │
│                                                                 │
│  ┌──────────┐  ┌──────────┐  ┌─────────────┐  ┌───────────┐  │
│  │  Chat    │  │  Calls   │  │  Contacts   │  │  Files    │  │
│  │  Screen  │  │  Screen  │  │  Screen     │  │  Screen   │  │
│  └────┬─────┘  └────┬─────┘  └──────┬──────┘  └─────┬─────┘  │
│       └─────────────┴───────────────┴────────────────┘        │
│                         │                                       │
│                  PiperService (FFI)                             │
│                  BLEDiscoveryService                            │
│                  WiFiDirectService                              │
│                  CallService / MeshCallService                  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ FFI / shared lib (.dll / .so)
┌───────────────────────────▼─────────────────────────────────────┐
│                       Go Backend                                │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    core/node.go                          │  │
│  │                                                          │  │
│  │  Discovery ◄──────────────────► PeerManager             │  │
│  │  (mDNS+UDP)                     (PeerInfo registry)      │  │
│  │                                                          │  │
│  │  GroupManager          TransferManager                   │  │
│  │  (group membership)    (chunked file transfer)           │  │
│  │                                                          │  │
│  │  crypto.go             spam.go                           │  │
│  │  (X25519+ChaCha20)     (rate limiter)                   │  │
│  │                                                          │  │
│  │  seenMsgs map          connByPeerID map                  │  │
│  │  (dedup cache)         (active TCP connections)          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                      mesh/                               │  │
│  │                                                          │  │
│  │  transport/Link ──► router/PeerTable ──► router/Route    │  │
│  │       │                    │                             │  │
│  │  TCPLink              router/Gossip                      │  │
│  │  WiFiDirectLink       (push/pull sync)                   │  │
│  │       │                    │                             │  │
│  │  proxy/PeerProxy      healer/Watchdog                    │  │
│  │  (relay forwarding)   healer/Rerouter                    │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```
