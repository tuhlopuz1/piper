import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../services/call_service.dart';
import '../../services/piper_service.dart';
import '../../widgets/app_avatar.dart';
import '../call/voice_call_screen.dart';
import '../call/video_call_screen.dart';
import '../media/media_viewer_screen.dart';
import '../contacts/contact_info_screen.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  late List<Message> _messages;
  bool _showAttach = false;
  bool _isRecording = false;
  int _recordSeconds = 0;
  String? _recordingPath;
  Timer? _recordTimer;
  StreamSubscription<PiperUserError>? _userErrorSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _playerPositionSub;
  StreamSubscription<Duration>? _playerDurationSub;
  StreamSubscription<void>? _playerCompleteSub;
  PiperService? _svc;
  String? _playingMessageId;
  PlayerState _playerState = PlayerState.stopped;
  Duration _playerPosition = Duration.zero;
  Duration _playerDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _messages = getMockMessages(widget.chat);
    _svc = context.read<PiperService>();
    _userErrorSub = _svc!.userErrors.listen(_handleUserError);
    _initAudioPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _svc!.currentChatId = widget.chat.id;
      _svc!.markChatAsRead(widget.chat.id);
    });
  }

  @override
  void dispose() {
    _svc?.currentChatId = null;
    _userErrorSub?.cancel();
    _playerStateSub?.cancel();
    _playerPositionSub?.cancel();
    _playerDurationSub?.cancel();
    _playerCompleteSub?.cancel();
    _recordTimer?.cancel();
    unawaited(_recorder.cancel());
    unawaited(_recorder.dispose());
    unawaited(_audioPlayer.dispose());
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _sendText() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();

    final svc = context.read<PiperService>();
    if (svc.isRunning) {
      if (widget.chat.id == 'global') {
        // Broadcast to all peers
        svc.sendText(text);
      } else if (widget.chat.isGroup) {
        final groupId = widget.chat.id.replaceFirst('group:', '');
        svc.sendText(text, groupId: groupId);
      } else {
        svc.sendText(text, toPeerId: widget.chat.id);
      }
      setState(() => _showAttach = false);
    } else {
      // Demo / no-backend mode: update local state only.
      setState(() {
        _messages.add(Message(
          id: 'new_${DateTime.now().millisecondsSinceEpoch}',
          isMe: true,
          type: MsgType.text,
          text: text,
          time: DateTime.now(),
          delivered: false,
        ));
        _showAttach = false;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _handleUserError(PiperUserError error) {
    if (!mounted) return;
    if (error.chatId != null && error.chatId != widget.chat.id) return;
    _showSnackBar(error.message);
  }

  void _initAudioPlayer() {
    unawaited(_audioPlayer.setReleaseMode(ReleaseMode.stop));
    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _playerState = state;
        if (state == PlayerState.stopped && _playingMessageId == null) {
          _playerPosition = Duration.zero;
          _playerDuration = Duration.zero;
        }
      });
    });
    _playerPositionSub = _audioPlayer.onPositionChanged.listen((position) {
      if (!mounted || _playingMessageId == null) return;
      setState(() => _playerPosition = position);
    });
    _playerDurationSub = _audioPlayer.onDurationChanged.listen((duration) {
      if (!mounted || _playingMessageId == null) return;
      setState(() => _playerDuration = duration);
    });
    _playerCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playerState = PlayerState.completed;
        _playerPosition = _playerDuration;
        _playingMessageId = null;
      });
    });
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<bool> _ensureMicrophonePermission() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.microphone.request();
      return status.isGranted;
    }
    return true;
  }

  Future<String> _createVoiceRecordingPath() async {
    final supportDir = await getApplicationSupportDirectory();
    final recordingsDir = Directory(
      '${supportDir.path}${Platform.pathSeparator}voice-recordings',
    );
    await recordingsDir.create(recursive: true);
    return '${recordingsDir.path}${Platform.pathSeparator}'
        'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
  }

  Future<void> _deleteFileIfExists(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _pickAndSendFile({bool imageOnly = false}) async {
    setState(() => _showAttach = false);
    final result = await FilePicker.platform.pickFiles(
      type: imageOnly ? FileType.image : FileType.any,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    final svc = context.read<PiperService>();
    if (!svc.isRunning) return;

    final chatId = widget.chat.id;
    if (widget.chat.isGroup && chatId != 'global') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Отправка файлов в группы пока не поддерживается')),
      );
      return;
    }
    if (chatId == 'global') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Отправка файлов в общий чат не поддерживается')),
      );
      return;
    }

    svc.sendFile(chatId, file.path!);
  }

  Future<void> _startRecording() async {
    if (widget.chat.id == 'global') {
      _showSnackBar('Голосовые сообщения в общий чат не поддерживаются');
      return;
    }
    if (!await _ensureMicrophonePermission()) {
      _showSnackBar('Нет доступа к микрофону');
      return;
    }

    try {
      final path = await _createVoiceRecordingPath();
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
        ),
        path: path,
      );
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordSeconds += 1);
      });
      if (!mounted) return;
      setState(() {
        _showAttach = false;
        _isRecording = true;
        _recordSeconds = 0;
        _recordingPath = path;
      });
    } catch (e) {
      await _deleteFileIfExists(_recordingPath);
      if (!mounted) return;
      _showSnackBar('Не удалось начать запись');
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    _recordTimer = null;
    try {
      await _recorder.cancel();
    } catch (_) {}
    await _deleteFileIfExists(_recordingPath);
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _recordSeconds = 0;
      _recordingPath = null;
    });
  }

  Future<void> _sendVoice() async {
    if (_recordSeconds == 0) {
      await _cancelRecording();
      return;
    }

    _recordTimer?.cancel();
    _recordTimer = null;
    final durationSec = _recordSeconds;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    path ??= _recordingPath;

    if (path == null) {
      await _cancelRecording();
      return;
    }

    final resolvedPath = path;
    try {
      final file = File(resolvedPath);
      final size = await file.exists() ? await file.length() : 0;
      if (size <= 0) {
        await _deleteFileIfExists(resolvedPath);
        if (mounted) {
          setState(() {
            _isRecording = false;
            _recordSeconds = 0;
            _recordingPath = null;
          });
        }
        return;
      }

      final svc = _svc;
      if (svc == null) return;
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordSeconds = 0;
          _recordingPath = null;
        });
      }

      if (svc.isRunning) {
        if (widget.chat.isGroup) {
          svc.sendVoice(
            groupId: widget.chat.id.replaceFirst('group:', ''),
            filePath: resolvedPath,
            durationSec: durationSec,
          );
        } else {
          svc.sendVoice(
            toPeerId: widget.chat.id,
            filePath: resolvedPath,
            durationSec: durationSec,
          );
        }
      } else {
        setState(() {
          _messages.add(Message(
            id: 'voice_${DateTime.now().millisecondsSinceEpoch}',
            isMe: true,
            type: MsgType.voice,
            fileName: resolvedPath.split(Platform.pathSeparator).last,
            filePath: resolvedPath,
            voiceDuration: durationSec,
            time: DateTime.now(),
            delivered: false,
          ));
        });
      }
      _scrollToBottom();
    } catch (e) {
      await _deleteFileIfExists(resolvedPath);
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordSeconds = 0;
        _recordingPath = null;
      });
      _showSnackBar('Не удалось отправить голосовое сообщение');
    }
  }

  Future<void> _toggleVoicePlayback(Message message) async {
    final path = message.filePath;
    if (path == null || path.isEmpty) {
      _showSnackBar('Файл голосового сообщения не найден');
      return;
    }

    if (!await File(path).exists()) {
      _showSnackBar('Файл голосового сообщения не найден');
      return;
    }

    try {
      if (_playingMessageId == message.id) {
        if (_playerState == PlayerState.playing) {
          await _audioPlayer.pause();
        } else if (_playerState == PlayerState.paused) {
          await _audioPlayer.resume();
        } else {
          await _audioPlayer.seek(Duration.zero);
          await _audioPlayer.resume();
        }
        return;
      }

      await _audioPlayer.stop();
      await _audioPlayer.setSourceDeviceFile(path, mimeType: 'audio/mp4');
      final duration = await _audioPlayer.getDuration() ??
          Duration(seconds: message.voiceDuration ?? 0);
      if (!mounted) return;
      setState(() {
        _playingMessageId = message.id;
        _playerPosition = Duration.zero;
        _playerDuration = duration;
      });
      await _audioPlayer.resume();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Не удалось воспроизвести голосовое сообщение');
    }
  }

  Future<void> _seekVoice(Message message, double value) async {
    if (_playingMessageId != message.id) return;
    final duration = _voiceDurationFor(message);
    final target = Duration(
      milliseconds: (duration.inMilliseconds * value).round(),
    );
    try {
      await _audioPlayer.seek(target);
      if (!mounted) return;
      setState(() => _playerPosition = target);
    } catch (_) {}
  }

  Duration _voiceDurationFor(Message message) {
    if (_playingMessageId == message.id && _playerDuration > Duration.zero) {
      return _playerDuration;
    }
    return Duration(seconds: message.voiceDuration ?? 0);
  }

  double _voiceProgressFor(Message message) {
    final duration = _voiceDurationFor(message);
    if (_playingMessageId != message.id || duration.inMilliseconds <= 0) {
      return 0;
    }
    final progress = _playerPosition.inMilliseconds / duration.inMilliseconds;
    return progress.clamp(0.0, 1.0);
  }

  bool _isPlayingMessage(Message message) {
    return _playingMessageId == message.id &&
        _playerState == PlayerState.playing;
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<PiperService>();
    final displayMessages =
        svc.isRunning ? (svc.messages[widget.chat.id] ?? []) : _messages;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Column(
        children: [
          _ChatAppBar(chat: widget.chat),
          Expanded(
            child: _MessageList(
              messages: displayMessages,
              scrollCtrl: _scrollCtrl,
              chat: widget.chat,
              playingMessageId: _playingMessageId,
              isPlaying: _isPlayingMessage,
              voiceProgressFor: _voiceProgressFor,
              voiceDurationFor: _voiceDurationFor,
              onVoiceToggle: _toggleVoicePlayback,
              onVoiceSeek: _seekVoice,
            ),
          ),
          if (_isRecording)
            _VoiceRecordingBar(
              seconds: _recordSeconds,
              onCancel: () => unawaited(_cancelRecording()),
              onSend: () => unawaited(_sendVoice()),
            )
          else
            _InputBar(
              controller: _textCtrl,
              showAttach: _showAttach,
              onAttachToggle: () => setState(() => _showAttach = !_showAttach),
              onSend: _sendText,
              onMicStart: () => unawaited(_startRecording()),
            ),
          if (_showAttach)
            _AttachPanel(
              onClose: () => setState(() => _showAttach = false),
              onFilePick: () => _pickAndSendFile(),
              onPhotoPick: () => _pickAndSendFile(imageOnly: true),
            ),
        ],
      ),
    );
  }
}

