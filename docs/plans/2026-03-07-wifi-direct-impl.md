# WiFi Direct Full Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fully implement Android WiFi Direct peer discovery and transport so that WiFi Direct peers are injected into the Go mesh exactly like mDNS peers.

**Architecture:** Android's `WifiP2pManager` discovers devices and forms P2P groups; on connection the Group Owner IP is sent to Flutter via `EventChannel`; Flutter calls `node.injectPeers()`. Go connects via TCP and wraps the connection in `WifiDirectLink` (embeds `TCPLink`, adds 10ms RTT penalty). No protocol changes — the existing Go pipeline handles everything.

**Tech Stack:** Kotlin (Android P2P API), Flutter `MethodChannel`/`EventChannel`, Go `transport.TCPLink` embedding.

---

### Task 1: Go — `WifiDirectLink`

**Files:**
- Create: `go/mesh/transport/wifi_direct_link.go`
- Create: `go/mesh/transport/wifi_direct_link_test.go`

**Step 1: Write the failing test**

```go
// go/mesh/transport/wifi_direct_link_test.go
package transport_test

import (
	"net"
	"sync"
	"testing"
	"time"

	"github.com/catsi/piper/mesh/transport"
)

func TestWifiDirectLinkQualityPenalty(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	go func() {
		conn, _ := ln.Accept()
		conn.Close()
	}()

	conn, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()

	link := transport.NewWifiDirectLink("a", "b", conn)
	q := link.Quality()
	if q.RTT < 10*time.Millisecond {
		t.Fatalf("expected RTT >= 10ms penalty, got %v", q.RTT)
	}
}

func TestWifiDirectLinkSendReceive(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	received := make(chan []byte, 1)
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		conn, _ := ln.Accept()
		srv := transport.NewWifiDirectLink("server", "client", conn)
		srv.SetOnReceive(func(pkt []byte) {
			cp := make([]byte, len(pkt))
			copy(cp, pkt)
			received <- cp
		})
		srv.Start()
		<-time.After(2 * time.Second)
		srv.Close()
	}()

	conn, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	cli := transport.NewWifiDirectLink("client", "server", conn)
	cli.Start()

	msg := []byte("wifi-direct ping")
	if err := cli.Send(msg); err != nil {
		t.Fatal(err)
	}

	select {
	case got := <-received:
		if string(got) != string(msg) {
			t.Fatalf("want %q got %q", msg, got)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("timeout")
	}

	cli.Close()
	wg.Wait()
}
```

**Step 2: Run test to verify it fails**

```
cd go && go test ./mesh/transport/... -run TestWifiDirect -count=1
```
Expected: FAIL with "undefined: transport.NewWifiDirectLink"

**Step 3: Write minimal implementation**

```go
// go/mesh/transport/wifi_direct_link.go
package transport

import (
	"net"
	"time"
)

const wifiDirectRTTPenalty = 10 * time.Millisecond

// WifiDirectLink wraps TCPLink with a fixed RTT penalty to account for
// WiFi P2P overhead. All data methods delegate to the embedded TCPLink.
type WifiDirectLink struct {
	*TCPLink
}

func NewWifiDirectLink(id, peerID string, conn net.Conn) *WifiDirectLink {
	return &WifiDirectLink{TCPLink: NewTCPLink(id, peerID, conn)}
}

// Quality returns the underlying TCPLink quality with a minimum RTT of
// wifiDirectRTTPenalty so the router accounts for WiFi P2P overhead.
func (w *WifiDirectLink) Quality() LinkQuality {
	q := w.TCPLink.Quality()
	if q.RTT < wifiDirectRTTPenalty {
		q.RTT = wifiDirectRTTPenalty
	}
	return q
}
```

**Step 4: Run tests to verify they pass**

```
cd go && go test ./mesh/transport/... -count=1
```
Expected: PASS (all transport tests including new WifiDirect ones)

**Step 5: Commit**

```bash
git add go/mesh/transport/wifi_direct_link.go go/mesh/transport/wifi_direct_link_test.go
git commit -m "feat(mesh): add WifiDirectLink transport with 10ms RTT penalty"
```

