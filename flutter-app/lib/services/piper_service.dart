import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../native/piper_events.dart';
import '../native/piper_node.dart';
import 'call_service.dart';
import 'database_service.dart';
import 'log_service.dart';

/// Singleton service that owns the Go PiperNode and exposes observable state.
class PiperService extends ChangeNotifier {
  PiperNode? _node;
  StreamSubscription<PiperEvent>? _sub;

  /// Non-null when Go library failed to load or node failed to start.
  String? initError;

  List<PeerInfo> _peers = [];
  List<GroupInfo> _groups = [];

  /// Where received files are saved on this device.
  String _downloadsDir = '';
  String get downloadsDir => _downloadsDir;

  /// Chosen avatar style (persisted across sessions).
  AvatarStyle _avatarStyle = AvatarStyle.violet;
  AvatarStyle get avatarStyle => _avatarStyle;

  /// chatId → ordered list of messages (oldest first).
  final Map<String, List<Message>> _messages = {};

  // ── Transfer progress tracking ─────────────────────────────────────────────

  /// msgId → progress (0.0–1.0) while the outgoing transfer is in flight.
  final Map<String, double> _progressByMsgId = {};
  Map<String, double> get progressByMsgId => _progressByMsgId;

  // fileName → (chatId, msgId): links a pending outgoing file to its optimistic message.
  final Map<String, (String, String)> _pendingFiles = {};
  // transferId → msgId
  final Map<String, String> _transferToMsgId = {};
  // dedup: incoming transfer IDs already shown as a bubble
  final Set<String> _processedIncomingTransfers = {};

  // ── Call history ──────────────────────────────────────────────────────────
  final List<CallRecord> _callHistory = [];
  List<CallRecord> get callHistory => List.unmodifiable(_callHistory);

  // ── Unread counts (persisted) ──────────────────────────────────────────────
  final Map<String, int> _unreadCounts = {};

  // ── Chat display names (persisted) — needed to show offline peers ──────────
  final Map<String, String> _chatNames = {};

  /// Set by ChatScreen when a chat is opened; used to skip unread increment.
  String? currentChatId;

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
      _downloadsDir = await _resolveDownloadsDir();
      final prefs = await SharedPreferences.getInstance();

      // Restore or generate a stable peer ID.
      final savedId = prefs.getString('node_id');

      // Restore avatar style.
      final avatarIndex = prefs.getInt('user_avatar');
      if (avatarIndex != null && avatarIndex < AvatarStyle.values.length) {
        _avatarStyle = AvatarStyle.values[avatarIndex];
      }

      _node = PiperNode.create(name, nodeId: savedId);

      // Persist the ID after first creation so it survives app restarts.
      if (savedId == null) {
        await prefs.setString('node_id', _node!.id);
      }

      _node!.setDownloadsDir(_downloadsDir);
      _node!.start();
      _sub = _node!.events.listen(_onEvent);
      CallService.instance.init(_node!);
      CallService.instance.onCallEnded = _onCallEnded;
      await CallService.instance.loadDevicePreferences();

      // Load persisted messages, unread counts, and chat names.
      await DatabaseService.instance.init();
      final storedMessages = await DatabaseService.instance.getAllMessages();
      _messages.addAll(storedMessages);
      final storedUnreads = await DatabaseService.instance.getUnreadCounts();
      _unreadCounts.addAll(storedUnreads);
      final storedNames = await DatabaseService.instance.getChatNames();
      _chatNames.addAll(storedNames);

      // Rebuild call history from persisted call messages.
      for (final entry in _messages.entries) {
        for (final msg in entry.value) {
          if (msg.type == MsgType.call) {
            _callHistory.add(CallRecord(
              peerId: entry.key,
              peerName: msg.senderName ?? _chatNames[entry.key] ?? entry.key,
              direction: msg.isMe ? CallDirection.outgoing : CallDirection.incoming,
              isVideo: msg.callIsVideo ?? false,
              durationSeconds: msg.callDuration ?? 0,
              answered: msg.callResult == CallResult.answered,
              time: msg.time,
            ));
          }
        }
      }
      _callHistory.sort((a, b) => b.time.compareTo(a.time));