// ─── App Bar ──────────────────────────────────────────────────────────────────

class _ChatAppBar extends StatelessWidget {
  final Chat chat;
  const _ChatAppBar({required this.chat});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final svc = context.watch<PiperService>();

    final bool isOnline;
    final String statusText;
    if (chat.id == 'global') {
      final onlineCount = svc.peers.where((p) => p.isConnected).length;
      isOnline = onlineCount > 0;
      statusText = '${onlineCount + 1} участников';
    } else if (chat.isGroup) {
      isOnline = false;
      statusText = 'Группа';
    } else {
      final peer = svc.peers.where((p) => p.id == chat.id).firstOrNull;
      isOnline = peer?.isConnected ?? false;
      statusText = isOnline ? 'В сети' : 'Не в сети';
    }

    return Container(
      padding: EdgeInsets.fromLTRB(8, top + 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.bgSubtle,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            color: AppColors.foreground,
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ContactInfoScreen(chat: chat)),
              ),
              child: Row(
                children: [
                  AppAvatar(
                      style: chat.avatarStyle,
                      initials: chat.initials,
                      size: 38,
                      isGroup: chat.isGroup),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          chat.name,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.foreground,
                          ),
                        ),
                        Text(
                          statusText,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isOnline
                                ? AppColors.online
                                : AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.phone_outlined, size: 20),
            color: AppColors.mutedForeground,
            onPressed: () async {
              await CallService.instance.startCall(chat.id, chat.name, false);
              if (!context.mounted) return;
              if (CallService.instance.state == CallState.idle) return;
              Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const VoiceCallScreen(),
                  ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined, size: 22),
            color: AppColors.mutedForeground,
            onPressed: () async {
              await CallService.instance.startCall(chat.id, chat.name, true);
              if (!context.mounted) return;
              if (CallService.instance.state == CallState.idle) return;
              Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const VideoCallScreen(),
                  ));
            },
          ),
        ],
      ),
    );
  }
}

