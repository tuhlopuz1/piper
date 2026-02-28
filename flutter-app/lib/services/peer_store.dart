import 'package:flutter/foundation.dart';

import '../models/chat.dart';
import '../models/message.dart';
import 'ipc_service.dart';

/// Central reactive store for LAN peers and chat messages.
/// Listens to [IpcService] WebSocket events and updates the UI via [ChangeNotifier].
class PeerStore extends ChangeNotifier {
  static final PeerStore instance = PeerStore._();

  PeerStore._() {
    IpcService.instance.on('peer_found').listen(_onPeerFound);
    IpcService.instance.on('peer_lost').listen(_onPeerLost);
    IpcService.instance.on('message').listen(_onMessage);
  }

  // ── State ─────────────────────────────────────────────────────────────────

  final Map<String, Contact> _peers = {};
  final Map<String, List<Message>> _messages = {};

  /// All currently connected peers (always online).
  List<Contact> get peers => List.unmodifiable(_peers.values.toList());

  /// Messages for a specific peer, oldest first.
  List<Message> messagesFor(String peerID) =>
      List.unmodifiable(_messages[peerID] ?? []);

  // ── Event handlers ────────────────────────────────────────────────────────

  void _onPeerFound(Map<String, dynamic> data) {
    final id = data['id'] as String? ?? '';
    final name = data['name'] as String? ?? 'Unknown';
    final ip = data['ip'] as String? ?? '';
    if (id.isEmpty) return;

    _peers[id] = Contact(
      id: id,
      name: name,
      avatarStyle: _styleFromId(id),
      initials: _initials(name),
      isOnline: true,
      address: ip,
    );
    notifyListeners();
  }

  void _onPeerLost(Map<String, dynamic> data) {
    final id = data['id'] as String? ?? '';
    if (id.isEmpty) return;
    _peers.remove(id);
    notifyListeners();
  }

  void _onMessage(Map<String, dynamic> data) {
    final peerID = data['from'] as String? ?? '';
    final text = data['text'] as String? ?? '';
    final ts = data['ts'] as int?;
    if (peerID.isEmpty) return;

    final sender = _peers[peerID];
    final msg = Message(
      id: 'recv_${DateTime.now().millisecondsSinceEpoch}',
      isMe: false,
      senderName: sender?.name,
      senderColor: sender?.avatarStyle.color,
      type: MsgType.text,
      text: text,
      time: ts != null
          ? DateTime.fromMillisecondsSinceEpoch(ts * 1000)
          : DateTime.now(),
    );
    (_messages[peerID] ??= []).add(msg);
    notifyListeners();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Sends a text message to [peerID].
  /// Adds to the local store immediately for instant UI feedback.
  void sendMessage(String peerID, String text) {
    final msg = Message(
      id: 'sent_${DateTime.now().millisecondsSinceEpoch}',
      isMe: true,
      type: MsgType.text,
      text: text,
      time: DateTime.now(),
      delivered: false,
    );
    (_messages[peerID] ??= []).add(msg);
    notifyListeners();

    // Fire-and-forget — network send in background
    IpcService.instance.sendText(peerID, text).catchError(
      (e) => debugPrint('[peer_store] sendText error: $e'),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static AvatarStyle _styleFromId(String id) {
    if (id.isEmpty) return AvatarStyle.violet;
    final hash = id.codeUnits.fold(0, (sum, c) => sum + c);
    return AvatarStyle.values[hash % AvatarStyle.values.length];
  }

  static String _initials(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    final parts = t.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return t.substring(0, t.length.clamp(0, 2)).toUpperCase();
  }
}
