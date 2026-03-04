import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../native/piper_events.dart';
import '../native/piper_node.dart';

/// Singleton service that owns the Go PiperNode and exposes observable state.
/// Screens access it via context.watch<PiperService>() / context.read<PiperService>().
class PiperService extends ChangeNotifier {
  PiperNode? _node;
  StreamSubscription<PiperEvent>? _sub;

  /// Non-null when Go library failed to load or node failed to start.
  String? initError;

  List<PeerInfo> _peers = [];
  List<GroupInfo> _groups = [];

  /// chatId → ordered list of messages (oldest first).
  /// chatId: peerID for direct chats, 'group:<groupID>' for groups.
  final Map<String, List<Message>> _messages = {};

  // ── Public getters ────────────────────────────────────────────────────────

  String get myId => _node?.id ?? '';
  String get myName => _node?.name ?? '';
  bool get isRunning => _node != null && initError == null;

  List<PeerInfo> get peers => List.unmodifiable(_peers);
  List<GroupInfo> get groups => List.unmodifiable(_groups);
  Map<String, List<Message>> get messages => _messages;

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> init(String name) async {
    try {
      _node = PiperNode.create(name);
      _node!.start();
      _sub = _node!.events.listen(_onEvent);
      _refresh();
    } catch (e) {
      initError = e.toString();
      debugPrint('[PiperService] init error: $e');
      notifyListeners();
    }
  }

  void _refresh() {
    try {
      _peers = _node?.peers ?? [];
      _groups = _node?.groups ?? [];
    } catch (e) {
      debugPrint('[PiperService] refresh error: $e');
    }
    notifyListeners();
  }

  // ── Event handler ─────────────────────────────────────────────────────────

  void _onEvent(PiperEvent e) {
    switch (e.type) {
      case 'peer':
        _refresh();
      case 'group':
        _refresh();
      case 'message':
        _addIncomingMessage(e);
        notifyListeners();
      case 'transfer':
        notifyListeners();
    }
  }

  void _addIncomingMessage(PiperEvent e) {
    final chatId = (e.groupId?.isNotEmpty == true)
        ? 'group:${e.groupId}'
        : (e.peerId ?? '');
    if (chatId.isEmpty) return;

    _messages.putIfAbsent(chatId, () => []);
    _messages[chatId]!.add(Message(
      id: e.msgId ?? '${DateTime.now().millisecondsSinceEpoch}',
      isMe: false,
      senderName: e.peerName,
      senderColor: colorForPeer(e.peerId ?? ''),
      type: MsgType.text,
      text: e.content,
      time: e.timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(e.timestamp!)
          : DateTime.now(),
    ));
  }

  // ── Messaging ─────────────────────────────────────────────────────────────

  void sendText(String text, {String? toPeerId, String? groupId}) {
    if (_node == null) return;

    if (groupId != null && groupId.isNotEmpty) {
      _node!.sendGroup(text, groupId);
    } else if (toPeerId != null && toPeerId.isNotEmpty) {
      _node!.send(text, toPeerID: toPeerId);
    } else {
      return;
    }

    // Optimistic local add so the sender sees the message immediately.
    final chatId =
        groupId != null && groupId.isNotEmpty ? 'group:$groupId' : toPeerId!;
    _messages.putIfAbsent(chatId, () => []);
    _messages[chatId]!.add(Message(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      isMe: true,
      type: MsgType.text,
      text: text,
      time: DateTime.now(),
    ));
    notifyListeners();
  }

  void sendFile(String peerId, String filePath) {
    _node?.sendFile(peerId, filePath);
  }

  // ── Group management ──────────────────────────────────────────────────────

  String createGroup(String name) => _node?.createGroup(name) ?? '';
  void inviteToGroup(String groupId, String peerId) =>
      _node?.inviteToGroup(groupId, peerId);
  void leaveGroup(String groupId) => _node?.leaveGroup(groupId);

  // ── Helpers for UI ────────────────────────────────────────────────────────

  Color colorForPeer(String peerId) {
    const colors = [
      Color(0xFF7C3AED), // violet
      Color(0xFF06B6D4), // cyan
      Color(0xFFE11D48), // rose
      Color(0xFFF97316), // orange
      Color(0xFF10B981), // emerald
      Color(0xFF3B82F6), // blue
    ];
    if (peerId.isEmpty) return colors[0];
    final hash = peerId.codeUnits.fold(0, (a, b) => a + b);
    return colors[hash % colors.length];
  }

  AvatarStyle avatarStyleForPeer(String peerId) {
    if (peerId.isEmpty) return AvatarStyle.violet;
    final hash = peerId.codeUnits.fold(0, (a, b) => a + b);
    return AvatarStyle.values[hash % AvatarStyle.values.length];
  }

  String initialsFor(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  /// All known peers as Contact objects ready for the UI.
  List<Contact> get contacts => _peers
      .map((p) => Contact(
            id: p.id,
            name: p.displayName,
            avatarStyle: avatarStyleForPeer(p.id),
            initials: initialsFor(p.displayName),
            isOnline: p.isConnected,
            address: p.id.length > 12 ? '${p.id.substring(0, 12)}…' : p.id,
          ))
      .toList();

  /// Chats list derived from known peers + groups.
  List<Chat> get chats {
    final result = <Chat>[];

    for (final p in _peers) {
      final msgs = _messages[p.id] ?? [];
      result.add(Chat(
        id: p.id,
        name: p.displayName,
        lastMessage: msgs.isNotEmpty ? (msgs.last.text ?? '') : '',
        lastMessageTime:
            msgs.isNotEmpty ? msgs.last.time : DateTime.now(),
        unreadCount: 0,
        isGroup: false,
        avatarStyle: avatarStyleForPeer(p.id),
        initials: initialsFor(p.displayName),
        isOnline: p.isConnected,
        lastMessageType: MessageType.text,
      ));
    }

    for (final g in _groups) {
      final chatId = 'group:${g.id}';
      final msgs = _messages[chatId] ?? [];
      result.add(Chat(
        id: chatId,
        name: g.name,
        lastMessage: msgs.isNotEmpty ? (msgs.last.text ?? '') : '',
        lastMessageTime:
            msgs.isNotEmpty ? msgs.last.time : DateTime.now(),
        unreadCount: 0,
        isGroup: true,
        avatarStyle: AvatarStyle.indigo,
        initials: initialsFor(g.name),
        isOnline: false,
        lastMessageType: MessageType.text,
        memberCount: g.members.length,
      ));
    }

    return result;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _sub?.cancel();
    _node?.stop();
    super.dispose();
  }
}
