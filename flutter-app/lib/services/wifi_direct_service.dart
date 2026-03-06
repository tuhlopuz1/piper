import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class WifiDirectEndpoint {
  final String peerId;
  final String name;
  final String ip;
  final int port;

  const WifiDirectEndpoint({
    required this.peerId,
    required this.name,
    required this.ip,
    required this.port,
  });

  factory WifiDirectEndpoint.fromJson(Map<dynamic, dynamic> json) {
    return WifiDirectEndpoint(
      peerId: json['peer_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      ip: json['ip'] as String? ?? '',
      port: json['port'] as int? ?? 0,
    );
  }
}

class WifiDirectService {
  WifiDirectService._();
  static final WifiDirectService instance = WifiDirectService._();

  static const MethodChannel _method = MethodChannel('piper/wifi_direct');
  static const EventChannel _events = EventChannel('piper/wifi_direct/events');

  StreamSubscription<dynamic>? _sub;
  final _endpointController = StreamController<WifiDirectEndpoint>.broadcast();

  Stream<WifiDirectEndpoint> get endpoints => _endpointController.stream;

  Future<void> init() async {
    if (!Platform.isAndroid) return;
    _sub ??= _events.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final endpoint = WifiDirectEndpoint.fromJson(event);
        if (endpoint.peerId.isNotEmpty && endpoint.ip.isNotEmpty && endpoint.port > 0) {
          _endpointController.add(endpoint);
        }
      }
    });
    await _method.invokeMethod<void>('init');
  }

  Future<void> startDiscovery() async {
    if (!Platform.isAndroid) return;
    await _method.invokeMethod<void>('discover');
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
