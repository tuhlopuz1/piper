# WiFi Direct Full Implementation Design

Date: 2026-03-07

## Summary

Add full Android WiFi Direct (Wi-Fi P2P) peer discovery and transport to piper's mesh network. Discovered peers are injected into the Go core via `injectPeers`, identical to the existing mDNS and BLE paths. No protocol changes are needed on the Go side beyond adding a `WifiDirectLink` transport.

## Approach

**Discovery + P2P group + WifiDirectLink as transport.Link over P2P TCP.**

- Android's `WifiP2pManager` handles peer discovery and GO (Group Owner) negotiation automatically.
- Once a group is formed, Go opens a TCP connection to the peer's IP:port.
- `WifiDirectLink` embeds `TCPLink` and adds a fixed `EdgeWeight` penalty of 10 ms (P2P links are reliable but not as fast as LAN).
- Peers flow into the mesh via `node.injectPeers()` — same pipeline as mDNS.

## Section 1: Android Layer

**BroadcastReceiver in MainActivity** (Approach 1).

`WifiDirectPlugin` (Kotlin):
- Holds `WifiP2pManager` + `WifiP2pManager.Channel`.
- Registers `WifiDirectReceiver : BroadcastReceiver` in `MainActivity.onResume` / unregisters in `onPause`.
- `WifiDirectReceiver` handles:
  - `WIFI_P2P_STATE_CHANGED_ACTION` — enable/disable discovery.
  - `WIFI_P2P_PEERS_CHANGED_ACTION` — call `requestPeers`; for each peer with a known IP, emit `{id, name, ip, port=7788}` on the `EventChannel`.
  - `WIFI_P2P_CONNECTION_CHANGED_ACTION` — on connection, call `requestConnectionInfo`; emit GO IP when available.
  - `WIFI_P2P_THIS_DEVICE_CHANGED_ACTION` — update local device info.
- `startDiscovery` calls `manager.discoverPeers(channel, ...)`.
- `stopDiscovery` calls `manager.stopPeerDiscovery(channel, ...)` and `manager.removeGroup(channel, ...)`.
- Events are sent to Flutter via `EventChannel("piper/wifidirect/events")`.

## Section 2: Go Transport Layer

`go/mesh/transport/wifi_direct_link.go`:
- `WifiDirectLink` embeds `*TCPLink`.
- Constructor: `NewWifiDirectLink(conn net.Conn, localID, remoteID [32]byte) *WifiDirectLink`.
- Overrides `Quality()` to add 10 ms to the embedded `TCPLink.Quality().RTT` (WiFi P2P penalty).
- All other methods (`Send`, `Close`, `Start`, `ID`) delegate to `TCPLink`.

`go/mesh/transport/wifi_direct_link_test.go`:
- Verify `Quality().RTT` includes the 10 ms penalty.
- Verify send/receive works end-to-end (reuse `TCPLink` test pattern).

Go peer injection: when Flutter emits `{ip, port}`, `WifiDirectService.dart` calls `node.injectPeers([PeerRecord(ip, port)])`. The Go core's mDNS dialer path dials TCP to that address and wraps the connection in `WifiDirectLink`.

> **Note:** The existing `TCPLink` dialer in `core.Node` dials plain TCP. To use `WifiDirectLink` instead of `TCPLink` for WiFi Direct peers, we mark injected peers with a `transport=wifidirect` tag, and the dialer checks the tag to choose the wrapper. Alternatively (simpler): `WifiDirectLink` is identical to `TCPLink` for now — the penalty is the only difference, and we can add it without a tag by making the dialer always use `WifiDirectLink` when the peer was injected from WiFi Direct. We store the source in `PeerRecord.Source` field.

## Section 3: Permissions & Manifest

Add to `AndroidManifest.xml`:

```xml
<!-- WiFi Direct discovery — required pre-API 33 -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
    android:maxSdkVersion="32" />
<!-- Android 13+ replacement for location during WiFi peer scan -->
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES"
    android:usesPermissionFlags="neverForLocation" />

<uses-feature android:name="android.hardware.wifi.direct" android:required="false" />
```

The existing `ACCESS_FINE_LOCATION` entry has `android:maxSdkVersion="30"` (for BLE). Add a separate entry covering API 31-32 for WiFi Direct, or change the cap to 32.

`MainActivity.onCreate` requests runtime permissions:
- API < 33: `ACCESS_FINE_LOCATION`
- API >= 33: `NEARBY_WIFI_DEVICES`

## Section 4: Flutter Wiring

`WifiDirectService` (existing skeleton in `lib/services/wifi_direct_service.dart`):
- `start(PiperNode node)` — calls `startDiscovery` and listens for peer events, injecting each as `PeerRecord`.
- `stop()` — calls `stopDiscovery`.

Initialization: call `WifiDirectService().start(node)` after `node.start()` in the same place other services (mDNS, BLE) are started. Call `stop()` in the dispose/shutdown path alongside `node.stop()`.

No UI changes needed — peers are invisible to the UI layer, handled entirely within the mesh routing layer.

## Files to Create / Modify

| File | Change |
|------|--------|
| `android/.../WifiDirectPlugin.kt` | Full BroadcastReceiver implementation |
| `android/.../MainActivity.kt` | Register/unregister receiver, request permissions |
| `android/.../AndroidManifest.xml` | Add WiFi Direct permissions + feature |
| `go/mesh/transport/wifi_direct_link.go` | `WifiDirectLink` embedding `TCPLink` |
| `go/mesh/transport/wifi_direct_link_test.go` | Quality penalty + send/receive test |
| `flutter-app/lib/services/wifi_direct_service.dart` | Full implementation (replace skeleton) |
| `flutter-app/lib/native/piper_events.dart` | Add `source` field to `PeerRecord` if needed |
