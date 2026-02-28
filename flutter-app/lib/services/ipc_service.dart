import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// IpcService connects to the running Go daemon via:
///   - WebSocket  `ws://127.0.0.1:{port}/ws`   — real-time events (daemon → Flutter)
///   - HTTP       `http://127.0.0.1:{port}/api` — commands        (Flutter → daemon)
class IpcService {
  static final IpcService instance = IpcService._();
  IpcService._();

  int? _port;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  // One broadcast StreamController per event name
  final _streams = <String, StreamController<Map<String, dynamic>>>{};

  bool get isConnected => _port != null;

  /// Call once the daemon is up and has reported its port.
  void connect(int port) {
    _port = port;
    _channel = WebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:$port/ws'),
    );

    _sub = _channel!.stream.listen(
      (raw) {
        try {
          final envelope = jsonDecode(raw as String) as Map<String, dynamic>;
          final event = envelope['event'] as String?;
          final data = envelope['data'];
          if (event != null && data is Map<String, dynamic>) {
            _streams[event]?.add(data);
          }
        } catch (e) {
          debugPrint('[ipc] parse error: $e');
        }
      },
      onError: (e) => debugPrint('[ipc] WS error: $e'),
      onDone: () => debugPrint('[ipc] WS closed'),
    );

    debugPrint('[ipc] connected to daemon on port $port');
  }

  void disconnect() {
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _port = null;
  }

  /// Subscribe to a daemon event (e.g. "peer_found", "message", "call_signal").
  Stream<Map<String, dynamic>> on(String event) {
    _streams[event] ??= StreamController<Map<String, dynamic>>.broadcast();
    return _streams[event]!.stream;
  }

  // ── HTTP commands ─────────────────────────────────────────────────────────

  /// Returns daemon status: id, name, ip, port.
  Future<Map<String, dynamic>> getStatus() =>
      _get('/api/status').then((r) => r as Map<String, dynamic>);

  /// Returns list of connected peers: [{id, name, ip}].
  Future<List<Map<String, dynamic>>> getPeers() =>
      _get('/api/peers').then((r) => (r as List)
          .map((e) => e as Map<String, dynamic>)
          .toList());

  /// Sends a text message to [peerID].
  Future<void> sendText(String peerID, String text) =>
      _post('/api/message/send', {'to': peerID, 'text': text});

  /// Sends a WebRTC signaling payload (offer/answer/ICE) to [peerID].
  Future<void> sendCallSignal(
    String peerID, {
    String sdpType = '',
    String sdp = '',
    String candidate = '',
  }) =>
      _post('/api/call/signal', {
        'to': peerID,
        'sdp_type': sdpType,
        'sdp': sdp,
        'candidate': candidate,
      });

  /// Notifies [peerID] that the call has ended.
  Future<void> endCall(String peerID) =>
      _post('/api/call/end', {'to': peerID});

  /// Updates our display name and avatar colour in the daemon.
  Future<void> setProfile(String name, String avatarColor) =>
      _post('/api/profile/set', {'name': name, 'avatar_color': avatarColor});

  // ── internals ─────────────────────────────────────────────────────────────

  Uri _uri(String path) => Uri.parse('http://127.0.0.1:$_port$path');

  Future<dynamic> _get(String path) async {
    final r = await http.get(_uri(path));
    return jsonDecode(r.body);
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    await http.post(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }
}
