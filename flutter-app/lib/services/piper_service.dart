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

class PiperUserError {
  final String message;
  final String? chatId;

  const PiperUserError(this.message, {this.chatId});
}

class _PendingAttachmentCandidate {
  final String chatId;
  final String msgId;
  final String fileName;
  final int? fileSize;
  final String attachmentKind;
  final int? voiceDuration;
  final int expectedTransfers;

  const _PendingAttachmentCandidate({
    required this.chatId,
    required this.msgId,
    required this.fileName,
    required this.fileSize,
    required this.attachmentKind,
    required this.voiceDuration,
    required this.expectedTransfers,
  });
}

class _OutgoingAttachmentTracker {
  final String chatId;
  final String msgId;
  final int expectedTransfers;
  final int fileSize;
  String? attachmentId;
  final Map<String, int> progressByTransferId = {};
  final Set<String> completedTransferIds = {};
  final Set<String> failedTransferIds = {};
  bool errorNotified = false;

  _OutgoingAttachmentTracker({
    required this.chatId,
    required this.msgId,
    required this.expectedTransfers,
    required this.fileSize,
    this.attachmentId,
  });

  int get resolvedTransfers =>
      completedTransferIds.length + failedTransferIds.length;
}

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

  final StreamController<PiperUserError> _userErrors =
      StreamController<PiperUserError>.broadcast();
  Stream<PiperUserError> get userErrors => _userErrors.stream;

  final Map<String, List<_PendingAttachmentCandidate>> _pendingAttachments = {};
  final Map<String, _OutgoingAttachmentTracker> _outgoingAttachments = {};
  final Map<String, String> _transferToAttachmentId = {};
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
              direction:
                  msg.isMe ? CallDirection.outgoing : CallDirection.incoming,
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
    _persistChatName(chatId, e.peerName);

    // Persist and track unread.
    DatabaseService.instance.insertMessage(chatId, msg);
    if (currentChatId != chatId) {
      _unreadCounts[chatId] = (_unreadCounts[chatId] ?? 0) + 1;
      DatabaseService.instance.incrementUnread(chatId);
    }
  }

  void _handleTransfer(PiperEvent e) {
    final tid = e.transferId ?? '';
    final chatId = _chatIdForTransfer(e);
    if (chatId.isEmpty) return;

    if (e.sending == true) {
      _handleOutgoingTransfer(e, chatId);
      return;
    }

    if (e.transferKind != 'completed') return;
    if (tid.isEmpty || !_processedIncomingTransfers.add(tid)) return;

    final attachmentKind = _attachmentKindForEvent(e);
    final filePath = e.fileName == null
        ? null
        : '$_downloadsDir${Platform.pathSeparator}${e.fileName}';
    final msg = Message(
      id: tid,
      isMe: false,
      senderName: e.peerName,
      senderColor: colorForPeer(e.peerId ?? ''),
      type: attachmentKind == 'voice' ? MsgType.voice : MsgType.file,
      fileName: e.fileName,
      fileExt: attachmentKind == 'voice'
          ? null
          : e.fileName?.split('.').last.toUpperCase(),
      fileSize: e.fileSize,
      filePath: filePath,
      voiceDuration: e.voiceDuration,
      time: DateTime.now(),
    );

    _messages.putIfAbsent(chatId, () => []);
    _messages[chatId]!.add(msg);
    _persistChatName(chatId, e.peerName);
    DatabaseService.instance.insertMessage(chatId, msg);
    if (currentChatId != chatId) {
      _unreadCounts[chatId] = (_unreadCounts[chatId] ?? 0) + 1;
      DatabaseService.instance.incrementUnread(chatId);
    }
    notifyListeners();
  }

  String _chatIdForTransfer(PiperEvent e) {
    if (e.groupId?.isNotEmpty == true) {
      return 'group:${e.groupId}';
    }
    return e.peerId ?? '';
  }

  String _attachmentKindForEvent(PiperEvent e) {
    return e.attachmentKind == 'voice' ? 'voice' : 'file';
  }

  void _handleOutgoingTransfer(PiperEvent e, String chatId) {
    final tracker = _resolveOutgoingAttachmentTracker(e, chatId);
    if (tracker == null) return;

    final transferId = e.transferId ?? '';
    final attachmentId = tracker.attachmentId;
    if (transferId.isNotEmpty && attachmentId != null) {
      _transferToAttachmentId[transferId] = attachmentId;
    }

    final perTransferSize =
        tracker.fileSize > 0 ? tracker.fileSize : (e.fileSize ?? 0);

    final transferKind = e.transferKind;
    if (transferKind == 'offered' || transferKind == 'started') {
      if (transferId.isNotEmpty) {
        tracker.progressByTransferId.putIfAbsent(transferId, () => 0);
      }
    } else if (transferKind == 'progress') {
      if (transferId.isNotEmpty) {
        tracker.progressByTransferId[transferId] = e.progress ?? 0;
      }
    } else if (transferKind == 'completed') {
      if (transferId.isNotEmpty) {
        tracker.progressByTransferId[transferId] = perTransferSize;
        tracker.completedTransferIds.add(transferId);
      }
    } else if (transferKind == 'failed') {
      if (transferId.isNotEmpty) {
        tracker.progressByTransferId
            .putIfAbsent(transferId, () => e.progress ?? 0);
        tracker.failedTransferIds.add(transferId);
      }
      if (!tracker.errorNotified) {
        tracker.errorNotified = true;
        _emitAttachmentError(chatId, _attachmentKindForEvent(e));
      }
    }

    final expectedTransfers = tracker.expectedTransfers > 0
        ? tracker.expectedTransfers
        : (tracker.progressByTransferId.isNotEmpty
            ? tracker.progressByTransferId.length
            : 1);
    final totalBytes = perTransferSize * expectedTransfers;
    final sentBytes = tracker.progressByTransferId.values
        .fold<int>(0, (sum, value) => sum + value);
    if (tracker.resolvedTransfers >= expectedTransfers) {
      _progressByMsgId.remove(tracker.msgId);
    } else if (totalBytes > 0) {
      _progressByMsgId[tracker.msgId] =
          (sentBytes / totalBytes).clamp(0.0, 1.0);
    }

    if (tracker.failedTransferIds.isEmpty &&
        tracker.completedTransferIds.length >= expectedTransfers) {
      _progressByMsgId.remove(tracker.msgId);
      _setMessageDelivered(chatId, tracker.msgId, delivered: true);
      DatabaseService.instance.markDelivered(tracker.msgId);
      _cleanupOutgoingAttachmentTracker(tracker);
    } else if (tracker.resolvedTransfers >= expectedTransfers &&
        tracker.failedTransferIds.isNotEmpty) {
      _progressByMsgId.remove(tracker.msgId);
      _cleanupOutgoingAttachmentTracker(tracker);
    }

    notifyListeners();
  }

  _OutgoingAttachmentTracker? _resolveOutgoingAttachmentTracker(
    PiperEvent e,
    String chatId,
  ) {
    final attachmentId = e.attachmentId;
    if (attachmentId != null && attachmentId.isNotEmpty) {
      final existing = _outgoingAttachments[attachmentId];
      if (existing != null) {
        return existing;
      }
    }

    final transferId = e.transferId;
    if (transferId != null && transferId.isNotEmpty) {
      final mappedAttachmentId = _transferToAttachmentId[transferId];
      if (mappedAttachmentId != null) {
        return _outgoingAttachments[mappedAttachmentId];
      }
    }

    final fileName = e.fileName;
    if (fileName == null || fileName.isEmpty) return null;

    final lookupKey = _pendingAttachmentLookupKey(
      chatId: chatId,
      fileName: fileName,
      attachmentKind: _attachmentKindForEvent(e),
      voiceDuration: e.voiceDuration,
    );
    final queue = _pendingAttachments[lookupKey];
    if (queue == null || queue.isEmpty) return null;

    final pending = queue.removeAt(0);
    if (queue.isEmpty) {
      _pendingAttachments.remove(lookupKey);
    }

    final resolvedAttachmentId =
        (attachmentId != null && attachmentId.isNotEmpty)
            ? attachmentId
            : 'legacy:${transferId ?? pending.msgId}';
    final tracker = _OutgoingAttachmentTracker(
      chatId: pending.chatId,
      msgId: pending.msgId,
      expectedTransfers: pending.expectedTransfers,
      fileSize: pending.fileSize ?? (e.fileSize ?? 0),
      attachmentId: resolvedAttachmentId,
    );
    _outgoingAttachments[resolvedAttachmentId] = tracker;
    return tracker;
  }

  String _pendingAttachmentLookupKey({
    required String chatId,
    required String fileName,
    required String attachmentKind,
    required int? voiceDuration,
  }) {
    return '$chatId|$attachmentKind|$fileName|${voiceDuration ?? 0}';
  }

  void _registerPendingAttachment(_PendingAttachmentCandidate candidate) {
    final key = _pendingAttachmentLookupKey(
      chatId: candidate.chatId,
      fileName: candidate.fileName,
      attachmentKind: candidate.attachmentKind,
      voiceDuration: candidate.voiceDuration,
    );
    _pendingAttachments.putIfAbsent(key, () => []).add(candidate);
  }

  void _removePendingAttachment(_PendingAttachmentCandidate candidate) {
    final key = _pendingAttachmentLookupKey(
      chatId: candidate.chatId,
      fileName: candidate.fileName,
      attachmentKind: candidate.attachmentKind,
      voiceDuration: candidate.voiceDuration,
    );
    final queue = _pendingAttachments[key];
    if (queue == null) return;
    queue.removeWhere((item) => item.msgId == candidate.msgId);
    if (queue.isEmpty) {
      _pendingAttachments.remove(key);
    }
  }

  void _cleanupOutgoingAttachmentTracker(_OutgoingAttachmentTracker tracker) {
    final attachmentId = tracker.attachmentId;
    if (attachmentId != null) {
      _outgoingAttachments.remove(attachmentId);
      _transferToAttachmentId.removeWhere((_, value) => value == attachmentId);
    }
  }

  void _emitAttachmentError(String chatId, String attachmentKind) {
    final message = attachmentKind == 'voice'
        ? 'Не удалось отправить голосовое сообщение'
        : 'Не удалось отправить файл';
    _userErrors.add(PiperUserError(message, chatId: chatId));
  }

  void _persistChatName(String chatId, String? peerName) {
    if (peerName == null ||
        peerName.isEmpty ||
        chatId.startsWith('group:') ||
        chatId == 'global') {
      return;
    }
    _chatNames[chatId] = peerName;
    DatabaseService.instance.upsertChatName(chatId, peerName);
  }

  void _setMessageDelivered(
    String chatId,
    String msgId, {
    required bool delivered,
  }) {
    final list = _messages[chatId];
    if (list == null) return;
    final index = list.indexWhere((message) => message.id == msgId);
    if (index == -1) return;
    final updated = list[index].copyWith(delivered: delivered);
    list[index] = updated;
    DatabaseService.instance.insertMessage(chatId, updated);
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
      _persistChatName(toPeerId, peerName);
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
    _sendAttachment(
      attachmentKind: 'file',
      filePath: filePath,
      toPeerId: peerId,
    );
  }

  void sendVoice({
    String? toPeerId,
    String? groupId,
    required String filePath,
    required int durationSec,
  }) {
    if ((toPeerId == null || toPeerId.isEmpty) &&
        (groupId == null || groupId.isEmpty)) {
      _userErrors.add(const PiperUserError(
        'Голосовые сообщения в общий чат не поддерживаются',
        chatId: 'global',
      ));
      return;
    }
    _sendAttachment(
      attachmentKind: 'voice',
      filePath: filePath,
      toPeerId: toPeerId,
      groupId: groupId,
      voiceDuration: durationSec,
    );
  }

  void _sendAttachment({
    required String attachmentKind,
    required String filePath,
    String? toPeerId,
    String? groupId,
    int? voiceDuration,
  }) {
    if (_node == null) return;

    final chatId = groupId != null && groupId.isNotEmpty
        ? 'group:$groupId'
        : (toPeerId ?? '');
    if (chatId.isEmpty) return;

    final name = filePath
        .replaceAll(r'\', '/')
        .split('/')
        .lastWhere((part) => part.isNotEmpty, orElse: () => 'file');
    final ext = attachmentKind == 'voice'
        ? null
        : (name.contains('.') ? name.split('.').last.toUpperCase() : null);

    int? size;
    try {
      size = File(filePath).statSync().size;
    } catch (_) {}

    if (toPeerId != null && toPeerId.isNotEmpty) {
      final peerName = _peers
          .where((peer) => peer.id == toPeerId)
          .map((peer) => peer.displayName)
          .firstOrNull;
      _persistChatName(toPeerId, peerName);
    }

    final msgId = '${attachmentKind}_${DateTime.now().millisecondsSinceEpoch}';
    final outMsg = Message(
      id: msgId,
      isMe: true,
      type: attachmentKind == 'voice' ? MsgType.voice : MsgType.file,
      fileName: name,
      fileExt: ext,
      fileSize: size,
      filePath: filePath,
      voiceDuration: voiceDuration,
      time: DateTime.now(),
      delivered: false,
    );

    _messages.putIfAbsent(chatId, () => []);
    _messages[chatId]!.add(outMsg);
    DatabaseService.instance.insertMessage(chatId, outMsg);

    final candidate = _PendingAttachmentCandidate(
      chatId: chatId,
      msgId: msgId,
      fileName: name,
      fileSize: size,
      attachmentKind: attachmentKind,
      voiceDuration: voiceDuration,
      expectedTransfers: groupId != null && groupId.isNotEmpty
          ? _expectedGroupTransferCount(groupId)
          : 1,
    );
    _registerPendingAttachment(candidate);

    try {
      if (groupId != null && groupId.isNotEmpty) {
        if (attachmentKind == 'voice') {
          _node!.sendVoiceToGroup(
            groupId,
            filePath,
            durationSec: voiceDuration ?? 0,
          );
        } else {
          _node!.sendFileToGroup(groupId, filePath);
        }
      } else if (attachmentKind == 'voice') {
        _node!.sendVoice(
          toPeerId!,
          filePath,
          durationSec: voiceDuration ?? 0,
        );
      } else {
        _node!.sendFile(toPeerId!, filePath);
      }
    } catch (e) {
      _removePendingAttachment(candidate);
      LogService.instance.error('[PiperService] sendAttachment error: $e');
      _emitAttachmentError(chatId, attachmentKind);
    }

    notifyListeners();
  }

  int _expectedGroupTransferCount(String groupId) {
    final group = _groups.where((item) => item.id == groupId).firstOrNull;
    if (group == null) return 1;
    final count = group.members.where((memberId) => memberId != myId).length;
    return count > 0 ? count : 1;
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

  String _chatPreviewText(Message? message, {required String emptyText}) {
    if (message == null) return emptyText;
    switch (message.type) {
      case MsgType.text:
        return message.text ?? '';
      case MsgType.image:
        return 'Фото';
      case MsgType.file:
        return message.fileName ?? 'Файл';
      case MsgType.voice:
        return 'Голосовое';
      case MsgType.call:
        return 'Звонок';
    }
  }

  MessageType _chatPreviewType(Message? message) {
    if (message == null) return MessageType.text;
    switch (message.type) {
      case MsgType.text:
        return MessageType.text;
      case MsgType.image:
        return MessageType.photo;
      case MsgType.file:
        return MessageType.file;
      case MsgType.voice:
        return MessageType.voice;
      case MsgType.call:
        return MessageType.call;
    }
  }

  List<Contact> get contacts => _peers
      .map((p) => Contact(
            id: p.id,
            name: p.displayName,
            avatarStyle: avatarStyleForPeer(p.id),
            initials: initialsFor(p.displayName),
            isOnline: p.isConnected,
            address: p.isRelay
                ? 'via ${p.relayPeerName ?? 'relay'}'
                : (p.id.length > 12 ? '${p.id.substring(0, 12)}…' : p.id),
            isRelay: p.isRelay,
            relayPeerName: p.relayPeerName,
          ))
      .toList();

  /// Returns the mesh topology data for the graph widget.
  Map<String, dynamic> get topology =>
      _node?.getTopology() ?? {'nodes': [], 'edges': []};

  List<Chat> get chats {
    final result = <Chat>[];

    // ── Global chat (always shown) ────────────────────────────────────────────
    final globalMsgs = _messages['global'] ?? [];
    final globalLastMessage = globalMsgs.isNotEmpty ? globalMsgs.last : null;
    final onlinePeers = _peers.where((p) => p.isConnected).length;
    result.add(Chat(
      id: 'global',
      name: 'Общий чат',
      lastMessage: _chatPreviewText(
        globalLastMessage,
        emptyText: 'Переписка со всеми в сети',
      ),
      lastMessageTime: globalLastMessage?.time ?? DateTime.now(),
      unreadCount: _unreadCounts['global'] ?? 0,
      isGroup: true,
      avatarStyle: AvatarStyle.emerald,
      initials: '#',
      isOnline: onlinePeers > 0,
      lastMessageType: _chatPreviewType(globalLastMessage),
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

      final lastMessage = msgs.last;
      result.add(Chat(
        id: peerId,
        name: name,
        lastMessage: _chatPreviewText(lastMessage, emptyText: ''),
        lastMessageTime: lastMessage.time,
        unreadCount: _unreadCounts[peerId] ?? 0,
        isGroup: false,
        avatarStyle: avatarStyleForPeer(peerId),
        initials: initialsFor(name),
        isOnline: livePeer?.isConnected ?? false,
        lastMessageType: _chatPreviewType(lastMessage),
      ));
    }

    // ── Group chats ───────────────────────────────────────────────────────────
    for (final g in _groups) {
      final chatId = 'group:${g.id}';
      final msgs = _messages[chatId] ?? [];
      final lastMessage = msgs.isNotEmpty ? msgs.last : null;
      result.add(Chat(
        id: chatId,
        name: g.name,
        lastMessage: _chatPreviewText(lastMessage, emptyText: ''),
        lastMessageTime: lastMessage?.time ?? DateTime.now(),
        unreadCount: _unreadCounts[chatId] ?? 0,
        isGroup: true,
        avatarStyle: AvatarStyle.indigo,
        initials: initialsFor(g.name),
        isOnline: false,
        lastMessageType: _chatPreviewType(lastMessage),
        memberCount: g.members.length,
      ));
    }

    return result;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _sub?.cancel();
    _userErrors.close();
    _node?.stop();
    super.dispose();
  }
}
