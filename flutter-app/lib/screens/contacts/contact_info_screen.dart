import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../services/piper_service.dart';
import '../../services/call_service.dart';
import '../../widgets/app_avatar.dart';
import '../chat/chat_screen.dart';
import '../call/voice_call_screen.dart';
import '../call/video_call_screen.dart';

class ContactInfoScreen extends StatelessWidget {
  final Chat chat;

  const ContactInfoScreen({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<PiperService>();

    // Resolve live peer data from the service.
    final peer = svc.peers.where((p) => p.id == chat.id).firstOrNull;
    final isOnline = peer?.isConnected ?? chat.isOnline;
    final displayName = peer?.displayName ?? chat.name;

    // Truncated peer ID for display.
    final shortId = chat.id.length > 16
        ? '${chat.id.substring(0, 8)}…${chat.id.substring(chat.id.length - 8)}'
        : chat.id;

    // Shared files from real message history.
    final chatMessages = svc.messages[chat.id] ?? [];
    final sharedFiles = chatMessages.where((m) => m.fileName != null).toList();

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
                    initials: svc.initialsFor(displayName),
                    size: 88,
                    isGroup: false,
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
                    displayName,
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
                          color: isOnline ? AppColors.online : AppColors.border,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isOnline ? 'В сети' : 'Не в сети',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: isOnline ? AppColors.online : AppColors.mutedForeground,
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
                        onTap: () async {
                          await CallService.instance.startCall(chat.id, chat.name, false);
                          if (!context.mounted) return;
                          if (CallService.instance.state == CallState.idle) return;
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const VoiceCallScreen(),
                          ));
                        },
                      ),
                      const SizedBox(width: 20),
                      _ActionBtn(
                        icon: Icons.videocam_outlined,
                        label: 'Видео',
                        onTap: () async {
                          await CallService.instance.startCall(chat.id, chat.name, true);
                          if (!context.mounted) return;
                          if (CallService.instance.state == CallState.idle) return;
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const VideoCallScreen(),
                          ));
                        },
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
                  GestureDetector(
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: chat.id));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ID скопирован')),
                      );
                    },
                    child: _InfoRow(
                      icon: Icons.fingerprint_rounded,
                      label: 'Peer ID',
                      value: shortId,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _InfoRow(
                    icon: Icons.circle,
                    label: 'Статус',
                    value: isOnline ? 'Подключён' : 'Отключён',
                    valueColor: isOnline ? AppColors.online : AppColors.mutedForeground,
                    iconColor: isOnline ? AppColors.online : AppColors.mutedForeground,
                    iconSize: 10,
                  ),
                ],
              ).animate(delay: 200.ms).fadeIn(duration: 380.ms),
            ),
          ),

          // ── Shared files ──────────────────────────────────────────────────
          if (sharedFiles.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  'ОБЩИЕ ФАЙЛЫ · ${sharedFiles.length}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedForeground,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final file = sharedFiles[i];
                  final sizeStr = file.fileSize != null
                      ? _formatFileSize(file.fileSize!)
                      : '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.bgSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                file.fileExt?.toUpperCase() ?? '?',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryLight,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  file.fileName ?? 'Файл',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.foreground,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (sizeStr.isNotEmpty)
                                  Text(
                                    sizeStr,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: AppColors.mutedForeground,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            file.isMe ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            size: 16,
                            color: AppColors.mutedForeground,
                          ),
                        ],
                      ),
                    ),
                  )
                      .animate(delay: Duration(milliseconds: 240 + i * 40))
                      .fadeIn(duration: 300.ms);
                },
                childCount: sharedFiles.length > 10 ? 10 : sharedFiles.length,
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
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
  final Color? valueColor;
  final Color? iconColor;
  final double? iconSize;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.iconColor,
    this.iconSize,
  });

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
          Icon(icon, size: iconSize ?? 17, color: iconColor ?? AppColors.primaryLight),
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
              color: valueColor ?? AppColors.foreground,
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
