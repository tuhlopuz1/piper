# Piper — Logs and Metrics

## Log Files

| File | Content |
|------|---------|
| `go/piper.log` | Main node runtime log (production) |
| `go/claudemess.log` | Secondary session log (development sessions) |

Logs are written by Go's standard `log` package and are prefixed with `[node]`, `[discovery]`, etc.

---

## Log Format

Each log line follows Go's default format:

```
YYYY/MM/DD HH:MM:SS [component] message
```

### Real examples from `piper.log`

```
2026/03/04 00:45:33 [node] listening on :49156 (id=08f999ca-048a-4b3d-84fe-8fa066913bf6)
2026/03/04 00:45:34 [node] ECDH shared key established with DESKTOP-0D8CF7J (fbd83c0e)
2026/03/04 00:47:57 [node] sent file offer "7.exe" (8451072 bytes) to DESKTOP-0D8CF7J
2026/03/04 00:47:57 [node] file "7.exe" accepted by DESKTOP-0D8CF7J
2026/03/04 00:47:57 [node] file "7.exe" sent to af039986 (hash=0ff8cfbded41cd72)
2026/03/04 00:48:20 [node] created group "123" (b79c5040)
2026/03/04 00:48:22 [node] invited DESKTOP-0D8CF7J#2 to group "123"
2026/03/04 11:22:41 [node] received invite to group "12345" from DESKTOP-MB879JA
2026/03/04 11:23:22 [node] file "7.exe" received from DESKTOP-MB879JA (hash=0ff8cfbded41cd72)
```

---

## Log Event Reference

### Node lifecycle

| Log message | Meaning |
|-------------|---------|
| `listening on :<port> (id=<uuid>)` | Node started; local TCP listener active |
| `read from <peerID>: ...` | Connection closed (graceful or abrupt) |
| `dial <ip>:<port>: i/o timeout` | Could not reach discovered peer |

### Peer events

| Log message | Meaning |
|-------------|---------|
| `ECDH shared key established with <name> (<id>)` | Handshake complete; encrypted channel ready |
| `peer <id> left` | Graceful disconnect received |

### Messaging

| Log message | Meaning |
|-------------|---------|
| `broadcast from <id>: <text>` | Received global broadcast |
| `direct from <id>: <text>` | Received encrypted personal message (after decrypt) |
| `relay: forwarding <msgID> to <peerID>` | Acting as relay node |
| `dedup: dropping seen message <msgID>` | Loop/duplicate prevention |
| `spam: dropping message from <peerID>` | Rate limit exceeded |

### File transfer

| Log message | Meaning |
|-------------|---------|
| `sent file offer "<name>" (<size> bytes) to <peer>` | Offer sent |
| `file "<name>" accepted by <peer>` | Receiver accepted |
| `file "<name>" sent to <id> (hash=<sha256>)` | Transfer complete; hash logged |
| `accepted file "<name>" (<size> bytes) from <peer>` | Incoming transfer started |
| `file "<name>" received from <peer> (hash=<sha256>)` | Transfer complete; hash logged |
| `sent group file offer "<name>" (<size> bytes) to <peer>` | Group file transfer offer |

### Groups

| Log message | Meaning |
|-------------|---------|
| `created group "<name>" (<id>)` | New group created |
| `invited <peer> to group "<name>"` | Invite sent |
| `received invite to group "<name>" from <peer>` | Invite received |
| `left group "<name>"` | Left a group |

---

## Monitoring Recipes

### Live log tail

```bash
tail -f go/piper.log
```

### Watch peer connections

```bash
grep "ECDH shared key" go/piper.log
```

### Watch disconnections

```bash
grep "read from" go/piper.log
```

### Watch file transfers

```bash
grep "file" go/piper.log
```

### Watch errors and timeouts

```bash
grep -iE "error|fail|timeout|refused" go/piper.log
```

### Watch relay activity

```bash
grep "relay" go/piper.log
```

### Watch spam drops

```bash
grep "spam\|dedup" go/piper.log
```

### Count unique peers seen in session

```bash
grep "ECDH shared key" go/piper.log | grep -oE '\([0-9a-f]{8}\)' | sort -u | wc -l
```

### Extract file transfer hashes (integrity audit)

```bash
grep "hash=" go/piper.log | grep -oE 'hash=[0-9a-f]+'
```

---

## Metrics from Test Coverage

Run coverage report to get per-package metrics:

```bash
cd go
go test ./core/ -cover -coverprofile=coverage.out -timeout 120s
go tool cover -func=coverage.out
go tool cover -html=coverage.out   # opens browser
```

Expected output (representative):

```
github.com/catsi/piper/core/crypto.go      GenerateKeyPair       100.0%
github.com/catsi/piper/core/crypto.go      DeriveSharedKey       100.0%
github.com/catsi/piper/core/crypto.go      Encrypt               100.0%
github.com/catsi/piper/core/crypto.go      Decrypt               100.0%
github.com/catsi/piper/core/message.go     WriteMsg              100.0%
github.com/catsi/piper/core/message.go     ReadMsg               100.0%
github.com/catsi/piper/core/peer.go        Upsert                100.0%
github.com/catsi/piper/core/transfer.go    Start                 100.0%
```

Existing coverage output: `go/coverage.out`

---

## Diagnostics for Specific Scenarios

### Peer not discovered

1. Check both peers are on the same subnet: `ip route` / `ipconfig`
2. Check UDP port 47821 is not firewalled
3. Check mDNS is not blocked (some routers disable multicast)
4. Check logs for `dial ... i/o timeout` — peer was discovered but TCP failed
5. Try BLE discovery as fallback (mobile only)

### Message not delivered

1. Check logs for `dedup: dropping` — message already seen (loop resolved correctly)
2. Check logs for `spam: dropping` — rate limit hit; sender sending too fast
3. Check if peer is still connected: `grep "ECDH\|read from" go/piper.log | tail -20`

### File transfer fails or hash mismatch

1. Check logs for `file ... received` vs `file ... sent` — compare hashes manually
2. Hash mismatch → chunk corruption in transit; file is discarded automatically
3. Check if transfer was throttled: rate limit is 5 MB/s; large files take time
4. Check disk space in `go/piper-files/`

### Relay not working

1. Check intermediate node is connected to both endpoints
2. Check logs on relay node for `relay: forwarding`
3. Check watchdog logs for `LinkDead` → reroute triggered

### Call quality degraded

1. Check logs for ICE candidate exchange (`call_ice` messages)
2. In Flutter debug mode, WebRTC stats are printed to console
3. Check local network congestion — file transfers are throttled to protect calls
4. Verify DTLS handshake completed (no `call_reject` or `call_busy` in logs)

---

## Performance Reference

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| File transfer rate limit | 5 MB/s (40 Mbit/s) | Leaves headroom for calls on typical Wi-Fi |
| File chunk size | 512 KB | Balance between overhead and memory |
| Spam limit | 60 msg / 10 s per peer | Blocks floods, allows normal conversation |
| Dedup TTL | 2 minutes | Long enough to cover all relay paths |
| Keepalive interval | 30 s (ping/pong) | Detects silent disconnects |
| Watchdog tick | ~5 s | Fast enough for real-time rerouting |
| UDP broadcast interval | 5 s | Peer discovery refresh |
| Max message size | 4 MB | Enforced by framing layer |
