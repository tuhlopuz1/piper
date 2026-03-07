import 'dart:io';

import 'package:flutter/services.dart';

import '../native/piper_events.dart';
import '../native/piper_node.dart';

class WifiDirectService {
  static const _method = MethodChannel('piper/wifidirect');
  static const _events = EventChannel('piper/wifidirect/events');

  static bool get isSupported => Platform.isAndroid;

  Future<void> start(PiperNode node) async {
    if (!isSupported) return;
    await _method.invokeMethod<void>('startDiscovery');
    _events.receiveBroadcastStream().listen((event) {
      final map = Map<String, dynamic>.from(event as Map);
      final rec = PeerRecord(
        id:   map['id'] as String,
        name: map['name'] as String? ?? '',
        ip:   map['ip'] as String,
        port: map['port'] as int,
      );
      node.injectPeers([rec]);
    });
  }

  Future<void> stop() async {
    if (!isSupported) return;
    await _method.invokeMethod<void>('stopDiscovery');
  }
}