// ─── Message List ─────────────────────────────────────────────────────────────

class _MessageList extends StatelessWidget {
  final List<Message> messages;
  final ScrollController scrollCtrl;
  final Chat chat;
  final String? playingMessageId;
  final bool Function(Message message) isPlaying;
  final double Function(Message message) voiceProgressFor;
  final Duration Function(Message message) voiceDurationFor;
  final Future<void> Function(Message message) onVoiceToggle;
  final Future<void> Function(Message message, double value) onVoiceSeek;

  const _MessageList({
    required this.messages,
    required this.scrollCtrl,
    required this.chat,
    required this.playingMessageId,
    required this.isPlaying,
    required this.voiceProgressFor,
    required this.voiceDurationFor,
    required this.onVoiceToggle,
    required this.onVoiceSeek,
  });

  bool _showDate(int i) {
    if (i == messages.length - 1) return true;
    final curr = messages[messages.length - 1 - i];
    final prev = messages[messages.length - 2 - i];
    return !_sameDay(curr.time, prev.time);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollCtrl,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final msg = messages[messages.length - 1 - i];
        final showDate = _showDate(i);
        return Column(
          children: [
            if (showDate) _DateDivider(date: msg.time),
            _MessageBubble(
              message: msg,
              chat: chat,
              isVoicePlaying: isPlaying(msg),
              isVoiceActive: playingMessageId == msg.id,
              voiceProgress: voiceProgressFor(msg),
              voiceDuration: voiceDurationFor(msg),
              onVoiceToggle: () => onVoiceToggle(msg),
              onVoiceSeek: (value) => onVoiceSeek(msg, value),
            )
                .animate()
                .fadeIn(duration: 200.ms)
                .slideY(begin: 0.1, end: 0, duration: 200.ms),
          ],
        );
      },
    );
  }
}

