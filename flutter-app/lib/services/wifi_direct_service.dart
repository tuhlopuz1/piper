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
