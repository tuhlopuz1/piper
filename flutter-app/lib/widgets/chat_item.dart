import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/chat.dart';
import 'app_avatar.dart';
import '../screens/chat/chat_screen.dart';

class ChatItem extends StatefulWidget {
  final Chat chat;
  const ChatItem({super.key, required this.chat});

  @override
  State<ChatItem> createState() => _ChatItemState();
}

class _ChatItemState extends State<ChatItem> {
  bool _pressed = false;

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays >= 1) {
      return '${time.day}.${time.month.toString().padLeft(2, '0')}';
    }
    return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  Widget _lastMessagePreview() {
    switch (widget.chat.lastMessageType) {
      case MessageType.photo:
        return _iconPreview(Icons.image_outlined, 'Фото');
      case MessageType.voice:
        return _iconPreview(Icons.mic_outlined, 'Голосовое');
      case MessageType.file:
        return _iconPreview(Icons.attach_file_rounded, 'Файл');
      case MessageType.call:
        return _iconPreview(Icons.call_outlined, 'Звонок');
      case MessageType.text:
        return Text(
          widget.chat.lastMessage,
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.mutedForeground),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
    }
  }

  Widget _iconPreview(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.mutedForeground),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.mutedForeground),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatScreen(chat: widget.chat)),
        );
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        color: _pressed ? AppColors.bgSubtle : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            // ── Avatar ──────────────────────────────────────────────────────
            Stack(
              children: [
                AppAvatar(
                  style: widget.chat.avatarStyle,
                  initials: widget.chat.initials,
                  isGroup: widget.chat.isGroup,
                  size: 50,
                ),
                if (widget.chat.isOnline && !widget.chat.isGroup)
                  Positioned(
                    bottom: 1,
                    right: 1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.bgBase, width: 2),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 12),

            // ── Content ─────────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + time
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.chat.name,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.foreground,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(widget.chat.lastMessageTime),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: widget.chat.unreadCount > 0
                              ? AppColors.primary
                              : AppColors.mutedForeground,
                          fontWeight: widget.chat.unreadCount > 0
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 3),

                  // Last message + badge
                  Row(
                    children: [
                      Expanded(child: _lastMessagePreview()),
                      if (widget.chat.unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            widget.chat.unreadCount > 99
                                ? '99+'
                                : '${widget.chat.unreadCount}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