      _refresh();
    } catch (e) {
      initError = e.toString();
      LogService.instance.error('[PiperService] init error', detail: '$e');
      notifyListeners();
    }
  }

  /// Called by ChatScreen when the user opens a chat — clears unread badge.
  Future<void> markChatAsRead(String chatId) async {
    if (_unreadCounts[chatId] == 0) return;
    _unreadCounts[chatId] = 0;
    await DatabaseService.instance.clearUnread(chatId);
    notifyListeners();
  }

  /// Update display name and avatar, persist to SharedPreferences.
  Future<void> rename(String newName, AvatarStyle newAvatar) async {
    _avatarStyle = newAvatar;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', newName);
    await prefs.setInt('user_avatar', newAvatar.index);
    _node?.setName(newName);
    notifyListeners();
  }

  static Future<String> _resolveDownloadsDir() async {
    Directory base;
    if (Platform.isAndroid) {
      base = (await getExternalStorageDirectory()) ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/piper-downloads');
    await dir.create(recursive: true);
    return dir.path;
  }

  void _refresh() {
    try {
      _peers = _node?.peers ?? [];
      _groups = _node?.groups ?? [];
    } catch (e) {
      LogService.instance.warning('[PiperService] refresh error: $e');
    }
    notifyListeners();
  }

  // ── Event handler ─────────────────────────────────────────────────────────

  void _onEvent(PiperEvent e) {
    if (e.type == 'peer') {
      _refresh();
      return;
    }
    if (e.type == 'group') {
      _refresh();
      return;
    }
    if (e.type == 'message') {
      _addIncomingMessage(e);
      notifyListeners();
      return;
    }
    if (e.type == 'transfer') {
      _handleTransfer(e);
      return;
    }
    if (e.type == 'call') {
      CallService.instance.handleSignal(e);
    }
  }

  void _addIncomingMessage(PiperEvent e) {
    if (e.peerId == myId) return;

    final String chatId;
    if (e.groupId?.isNotEmpty == true) {
      chatId = 'group:${e.groupId}';
    } else if (e.msgType == 'text') {
      chatId = 'global';
    } else {
      chatId = e.peerId ?? '';
    }
    if (chatId.isEmpty) return;

    _messages.putIfAbsent(chatId, () => []);
    final msg = Message(
      id: e.msgId ?? '${DateTime.now().millisecondsSinceEpoch}',
      isMe: false,
      senderName: e.peerName,
      senderColor: colorForPeer(e.peerId ?? ''),
      type: MsgType.text,
      text: e.content,
      time: e.timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(e.timestamp!)
          : DateTime.now(),
    );
    _messages[chatId]!.add(msg);

    // Persist name for DM chats so offline peers can still be shown.
    if (e.peerName != null &&
        e.peerName!.isNotEmpty &&
        !chatId.startsWith('group:') &&
        chatId != 'global') {
      _chatNames[chatId] = e.peerName!;
      DatabaseService.instance.upsertChatName(chatId, e.peerName!);
    }

    // Persist and track unread.
    DatabaseService.instance.insertMessage(chatId, msg);
    if (currentChatId != chatId) {
      _unreadCounts[chatId] = (_unreadCounts[chatId] ?? 0) + 1;
      DatabaseService.instance.incrementUnread(chatId);
    }
  }

  void _handleTransfer(PiperEvent e) {
    final tid = e.transferId ?? '';

    if (e.sending == true) {
      // ── Outgoing transfer ──────────────────────────────────────────────────
      switch (e.transferKind) {
        case 'offered':
          final key = e.fileName ?? '';
          if (_pendingFiles.containsKey(key)) {
            final (_, msgId) = _pendingFiles.remove(key)!;
            _transferToMsgId[tid] = msgId;
            _progressByMsgId[msgId] = 0.0;
            notifyListeners();
          }

        case 'progress':
          final msgId = _transferToMsgId[tid];
          if (msgId != null && (e.fileSize ?? 0) > 0) {
            _progressByMsgId[msgId] = (e.progress ?? 0) / e.fileSize!;
            notifyListeners();
          }

        case 'completed':
          final msgId = _transferToMsgId.remove(tid);
          if (msgId != null) _progressByMsgId.remove(msgId);
          notifyListeners();

        case 'failed':
          final msgId = _transferToMsgId.remove(tid);
          if (msgId != null) _progressByMsgId.remove(msgId);
          notifyListeners();
      }
    } else {
      // ── Incoming transfer ──────────────────────────────────────────────────
      if (e.transferKind != 'completed') return;
      if (tid.isEmpty || !_processedIncomingTransfers.add(tid)) return;
      final chatId = e.groupId?.isNotEmpty == true
          ? 'group:${e.groupId}'
          : (e.peerId ?? '');
      if (chatId.isEmpty) return;

      final filePath = e.fileName != null
          ? '$_downloadsDir${Platform.pathSeparator}${e.fileName}'
          : null;

      _messages.putIfAbsent(chatId, () => []);
      final fileMsg = Message(
        id: e.transferId ?? '${DateTime.now().millisecondsSinceEpoch}',
        isMe: false,
        senderName: e.peerName,
        senderColor: colorForPeer(e.peerId ?? ''),
        type: MsgType.file,
        fileName: e.fileName,
        fileExt: e.fileName?.split('.').last.toUpperCase(),
        fileSize: e.fileSize,
        filePath: filePath,
        time: DateTime.now(),
      );
      _messages[chatId]!.add(fileMsg);

      // Persist and track unread.
      DatabaseService.instance.insertMessage(chatId, fileMsg);
      if (currentChatId != chatId) {
        _unreadCounts[chatId] = (_unreadCounts[chatId] ?? 0) + 1;
        DatabaseService.instance.incrementUnread(chatId);
      }
      notifyListeners();
    }
  }

  // ── Call history ────────────────────────────────────────────────────────────

  void _onCallEnded(CallRecord record) {
    _callHistory.insert(0, record);

    // Also add a call message bubble to the DM chat.
    final chatId = record.peerId;
    final CallResult result;
    if (record.answered) {
      result = CallResult.answered;
    } else if (record.direction == CallDirection.incoming) {
      result = CallResult.missed;
    } else {
      result = CallResult.rejected;
    }

    final isMe = record.direction == CallDirection.outgoing;
    final msg = Message(
      id: 'call_${record.time.millisecondsSinceEpoch}',
      isMe: isMe,
      senderName: isMe ? null : record.peerName,
      type: MsgType.call,
      callDuration: record.durationSeconds,
      callIsVideo: record.isVideo,
      callResult: result,
      time: record.time,
    );

    _messages.putIfAbsent(chatId, () => []);
    _messages[chatId]!.add(msg);
    DatabaseService.instance.insertMessage(chatId, msg);

    // Persist peer name for offline display.
    if (record.peerName.isNotEmpty) {
      _chatNames[chatId] = record.peerName;
      DatabaseService.instance.upsertChatName(chatId, record.peerName);
    }

    notifyListeners();
  }

  // ── Messaging ─────────────────────────────────────────────────────────────

  void sendText(String text, {String? toPeerId, String? groupId}) {
    if (_node == null) return;

    final String chatId;
    if (groupId != null && groupId.isNotEmpty) {
      _node!.sendGroup(text, groupId);
      chatId = 'group:$groupId';
    } else if (toPeerId != null && toPeerId.isNotEmpty) {
      _node!.send(text, toPeerID: toPeerId);
      chatId = toPeerId;
    } else {
      _node!.send(text);
      chatId = 'global';
    }

    // Persist peer name for DM chats so the peer appears even when offline.
    if (toPeerId != null && toPeerId.isNotEmpty) {
      final peerName = _peers
          .where((p) => p.id == toPeerId)
          .map((p) => p.displayName)
          .firstOrNull;
      if (peerName != null && peerName.isNotEmpty) {
        _chatNames[toPeerId] = peerName;
        DatabaseService.instance.upsertChatName(toPeerId, peerName);
      }
    }

    _messages.putIfAbsent(chatId, () => []);
    final outMsg = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      isMe: true,
      type: MsgType.text,
      text: text,
      time: DateTime.now(),
    );
    _messages[chatId]!.add(outMsg);
    DatabaseService.instance.insertMessage(chatId, outMsg);
    notifyListeners();
  }

  void sendFile(String peerId, String filePath) {
    if (_node == null) return;

    // Extract file name (handle both separators).
    final name = filePath
        .replaceAll(r'\', '/')
        .split('/')
        .lastWhere((p) => p.isNotEmpty, orElse: () => 'file');
    final ext = name.contains('.') ? name.split('.').last.toUpperCase() : null;

    int? size;
    try {
      size = File(filePath).statSync().size;
    } catch (_) {}

    final msgId = 'file_${DateTime.now().millisecondsSinceEpoch}';

    // Persist peer name so the peer appears even when offline.
    final peerName = _peers
        .where((p) => p.id == peerId)
        .map((p) => p.displayName)
        .firstOrNull;
    if (peerName != null && peerName.isNotEmpty) {
      _chatNames[peerId] = peerName;
      DatabaseService.instance.upsertChatName(peerId, peerName);
    }

    _messages.putIfAbsent(peerId, () => []);
    final outFileMsg = Message(
      id: msgId,
      isMe: true,
      type: MsgType.file,
      fileName: name,
      fileExt: ext,
      fileSize: size,
      filePath: filePath,
      time: DateTime.now(),
      delivered: false,
    );
    _messages[peerId]!.add(outFileMsg);
    DatabaseService.instance.insertMessage(peerId, outFileMsg);

    // Track so we can link to transferId when the 'offered' event arrives.
    _pendingFiles[name] = (peerId, msgId);

    try {
      _node!.sendFile(peerId, filePath);
    } catch (e) {
      _pendingFiles.remove(name);
      LogService.instance.error('[PiperService] sendFile error: $e');
    }

    notifyListeners();
  }

  // ── Group management ──────────────────────────────────────────────────────

  String createGroup(String name) => _node?.createGroup(name) ?? '';
  void inviteToGroup(String groupId, String peerId) =>
      _node?.inviteToGroup(groupId, peerId);
  void leaveGroup(String groupId) => _node?.leaveGroup(groupId);

  // ── Helpers for UI ────────────────────────────────────────────────────────

  Color colorForPeer(String peerId) {
    const colors = [
      Color(0xFF7C3AED),
      Color(0xFF06B6D4),
      Color(0xFFE11D48),
      Color(0xFFF97316),
      Color(0xFF10B981),
      Color(0xFF3B82F6),
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

  List<Chat> get chats {
    final result = <Chat>[];

    // ── Global chat (always shown) ────────────────────────────────────────────
    final globalMsgs = _messages['global'] ?? [];
    final onlinePeers = _peers.where((p) => p.isConnected).length;
    result.add(Chat(
      id: 'global',
      name: 'Общий чат',
      lastMessage: globalMsgs.isNotEmpty
          ? (globalMsgs.last.text ?? '')
          : 'Переписка со всеми в сети',
      lastMessageTime:
          globalMsgs.isNotEmpty ? globalMsgs.last.time : DateTime.now(),
      unreadCount: _unreadCounts['global'] ?? 0,
      isGroup: true,
      avatarStyle: AvatarStyle.emerald,
      initials: '#',
      isOnline: onlinePeers > 0,
      lastMessageType: MessageType.text,
      memberCount: onlinePeers + 1,
    ));

    // ── DM chats: only those with at least one message ────────────────────────
    // Includes both online and offline peers (offline = known from history).
    final onlinePeerMap = {for (final p in _peers) p.id: p};

    final dmChatIds = _messages.keys
        .where((id) => id != 'global' && !id.startsWith('group:'))
        .toList();

    for (final peerId in dmChatIds) {
      final msgs = _messages[peerId] ?? [];
      if (msgs.isEmpty) continue;

      final livePeer = onlinePeerMap[peerId];
      final name = livePeer?.displayName ?? _chatNames[peerId] ?? peerId;

      result.add(Chat(
        id: peerId,
        name: name,
        lastMessage: msgs.last.text ?? '',
        lastMessageTime: msgs.last.time,
        unreadCount: _unreadCounts[peerId] ?? 0,
        isGroup: false,
        avatarStyle: avatarStyleForPeer(peerId),
        initials: initialsFor(name),
        isOnline: livePeer?.isConnected ?? false,
        lastMessageType: MessageType.text,
      ));
    }

    // ── Group chats ───────────────────────────────────────────────────────────
    for (final g in _groups) {
      final chatId = 'group:${g.id}';
      final msgs = _messages[chatId] ?? [];
      result.add(Chat(
        id: chatId,
        name: g.name,
        lastMessage: msgs.isNotEmpty ? (msgs.last.text ?? '') : '',
        lastMessageTime: msgs.isNotEmpty ? msgs.last.time : DateTime.now(),
        unreadCount: _unreadCounts[chatId] ?? 0,
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
