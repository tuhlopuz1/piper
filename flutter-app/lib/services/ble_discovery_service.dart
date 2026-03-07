import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../native/piper_events.dart';
import '../native/piper_node.dart';

/// BLE peer discovery for cross-subnet mesh bootstrap.
///
/// Protocol:
///   - Each device advertises a custom Piper service UUID (peripheral role,
///     via flutter_ble_peripheral).
///   - Manufacturer data (22 bytes) encodes our TCP endpoint:
///       [ip0, ip1, ip2, ip3, port_hi, port_lo, uuid_bytes[0..15]]
///   - On seeing a Piper advertisement (central role, via flutter_blue_plus),
///     the endpoint is decoded and injected into the Go node via InjectPeers.
///   - Go then dials TCP → normal handshake → DHT peer_exchange spreads all
///     known peers further.
///
/// Future work: WiFi Direct transport (same PeerRecord payload via Nearby).
class BleDiscoveryService {
  // 128-bit UUID that identifies Piper BLE advertisements.
  static const String _piperServiceUuid =
      '12340000-0000-1000-8000-00805f9b34fb';

  // Arbitrary manufacturer company ID used in advertisement payload.
  static const int _piperCompanyId = 0x1337;

  final PiperNode _node;
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _running = false;

  BleDiscoveryService(this._node);

  /// Returns true if BLE is available on this platform.
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// Start advertising our endpoint and scanning for other Piper devices.
  Future<void> start() async {
    if (!isSupported || _running) return;
    if (!await _requestPermissions()) return;

    _running = true;
    // Advertising and scanning run concurrently; failures in one don't
    // prevent the other from working.
    await Future.wait([
      _startAdvertising().catchError((e) => _log('advertising unavailable: $e')),
      _startScanning().catchError((e) => _log('scanning unavailable: $e')),
    ]);
  }

  /// Stop advertising and scanning.
  Future<void> stop() async {
    _running = false;
    _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    try {
      if (await _peripheral.isAdvertising) await _peripheral.stop();
    } catch (_) {}
  }

  // ─── Advertising (peripheral role) ────────────────────────────────────────

  Future<void> _startAdvertising() async {
    final info = _node.localInfo();
    if (info == null || info.ip.isEmpty || info.port <= 0) {
      _log('no local endpoint yet, skipping advertising');
      return;
    }

    final payload = _encodeEndpoint(info);
    if (payload == null) {
      _log('could not encode local endpoint');
      return;
    }

    final advertiseData = AdvertiseData(
      serviceUuid: _piperServiceUuid,
      manufacturerId: _piperCompanyId,
      manufacturerData: payload,
      includeDeviceName: false,
    );

    await _peripheral.start(advertiseData: advertiseData);
    _log('advertising ${info.ip}:${info.port} id=${info.id.substring(0, 8)}');
  }

  // ─── Scanning (central role) ───────────────────────────────────────────────

  Future<void> _startScanning() async {
    // Filter by Piper service UUID so we don't process unrelated devices.
    await FlutterBluePlus.startScan(
      withServices: [Guid(_piperServiceUuid)],
      continuousUpdates: true,
    );
    _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);
    _log('scanning for Piper BLE peers…');
  }

  void _onScanResults(List<ScanResult> results) {
    for (final r in results) {
      final mfrData = r.advertisementData.manufacturerData[_piperCompanyId];
      if (mfrData == null || mfrData.length < 22) continue;

      final record = _decodeEndpoint(mfrData);
      if (record == null) continue;
      if (record.id == _node.id) continue; // skip ourselves

      _log('BLE found peer ${record.ip}:${record.port} id=${record.id.substring(0, 8)}');
      _node.injectPeers([record]);
    }
  }

  // ─── Encoding ─────────────────────────────────────────────────────────────
  //
  // Binary layout (22 bytes):
  //   [0..3]   IPv4 address (network byte order)
  //   [4..5]   TCP port     (big-endian uint16)
  //   [6..21]  Peer UUID    (16 bytes, dashes stripped, hex-decoded)

  Uint8List? _encodeEndpoint(PeerRecord rec) {
    try {
      final ipParts = rec.ip.split('.');
      if (ipParts.length != 4) return null;

      final uuidHex = rec.id.replaceAll('-', '');
      if (uuidHex.length != 32) return null;

      final buf = Uint8List(22);
      buf[0] = int.parse(ipParts[0]);
      buf[1] = int.parse(ipParts[1]);
      buf[2] = int.parse(ipParts[2]);
      buf[3] = int.parse(ipParts[3]);
      buf[4] = (rec.port >> 8) & 0xFF;
      buf[5] = rec.port & 0xFF;
      for (var i = 0; i < 16; i++) {
        buf[6 + i] =
            int.parse(uuidHex.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return buf;
    } catch (_) {
      return null;
    }
  }

  PeerRecord? _decodeEndpoint(List<int> data) {
    try {
      final ip = '${data[0]}.${data[1]}.${data[2]}.${data[3]}';
      final port = (data[4] << 8) | data[5];
      if (port <= 0 || port > 65535) return null;

      // Reconstruct UUID string from 16 bytes: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      final hex = StringBuffer();
      for (var i = 0; i < 16; i++) {
        hex.write(data[6 + i].toRadixString(16).padLeft(2, '0'));
      }
      final h = hex.toString();
      final id =
          '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';

      return PeerRecord(id: id, name: '', ip: ip, port: port);
    } catch (_) {
      return null;
    }
  }

  // ─── Permissions ──────────────────────────────────────────────────────────

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      return statuses.values.every((s) => s.isGranted);
    }
    if (Platform.isIOS) {
      final status = await Permission.bluetooth.request();
      return status.isGranted;
    }
    return false;
  }

  void _log(String msg) {
    // ignore: avoid_print
    print('[ble] $msg');
  }
}