---

### Task 2: Android Manifest — WiFi Direct permissions

**Files:**
- Modify: `flutter-app/android/app/src/main/AndroidManifest.xml`

**Step 1: Read the current manifest**

Read `flutter-app/android/app/src/main/AndroidManifest.xml` to see the existing permissions block (lines 1-30 approximately).

**Step 2: Add permissions**

Find the existing `ACCESS_FINE_LOCATION` entry (currently `android:maxSdkVersion="30"` for BLE). Change its cap to `"30"` but add a **new separate entry** for WiFi Direct covering API 31-32, plus `NEARBY_WIFI_DEVICES` for API 33+. Also add the `wifi.direct` feature.

Add these lines right after the existing BLE `<uses-feature android:name="android.hardware.bluetooth_le".../>` line:

```xml
    <!-- WiFi Direct discovery — required on API 31-32 (API ≤30 covered above, API 33+ by NEARBY_WIFI_DEVICES) -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
        android:minSdkVersion="31"
        android:maxSdkVersion="32" />
    <!-- Android 13+ (API 33+) replaces location permission for WiFi peer scan -->
    <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES"
        android:usesPermissionFlags="neverForLocation" />
    <uses-feature android:name="android.hardware.wifi.direct" android:required="false" />
```

**Step 3: Verify manifest is valid**

```
cd flutter-app && grep -n "wifi\|NEARBY\|FINE_LOCATION" android/app/src/main/AndroidManifest.xml
```
Expected: see the new lines listed.

**Step 4: Commit**

```bash
git add flutter-app/android/app/src/main/AndroidManifest.xml
git commit -m "feat(android): add WiFi Direct permissions and feature declaration"
```

---

### Task 3: Android — Full `WifiDirectPlugin.kt` implementation

**Files:**
- Modify: `flutter-app/android/app/src/main/kotlin/com/example/piper/WifiDirectPlugin.kt`

**Step 1: Read current file**

Read `flutter-app/android/app/src/main/kotlin/com/example/piper/WifiDirectPlugin.kt`.

**Step 2: Replace with full implementation**

Replace the entire file with:

```kotlin
package com.example.piper

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.NetworkInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class WifiDirectPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        const val P2P_PORT = 7788
    }

    private val manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager?
    private val p2pChannel: WifiP2pManager.Channel? =
        manager?.initialize(context, context.mainLooper, null)

    private var eventSink: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null

    // ── Flutter channels ──────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startDiscovery" -> startDiscovery(result)
            "stopDiscovery"  -> stopDiscovery(result)
            else             -> result.notImplemented()
        }
    }

    override fun onListen(args: Any?, sink: EventChannel.EventSink?) { eventSink = sink }
    override fun onCancel(args: Any?) { eventSink = null }

    // ── BroadcastReceiver lifecycle (called from MainActivity) ────────────────

    fun registerReceiver() {
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                when (intent.action) {
                    WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> onPeersChanged()
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        @Suppress("DEPRECATION")
                        val netInfo = intent.getParcelableExtra<NetworkInfo>(
                            WifiP2pManager.EXTRA_NETWORK_INFO
                        )
                        if (netInfo?.isConnected == true) {
                            onConnected()
                        }
                    }
                }
            }
        }
        context.registerReceiver(receiver, filter)
    }

    fun unregisterReceiver() {
        receiver?.let {
            try { context.unregisterReceiver(it) } catch (_: Exception) {}
        }
        receiver = null
    }

    // ── Discovery ─────────────────────────────────────────────────────────────

    private fun startDiscovery(result: MethodChannel.Result) {
        val mgr = manager ?: return result.success(null)
        val ch  = p2pChannel ?: return result.success(null)
        mgr.discoverPeers(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = result.success(null)
            // Non-fatal — WiFi Direct may be unsupported or disabled.
            override fun onFailure(reason: Int) = result.success(null)
        })
    }

    private fun stopDiscovery(result: MethodChannel.Result) {
        val mgr = manager ?: return result.success(null)
        val ch  = p2pChannel ?: return result.success(null)
        mgr.stopPeerDiscovery(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {}
            override fun onFailure(reason: Int) {}
        })
        mgr.removeGroup(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {}
            override fun onFailure(reason: Int) {}
        })
        result.success(null)
    }

    // ── P2P event handlers ────────────────────────────────────────────────────

    private fun onPeersChanged() {
        val mgr = manager ?: return
        val ch  = p2pChannel ?: return
        mgr.requestPeers(ch) { peerList ->
            peerList.deviceList.forEach { device ->
                // Attempt connection. groupOwnerIntent=0 → prefer to be client,
                // letting the other device be Group Owner so we can learn the IP.
                val config = WifiP2pConfig().apply {
                    deviceAddress = device.deviceAddress
                    groupOwnerIntent = 0
                }
                mgr.connect(ch, config, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {}
                    override fun onFailure(reason: Int) {}
                })
            }
        }
    }

    private fun onConnected() {
        val mgr = manager ?: return
        val ch  = p2pChannel ?: return
        mgr.requestConnectionInfo(ch) { info ->
            val ip = info?.groupOwnerAddress?.hostAddress ?: return@requestConnectionInfo
            val event = mapOf(
                "id"   to ip,
                "name" to "wifidirect",
                "ip"   to ip,
                "port" to P2P_PORT
            )
            eventSink?.success(event)
        }
    }
}
```