class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Сегодня';
    if (d == today.subtract(const Duration(days: 1))) return 'Вчера';
    return '${date.day}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.border, thickness: 0.5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _label(),
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppColors.mutedForeground),
            ),
          ),
          Expanded(child: Divider(color: AppColors.border, thickness: 0.5)),
        ],
      ),
    );
  }
}

// ─── Message Bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final Message message;
  final Chat chat;
  final bool isVoicePlaying;
  final bool isVoiceActive;
  final double voiceProgress;
  final Duration voiceDuration;
  final Future<void> Function() onVoiceToggle;
  final Future<void> Function(double value) onVoiceSeek;

  const _MessageBubble({
    required this.message,
    required this.chat,
    required this.isVoicePlaying,
    required this.isVoiceActive,
    required this.voiceProgress,
    required this.voiceDuration,
    required this.onVoiceToggle,
    required this.onVoiceSeek,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final screenW = MediaQuery.sizeOf(context).width;
    final maxBubbleW = screenW > 600 ? screenW * 0.55 : double.infinity;
    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        bottom: 2,
        left: isMe ? 48 : 0,
        right: isMe ? 0 : 48,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe && chat.isGroup) ...[
            AppAvatar(
              style: _avatarStyleForColor(message.senderColor),
              initials: message.senderName?.substring(0, 1) ?? '?',
              size: 28,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleW),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe && chat.isGroup && message.senderName != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 3),
                      child: Text(
                        message.senderName!,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: message.senderColor ?? AppColors.primary,
                        ),
                      ),
                    ),
                  _BubbleContent(
                    message: message,
                    isVoicePlaying: isVoicePlaying,
                    isVoiceActive: isVoiceActive,
                    voiceProgress: voiceProgress,
                    voiceDuration: voiceDuration,
                    onVoiceToggle: onVoiceToggle,
                    onVoiceSeek: onVoiceSeek,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  AvatarStyle _avatarStyleForColor(Color? color) {
    if (color == null) return AvatarStyle.violet;
    for (final s in AvatarStyle.values) {
      if (s.color == color) return s;
    }
    return AvatarStyle.violet;
  }
}

