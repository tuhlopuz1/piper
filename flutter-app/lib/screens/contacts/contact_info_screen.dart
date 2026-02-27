import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../widgets/app_avatar.dart';
import '../chat/chat_screen.dart';
import '../call/voice_call_screen.dart';
import '../call/video_call_screen.dart';

class ContactInfoScreen extends StatelessWidget {
  final Chat chat;

  const ContactInfoScreen({super.key, required this.chat});

  // Build a fake chat for use with VoiceCallScreen / VideoCallScreen
  Chat get _callChat => chat;

  List<Message> get _mediaMessages {
    final msgs = getMockMessages(chat);
    return msgs.where((m) => m.type == MsgType.image).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: CustomScrollView(
        slivers: [
          // ── Header ────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.of(context).padding.top + 8,
                20,
                32,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    chat.avatarStyle.color.withValues(alpha: 0.25),
                    AppColors.bgBase,
                  ],
                ),
              ),
              child: Column(
                children: [
                  // Back button
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                        color: AppColors.foreground,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded, size: 20),
                        color: AppColors.mutedForeground,
                        onPressed: () {},
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Avatar
                  AppAvatar(
                    style: chat.avatarStyle,
                    initials: chat.initials,
                    size: 88,
                    isGroup: chat.isGroup,
                  )
                      .animate()
                      .scale(
                        begin: const Offset(0.7, 0.7),
                        end: const Offset(1, 1),
                        duration: 500.ms,
                        curve: Curves.easeOutBack,
                      )
                      .fadeIn(duration: 400.ms),

                  const SizedBox(height: 14),

                  Text(
                    chat.name,
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground,
                      letterSpacing: -0.5,
                    ),
                  ).animate(delay: 80.ms).fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0, duration: 400.ms),

                  const SizedBox(height: 6),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: chat.isOnline ? AppColors.online : AppColors.border,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        chat.isOnline ? 'В сети' : 'Не в сети',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: chat.isOnline ? AppColors.online : AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ).animate(delay: 120.ms).fadeIn(duration: 400.ms),

                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ActionBtn(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Написать',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
                        ),
                      ),
                      const SizedBox(width: 20),
                      _ActionBtn(
                        icon: Icons.call_outlined,
                        label: 'Звонок',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => VoiceCallScreen(chat: _callChat)),
                        ),
                      ),
                      const SizedBox(width: 20),
                      _ActionBtn(
                        icon: Icons.videocam_outlined,
                        label: 'Видео',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => VideoCallScreen(chat: _callChat)),
                        ),
                      ),
                    ],
                  ).animate(delay: 160.ms).fadeIn(duration: 400.ms),
                ],
              ),
            ),
          ),

          // ── Info section ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    icon: Icons.lan_outlined,
                    label: 'IP-адрес',
                    value: '192.168.1.12',
                  ),
                  const SizedBox(height: 2),
                  _InfoRow(
                    icon: Icons.devices_outlined,
                    label: 'Устройство',
                    value: 'MacBook Pro',
                  ),
                  if (chat.isGroup) ...[
                    const SizedBox(height: 2),
                    _InfoRow(
                      icon: Icons.group_outlined,
                      label: 'Участников',
                      value: '${chat.memberCount}',
                    ),
                  ],
                ],
              ).animate(delay: 200.ms).fadeIn(duration: 380.ms),
            ),
          ),

          // ── Shared media ──────────────────────────────────────────────────
          if (_mediaMessages.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  'ОБЩИЕ МЕДИА',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedForeground,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _mediaMessages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final msg = _mediaMessages[i];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 100,
                        color: msg.imageColor ?? AppColors.primary,
                        child: Center(
                          child: Icon(
                            Icons.image_outlined,
                            color: Colors.white.withValues(alpha: 0.5),
                            size: 28,
                          ),
                        ),
                      ),
                    )
                        .animate(delay: Duration(milliseconds: 240 + i * 60))
                        .fadeIn(duration: 300.ms)
                        .scale(
                          begin: const Offset(0.85, 0.85),
                          end: const Offset(1, 1),
                          duration: 300.ms,
                          curve: Curves.easeOutBack,
                        );
                  },
                ),
              ),
            ),
          ],

          // ── Danger zone ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Column(
                children: [
                  _DangerItem(
                    icon: Icons.notifications_off_outlined,
                    label: 'Отключить уведомления',
                    onTap: () {},
                  ),
                  const SizedBox(height: 8),
                  _DangerItem(
                    icon: Icons.block_rounded,
                    label: 'Заблокировать',
                    onTap: () {},
                    red: true,
                  ),
                ],
              ).animate(delay: 280.ms).fadeIn(duration: 380.ms),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
            child: Icon(icon, color: AppColors.primaryLight, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.primaryLight),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.mutedForeground,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _DangerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool red;

  const _DangerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.red = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = red ? AppColors.destructive : AppColors.mutedForeground;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: red
              ? AppColors.destructive.withValues(alpha: 0.08)
              : AppColors.bgSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: red ? AppColors.destructive.withValues(alpha: 0.3) : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