**Step 3: Verify Kotlin syntax by building**

```
cd flutter-app && ./gradlew compileDebugKotlin 2>&1 | tail -20
```
Expected: BUILD SUCCESSFUL (or only pre-existing warnings, no new errors).

**Step 4: Commit**

```bash
git add flutter-app/android/app/src/main/kotlin/com/example/piper/WifiDirectPlugin.kt
git commit -m "feat(android): implement WifiDirectPlugin with BroadcastReceiver and P2P discovery"
```

---

### Task 4: Android — `MainActivity.kt` channel registration + lifecycle

**Files:**
- Modify: `flutter-app/android/app/src/main/kotlin/com/example/piper/MainActivity.kt`

**Step 1: Read current file**

Read `flutter-app/android/app/src/main/kotlin/com/example/piper/MainActivity.kt`.

**Step 2: Replace with updated implementation**

Replace the entire file with:

```kotlin
package com.example.piper

import android.Manifest
import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiDirectPlugin: WifiDirectPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = WifiDirectPlugin(this)
        wifiDirectPlugin = plugin
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "piper/wifidirect"
        ).setMethodCallHandler(plugin)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "piper/wifidirect/events"
        ).setStreamHandler(plugin)
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        // Acquire multicast lock so Go's mDNS can join multicast groups.
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        multicastLock = wifi?.createMulticastLock("piper_mdns")?.also {
            it.setReferenceCounted(true)
            it.acquire()
        }

        // Request the permission required for WiFi Direct peer scan.
        val perms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        ActivityCompat.requestPermissions(this, perms, REQUEST_WIFI_DIRECT)
    }

    override fun onResume() {
        super.onResume()
        wifiDirectPlugin?.registerReceiver()
    }

    override fun onPause() {
        super.onPause()
        wifiDirectPlugin?.unregisterReceiver()
    }

    override fun onDestroy() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
        super.onDestroy()
    }

    companion object {
        private const val REQUEST_WIFI_DIRECT = 1
    }
}
```

**Step 3: Verify build**

```
cd flutter-app && ./gradlew compileDebugKotlin 2>&1 | tail -20
```
Expected: BUILD SUCCESSFUL.

**Step 4: Commit**

```bash
git add flutter-app/android/app/src/main/kotlin/com/example/piper/MainActivity.kt
git commit -m "feat(android): register WiFi Direct channels and BroadcastReceiver lifecycle in MainActivity"
```

---

### Task 5: Flutter — Fix `WifiDirectService` subscription cancellation

**Files:**
- Modify: `flutter-app/lib/services/wifi_direct_service.dart`

**Step 1: Read current file**

Read `flutter-app/lib/services/wifi_direct_service.dart`.