class _BubbleContent extends StatelessWidget {
  final Message message;
  final bool isVoicePlaying;
  final bool isVoiceActive;
  final double voiceProgress;
  final Duration voiceDuration;
  final Future<void> Function() onVoiceToggle;
  final Future<void> Function(double value) onVoiceSeek;

  const _BubbleContent({
    required this.message,
    required this.isVoicePlaying,
    required this.isVoiceActive,
    required this.voiceProgress,
    required this.voiceDuration,
    required this.onVoiceToggle,
    required this.onVoiceSeek,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final bg = isMe ? AppColors.primary : AppColors.bgSubtle;
    final fg = isMe ? Colors.white : AppColors.foreground;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 16),
    );

    Widget content;
    switch (message.type) {
      case MsgType.text:
        content =
            _TextContent(message: message, bg: bg, fg: fg, radius: radius);
        break;
      case MsgType.image:
        content = _ImageContent(message: message, radius: radius);
        break;
      case MsgType.file:
        final progress =
            context.read<PiperService>().progressByMsgId[message.id];
        content = _FileContent(
            message: message,
            bg: bg,
            fg: fg,
            radius: radius,
            transferProgress: progress);
        break;
      case MsgType.voice:
        content = _VoiceContent(
          message: message,
          bg: bg,
          fg: fg,
          radius: radius,
          isPlaying: isVoicePlaying,
          isActive: isVoiceActive,
          progress: voiceProgress,
          duration: voiceDuration,
          onToggle: onVoiceToggle,
          onSeek: onVoiceSeek,
        );
        break;
      case MsgType.call:
        content =
            _CallContent(message: message, bg: bg, fg: fg, radius: radius);
        break;
    }

    return content;
  }
}

class _TextContent extends StatelessWidget {
  final Message message;
  final Color bg, fg;
  final BorderRadius radius;
  const _TextContent(
      {required this.message,
      required this.bg,
      required this.fg,
      required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(message.text ?? '',
              style: GoogleFonts.inter(fontSize: 14, color: fg, height: 1.4)),
          const SizedBox(height: 3),
          _TimeRow(message: message, fg: fg.withValues(alpha: 0.65)),
        ],
      ),
    );
  }
}

class _ImageContent extends StatelessWidget {
  final Message message;
  final BorderRadius radius;
  const _ImageContent({required this.message, required this.radius});

