import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
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
  late List<Message> _messages;
  bool _showAttach = false;
  bool _isRecording = false;
  int _recordSeconds = 0;

  @override
  void initState() {
    super.initState();
    _messages = getMockMessages(widget.chat);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _sendText() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(Message(
        id: 'new_${DateTime.now().millisecondsSinceEpoch}',
        isMe: true,
        type: MsgType.text,
        text: text,
        time: DateTime.now(),
        delivered: false,
      ));
      _textCtrl.clear();
      _showAttach = false;
    });
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

  void _startRecording() => setState(() => _isRecording = true);
  void _cancelRecording() => setState(() { _isRecording = false; _recordSeconds = 0; });
  void _sendVoice() {
    if (_recordSeconds == 0) { _cancelRecording(); return; }
    setState(() {
      _messages.add(Message(
        id: 'voice_${DateTime.now().millisecondsSinceEpoch}',
        isMe: true,
        type: MsgType.voice,
        voiceDuration: _recordSeconds,
        time: DateTime.now(),
        delivered: false,
      ));
      _isRecording = false;
      _recordSeconds = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Column(
        children: [
          _ChatAppBar(chat: widget.chat),
          Expanded(
            child: _MessageList(
              messages: _messages,
              scrollCtrl: _scrollCtrl,
              chat: widget.chat,
            ),
          ),
          if (_isRecording)
            _VoiceRecordingBar(
              seconds: _recordSeconds,
              onCancel: _cancelRecording,
              onSend: _sendVoice,
            )
          else
            _InputBar(
              controller: _textCtrl,
              showAttach: _showAttach,
              onAttachToggle: () => setState(() => _showAttach = !_showAttach),
              onSend: _sendText,
              onMicStart: _startRecording,
            ),
          if (_showAttach) _AttachPanel(onClose: () => setState(() => _showAttach = false)),
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
                MaterialPageRoute(builder: (_) => ContactInfoScreen(chat: chat)),
              ),
              child: Row(
                children: [
                  AppAvatar(style: chat.avatarStyle, initials: chat.initials, size: 38, isGroup: chat.isGroup),
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
                          'В сети',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.online),
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
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => VoiceCallScreen(chat: chat),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined, size: 22),
            color: AppColors.mutedForeground,
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => VideoCallScreen(chat: chat),
            )),
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

  const _MessageList({
    required this.messages,
    required this.scrollCtrl,
    required this.chat,
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
            _MessageBubble(message: msg, chat: chat)
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
    return '${date.day}.${date.month.toString().padLeft(2,'0')}.${date.year}';
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
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.mutedForeground),
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

  const _MessageBubble({required this.message, required this.chat});

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
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
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
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                  _BubbleContent(message: message),
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
  const _BubbleContent({required this.message});

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
        content = _TextContent(message: message, bg: bg, fg: fg, radius: radius);
      case MsgType.image:
        content = _ImageContent(message: message, radius: radius);
      case MsgType.file:
        content = _FileContent(message: message, bg: bg, fg: fg, radius: radius);
      case MsgType.voice:
        content = _VoiceContent(message: message, bg: bg, fg: fg, radius: radius);
    }

    return content;
  }
}

class _TextContent extends StatelessWidget {
  final Message message;
  final Color bg, fg;
  final BorderRadius radius;
  const _TextContent({required this.message, required this.bg, required this.fg, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(message.text ?? '', style: GoogleFonts.inter(fontSize: 14, color: fg, height: 1.4)),
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
                  child: Icon(Icons.image_outlined, size: 40, color: Colors.white.withValues(alpha: 0.5)),
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
  const _FileContent({required this.message, required this.bg, required this.fg, required this.radius});

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                (message.fileExt ?? 'file').toUpperCase(),
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
                        style: GoogleFonts.inter(fontSize: 11, color: fg.withValues(alpha: 0.6)),
                      ),
                    const Spacer(),
                    _TimeRow(message: message, fg: fg.withValues(alpha: 0.6)),
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

class _VoiceContent extends StatefulWidget {
  final Message message;
  final Color bg, fg;
  final BorderRadius radius;
  const _VoiceContent({required this.message, required this.bg, required this.fg, required this.radius});

  @override
  State<_VoiceContent> createState() => _VoiceContentState();
}

class _VoiceContentState extends State<_VoiceContent> {
  bool _playing = false;
  double _progress = 0;

  String _fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: widget.bg, borderRadius: widget.radius),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _playing = !_playing),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.fg.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: widget.fg,
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
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: widget.fg,
                    inactiveTrackColor: widget.fg.withValues(alpha: 0.25),
                    thumbColor: widget.fg,
                  ),
                  child: Slider(
                    value: _progress,
                    onChanged: (v) => setState(() => _progress = v),
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _fmt(widget.message.voiceDuration ?? 0),
                      style: GoogleFonts.inter(fontSize: 11, color: widget.fg.withValues(alpha: 0.6)),
                    ),
                    const Spacer(),
                    _TimeRow(message: widget.message, fg: widget.fg.withValues(alpha: 0.6)),
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

class _InputBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: AppColors.bgSubtle,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: AnimatedRotation(
              turns: showAttach ? 0.125 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.add_circle_outline_rounded),
            ),
            color: AppColors.mutedForeground,
            onPressed: onAttachToggle,
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
                controller: controller,
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.foreground),
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Сообщение...',
                  hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.mutedForeground),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (_, val, __) {
              final hasText = val.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: hasText ? onSend : onMicStart,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: hasText ? AppColors.primaryGradient : null,
                    color: hasText ? null : AppColors.bgBase,
                    shape: BoxShape.circle,
                    border: hasText ? null : Border.all(color: AppColors.border, width: 0.5),
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
  const _AttachPanel({required this.onClose});

  static const _items = [
    (Icons.image_outlined, 'Фото'),
    (Icons.folder_outlined, 'Файл'),
    (Icons.camera_alt_outlined, 'Камера'),
    (Icons.location_on_outlined, 'Геопозиция'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: AppColors.bgSubtle,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: _items.indexed.map((entry) {
          final (i, item) = entry;
          final (icon, label) = item;
          return _AttachItem(icon: icon, label: label)
              .animate(delay: Duration(milliseconds: i * 40))
              .fadeIn(duration: 200.ms)
              .scale(begin: const Offset(0.7, 0.7), end: const Offset(1, 1), duration: 200.ms, curve: Curves.easeOutBack);
        }).toList(),
      ),
    );
  }
}

class _AttachItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _AttachItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2), width: 0.5),
          ),
          child: Icon(icon, color: AppColors.primaryLight, size: 24),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: AppColors.mutedForeground),
        ),
      ],
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

  String _fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
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
              child: const Icon(Icons.delete_outline_rounded, color: AppColors.destructive, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
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
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
