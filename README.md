https://disk.yandex.ru/d/-ySkUm3ud-8yHA



# Piper

Decentralized LAN messenger. No internet, no servers, no cloud. Devices discover each other over Wi-Fi/BLE and communicate directly via encrypted P2P connections.

> Built for Nuclear IT Hack — Hex.Team challenge.

---

## Features

- **Peer discovery** — mDNS/DNS-SD + UDP broadcast + BLE + Wi-Fi Direct
- **Encrypted messaging** — X25519 key exchange + ChaCha20-Poly1305 AEAD per peer session
- **Group chats** — multi-party encrypted rooms
- **File transfer** — chunked (512 KB), SHA-256 integrity, rate-limited to 5 MB/s
- **Voice/video calls** — WebRTC-based, mesh-routed signaling
- **Multi-hop relay** — messages route through intermediate nodes when no direct path exists
- **Spam protection** — per-peer sliding-window rate limiter (60 msg / 10 s)
- **Deduplication** — UUID-keyed seen-set (TTL 2 min) prevents broadcast loops
- **Cross-platform** — Windows, Android (Linux/macOS in progress)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   Flutter App (UI)                  │
│  screens/ · services/piper_service.dart · FFI       │
└────────────────────┬────────────────────────────────┘
                     │  FFI / shared library
┌────────────────────▼────────────────────────────────┐
│               Go Backend  (go/)                     │
│                                                     │
│  core/                                              │
│    node.go       — central P2P node lifecycle       │
│    discovery.go  — mDNS + UDP broadcast             │
│    message.go    — wire protocol (framed JSON)      │
│    crypto.go     — X25519 + ChaCha20-Poly1305       │
│    peer.go       — peer registry                    │
│    group.go      — group membership                 │
│    transfer.go   — chunked file transfer            │
│    spam.go       — rate limiting                    │
│                                                     │
│  mesh/                                              │
│    transport/    — Link abstraction (TCP, Wi-Fi D.) │
│    router/       — gossip peer table + route table  │
│    proxy/        — peer proxy for relay hops        │
│    healer/       — watchdog + rerouter              │
└─────────────────────────────────────────────────────┘
```

Full architecture with diagrams: [docs/architecture.md](docs/architecture.md)

---

## Prerequisites

| Tool | Version |
|------|---------|
| Go | 1.22+ |
| Flutter | 3.x |
| Android SDK | API 21+ |

---

## Building

### Windows installer + Android APK (from project root)

```bash
make
```

Individual targets:

```bash
make installer    # Windows NSIS installer (.exe)
make zip          # Windows portable ZIP
make android      # Android release APK
make linux        # Linux build (run inside WSL)
make clean        # delete build artifacts
```

### Go backend only

```bash
cd go
go build ./...
```

### Flutter app only

```bash
cd flutter-app
flutter build windows --release    # Windows
flutter build apk --release        # Android
flutter build linux --release      # Linux
```

---

## Running (development)

```bash
# Terminal UI (Go-only, no Flutter)
cd go
go run cmd/piper/main.go
```

Multiple instances on the same machine will discover each other automatically via UDP broadcast on port 47821.

---

## Testing

```bash
cd go
go test ./core/ -v -count=1 -timeout 60s
```

With race detector and coverage:

```bash
go test ./core/ -race -cover -coverprofile=coverage.out -timeout 120s
go tool cover -html=coverage.out
```

Full test documentation: [go/TESTING.md](go/TESTING.md)

**Test summary (65 tests total):**

| Package | Tests | Network |
|---------|-------|---------|
| `core/crypto` | 10 | No |
| `core/message` | 12 | No |
| `core/peer` | 10 | No |
| `core/group` | 9 | No |
| `core/transfer` | 9 | No |
| `core/node` (integration) | 15 | Yes (localhost) |

---

## Protocol

All messages are length-prefixed framed JSON over TCP:

```
[4 bytes big-endian length][JSON payload]
```

Message types:

| Type | Description |
|------|-------------|
| `hello` | Handshake — carries X25519 public key |
| `text` | Broadcast plaintext message |
| `direct` | Encrypted personal message (ChaCha20-Poly1305) |
| `group_text` | Encrypted group message |
| `relay` | Wrapped message for multi-hop forwarding |
| `file_offer/accept/chunk/done/reject` | File transfer protocol |
| `call_offer/answer/ice/end/reject/busy/ack` | Call signaling |
| `peer_exchange` | DHT gossip — shares known peer list |
| `ping/pong` | Keepalive |
| `leave` | Graceful disconnect |

---

## Security

- **Encryption:** X25519 ECDH key exchange per session + ChaCha20-Poly1305 AEAD
- **Integrity:** Poly1305 authentication tag on every message; file chunks verified with SHA-256
- **Replay protection:** Fresh ephemeral keypair on every startup; no persistent keys on disk
- **Spam protection:** Per-peer rate limiter (60 msg / 10 s sliding window)
- **Loop protection:** UUID-keyed dedup cache (TTL 2 min) for broadcast messages

Full threat model: [docs/threat-model.md](docs/threat-model.md)

---

## Logs and Metrics

Runtime log: `go/piper.log`

```bash
# Live tail
tail -f go/piper.log

# Filter by peer events
grep "peer" go/piper.log

# Filter errors
grep -i "error\|fail" go/piper.log
```

Diagnostics and metrics reference: [docs/metrics.md](docs/metrics.md)

---

## Project Structure

```
piper/
├── go/                     # Go backend
│   ├── cmd/piper/          # Entry point (TUI + FFI server)
│   ├── core/               # P2P node, protocol, crypto
│   ├── mesh/               # Mesh routing layer
│   │   ├── transport/      # Link abstraction
│   │   ├── router/         # Gossip + route table
│   │   ├── proxy/          # Relay proxy
│   │   └── healer/         # Watchdog + rerouter
│   ├── ffi/                # Flutter FFI bridge
│   └── tui/                # Bubble Tea terminal UI
├── flutter-app/            # Flutter frontend
│   ├── lib/
│   │   ├── screens/        # UI screens
│   │   ├── services/       # Service layer (piper, BLE, Wi-Fi Direct, calls)
│   │   ├── models/         # Data models
│   │   └── widgets/        # Reusable UI components
│   └── native/             # Platform-specific code
├── installer/              # NSIS installer scripts
├── scripts/                # Build scripts
├── docs/                   # Architecture, threat model, plans
└── installing-web-site/    # Landing page (Vite + React)
```

---

## Download

| Platform | Link |
|----------|------|
| Windows | [piper.exe](https://github.com/tuhlopuz1/piper/releases/download/release-piper/piper.exe) |
| Android | [app-release.apk](https://github.com/tuhlopuz1/piper/releases/download/release-piper/app-release.apk) |
| macOS / Linux / iOS | Coming soon |

---

## License

MIT