  @override
  Widget build(BuildContext context) {
    final color = message.imageColor ?? AppColors.primary;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MediaViewerScreen(color: color)),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: AspectRatio(
          aspectRatio: message.imageAspect,
          child: Container(
            color: color,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Center(
                  child: Icon(Icons.image_outlined,
                      size: 40, color: Colors.white.withValues(alpha: 0.5)),
                ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: _TimeRow(
                    message: message,
                    fg: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileContent extends StatelessWidget {
  final Message message;
  final Color bg, fg;
  final BorderRadius radius;
  final double?
      transferProgress; // null = not transferring, 0.0-1.0 = in progress

  const _FileContent({
    required this.message,
    required this.bg,
    required this.fg,
    required this.radius,
    this.transferProgress,
  });

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final canOpen = message.filePath != null && transferProgress == null;
    return GestureDetector(
      onTap: canOpen ? () => OpenFile.open(message.filePath!) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: transferProgress != null
                      ? Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              value: transferProgress,
                              strokeWidth: 2.5,
                              color: fg.withValues(alpha: 0.8),
                              backgroundColor: fg.withValues(alpha: 0.15),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            (message.fileExt ?? 'FILE').toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: fg.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.fileName ?? 'file',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: fg,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (message.fileSize != null)
                            Text(
                              _formatSize(message.fileSize!),
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: fg.withValues(alpha: 0.6)),
                            ),
                          const Spacer(),
                          _TimeRow(
                              message: message, fg: fg.withValues(alpha: 0.6)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (transferProgress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: transferProgress,
                  minHeight: 3,
                  color: fg.withValues(alpha: 0.75),
                  backgroundColor: fg.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${((transferProgress!) * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.inter(
                      fontSize: 10, color: fg.withValues(alpha: 0.55)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VoiceContent extends StatelessWidget {
  final Message message;
  final Color bg, fg;
  final BorderRadius radius;
  final bool isPlaying;
  final bool isActive;
  final double progress;
  final Duration duration;
  final Future<void> Function() onToggle;
  final Future<void> Function(double value) onSeek;

  const _VoiceContent({
    required this.message,
    required this.bg,
    required this.fg,
    required this.radius,
    required this.isPlaying,
    required this.isActive,
    required this.progress,
    required this.duration,
    required this.onToggle,
    required this.onSeek,
  });

  String _fmt(Duration value) {
    final seconds = value.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final effectiveDuration = duration.inMilliseconds > 0
        ? duration
        : Duration(seconds: message.voiceDuration ?? 0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => unawaited(onToggle()),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: fg,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: fg,
                    inactiveTrackColor: fg.withValues(alpha: 0.25),
                    thumbColor: fg,
                  ),
                  child: Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChanged: isActive && effectiveDuration.inMilliseconds > 0
                        ? (value) => unawaited(onSeek(value))
                        : null,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _fmt(effectiveDuration),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: fg.withValues(alpha: 0.6),
                      ),
                    ),
                    const Spacer(),
                    _TimeRow(
                      message: message,
                      fg: fg.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallContent extends StatelessWidget {
  final Message message;
  final Color bg, fg;
  final BorderRadius radius;
  const _CallContent(
      {required this.message,
      required this.bg,
      required this.fg,
      required this.radius});

  IconData _icon() {
    if (message.callResult == CallResult.missed)
      return Icons.call_missed_rounded;
    if (message.callResult == CallResult.rejected)
      return Icons.call_end_rounded;
    if (message.isMe) return Icons.call_made_rounded;
    return Icons.call_received_rounded;
  }

  String _label() {
    final type =
        (message.callIsVideo ?? false) ? 'Видеозвонок' : 'Голосовой звонок';
    if (message.callResult == CallResult.missed) return '$type · Пропущенный';
    if (message.callResult == CallResult.rejected) return '$type · Отклонён';
    final dur = message.callDuration ?? 0;
    if (dur < 60) return '$type · ${dur}с';
    final m = dur ~/ 60;
    final s = dur % 60;
    if (m < 60) return '$type · ${m}м ${s}с';
    final h = m ~/ 60;
    return '$type · ${h}ч ${m % 60}м';
  }

  @override
  Widget build(BuildContext context) {
    final isMissed = message.callResult == CallResult.missed ||
        message.callResult == CallResult.rejected;
    final iconColor = isMissed ? AppColors.destructive : fg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              (message.callIsVideo ?? false)
                  ? Icons.videocam_rounded
                  : Icons.phone_rounded,
              color: iconColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_icon(), size: 14, color: iconColor),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _label(),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isMissed ? AppColors.destructive : fg,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                _TimeRow(message: message, fg: fg.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  final Message message;
  final Color fg;
  const _TimeRow({required this.message, required this.fg});

  String _time() {
    final t = message.time;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_time(), style: GoogleFonts.inter(fontSize: 10, color: fg)),
        if (message.isMe) ...[
          const SizedBox(width: 3),
          Icon(
            message.delivered ? Icons.done_all_rounded : Icons.done_rounded,
            size: 12,
            color: message.delivered ? fg : fg.withValues(alpha: 0.6),
          ),
        ],
      ],
    );
  }
}

// ─── Input Bar ────────────────────────────────────────────────────────────────

class _InputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool showAttach;
  final VoidCallback onAttachToggle;
  final VoidCallback onSend;
  final VoidCallback onMicStart;

  const _InputBar({
    required this.controller,
    required this.showAttach,
    required this.onAttachToggle,
    required this.onSend,
    required this.onMicStart,
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.isShiftPressed) {
        widget.onSend();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: AppColors.bgSubtle,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: AnimatedRotation(
              turns: widget.showAttach ? 0.125 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.add_circle_outline_rounded),
            ),
            color: AppColors.mutedForeground,
            onPressed: widget.onAttachToggle,
          ),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: AppColors.bgBase,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                style: GoogleFonts.inter(
                    fontSize: 14, color: AppColors.foreground),
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Сообщение...',
                  hintStyle: GoogleFonts.inter(
                      fontSize: 14, color: AppColors.mutedForeground),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          ValueListenableBuilder(
            valueListenable: widget.controller,
            builder: (_, val, __) {
              final hasText = val.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: hasText ? widget.onSend : widget.onMicStart,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: hasText ? AppColors.primaryGradient : null,
                    color: hasText ? null : AppColors.bgBase,
                    shape: BoxShape.circle,
                    border: hasText
                        ? null
                        : Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Icon(
                    hasText ? Icons.send_rounded : Icons.mic_none_rounded,
                    size: 20,
                    color: hasText ? Colors.white : AppColors.mutedForeground,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Attach Panel ─────────────────────────────────────────────────────────────

class _AttachPanel extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onFilePick;
  final VoidCallback onPhotoPick;

  const _AttachPanel({
    required this.onClose,
    required this.onFilePick,
    required this.onPhotoPick,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.image_outlined, 'Фото', onPhotoPick),
      (Icons.folder_outlined, 'Файл', onFilePick),
      (Icons.camera_alt_outlined, 'Камера', null),
      (Icons.location_on_outlined, 'Геопозиция', null),
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: AppColors.bgSubtle,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.indexed.map((entry) {
          final (i, item) = entry;
          final (icon, label, onTap) = item;
          return _AttachItem(icon: icon, label: label, onTap: onTap)
              .animate(delay: Duration(milliseconds: i * 40))
              .fadeIn(duration: 200.ms)
              .scale(
                  begin: const Offset(0.7, 0.7),
                  end: const Offset(1, 1),
                  duration: 200.ms,
                  curve: Curves.easeOutBack);
        }).toList(),
      ),
    );
  }
}

class _AttachItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _AttachItem({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap != null ? 1.0 : 0.4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    width: 0.5),
              ),
              child: Icon(icon, color: AppColors.primaryLight, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppColors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Voice Recording Bar ──────────────────────────────────────────────────────

class _VoiceRecordingBar extends StatelessWidget {
  final int seconds;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const _VoiceRecordingBar({
    required this.seconds,
    required this.onCancel,
    required this.onSend,
  });

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: AppColors.bgSubtle,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onCancel,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.destructive.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.destructive, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 8,
            height: 8,
            decoration:
                const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(duration: 600.ms),
          const SizedBox(width: 8),
          Text(
            _fmt(seconds),
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.foreground,
            ),
          ),
          const SizedBox(width: 8),
          const Spacer(),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