The existing skeleton already calls `startDiscovery` and `injectPeers` correctly, but the `EventChannel` subscription is not stored so it cannot be cancelled on `stop()`. This causes a memory leak and spurious events after `stop()`.

**Step 2: Edit — store subscription and cancel on stop**

Replace the entire file with:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../native/piper_events.dart';
import '../native/piper_node.dart';

class WifiDirectService {
  static const _method = MethodChannel('piper/wifidirect');
  static const _events = EventChannel('piper/wifidirect/events');

  static bool get isSupported => Platform.isAndroid;

  StreamSubscription<dynamic>? _subscription;

  Future<void> start(PiperNode node) async {
    if (!isSupported) return;
    await _method.invokeMethod<void>('startDiscovery');
    _subscription = _events.receiveBroadcastStream().listen((event) {
      final map = Map<String, dynamic>.from(event as Map);
      final ip = map['ip'] as String? ?? '';
      if (ip.isEmpty) return;
      final rec = PeerRecord(
        id:   map['id'] as String? ?? ip,
        name: map['name'] as String? ?? '',
        ip:   ip,
        port: map['port'] as int? ?? 7788,
      );
      node.injectPeers([rec]);
    });
  }

  Future<void> stop() async {
    if (!isSupported) return;
    await _subscription?.cancel();
    _subscription = null;
    await _method.invokeMethod<void>('stopDiscovery');
  }
}
```

**Step 3: Verify no analysis errors**

```
cd flutter-app && flutter analyze lib/services/wifi_direct_service.dart 2>&1 | tail -10
```
Expected: "No issues found" or only pre-existing warnings.

**Step 4: Commit**

```bash
git add flutter-app/lib/services/wifi_direct_service.dart
git commit -m "fix(flutter): store and cancel WifiDirectService EventChannel subscription on stop"
```

---

### Task 6: Flutter — Wire `WifiDirectService` into `PiperService`

**Files:**
- Modify: `flutter-app/lib/services/piper_service.dart`

**Step 1: Read current file**

Read `flutter-app/lib/services/piper_service.dart` (focus on imports, class fields, `init()`, and `dispose()`).

**Step 2: Add import**

At the top of `piper_service.dart`, after the `ble_discovery_service.dart` import line, add:

```dart
import 'wifi_direct_service.dart';
```

**Step 3: Add field**

Find `BleDiscoveryService? _ble;` and add below it:

```dart
  WifiDirectService? _wifiDirect;
```

**Step 4: Start WiFi Direct after BLE in `init()`**

Find the BLE block in `init()`:

```dart
      if (BleDiscoveryService.isSupported) {
        _ble = BleDiscoveryService(_node!);
        _ble!.start();
      }
```

Add immediately after:

```dart
      if (WifiDirectService.isSupported) {
        _wifiDirect = WifiDirectService();
        await _wifiDirect!.start(_node!);
      }
```

**Step 5: Stop WiFi Direct in `dispose()`**

Find `_ble?.stop();` in `dispose()` and add below it:

```dart
    _wifiDirect?.stop();
```

**Step 6: Verify no analysis errors**

```
cd flutter-app && flutter analyze lib/services/piper_service.dart 2>&1 | tail -10
```
Expected: no new issues.

**Step 7: Commit**

```bash
git add flutter-app/lib/services/piper_service.dart
git commit -m "feat(flutter): start and stop WifiDirectService alongside BLE in PiperService"
```

---

### Task 7: Full build verification

**Step 1: Run all Go mesh tests**

```
cd go && go test ./mesh/... -count=1 -v 2>&1 | tail -30
```
Expected: all PASS, none FAIL.

**Step 2: Run Flutter analysis**

```
cd flutter-app && flutter analyze 2>&1 | tail -20
```
Expected: no new issues introduced by these changes.

**Step 3: Android debug build**

```
cd flutter-app && flutter build apk --debug 2>&1 | tail -20
```
Expected: BUILD SUCCESSFUL.

**Step 4: Commit if any fixes needed, otherwise done**

If all pass with no changes needed, the implementation is complete.
