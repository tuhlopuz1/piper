import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../services/call_service.dart';
import '../../../services/piper_service.dart';
import '../../../widgets/app_avatar.dart';
import '../../call/voice_call_screen.dart';
import '../../call/video_call_screen.dart';

class CallsTab extends StatelessWidget {
  const CallsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<PiperService>();
    final calls = svc.callHistory;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: CustomScrollView(
        slivers: [
          _buildHeader(context),
          _buildSectionLabel(calls.length),
          if (calls.isEmpty) _buildEmpty() else _buildList(context, svc, calls),
          const SliverToBoxAdapter(child: SizedBox(height: 88)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildHeader(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, top + 16, 20, 12),
        child: Text(
          'Звонки',
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.foreground,
            letterSpacing: -1,
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildSectionLabel(int count) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Text(
          'ИСТОРИЯ · $count',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.mutedForeground,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildEmpty() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
        child: Column(
          children: [
            Icon(Icons.phone_outlined,
                size: 48, color: AppColors.mutedForeground.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              'Нет звонков',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Здесь будет отображаться история ваших звонков',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.mutedForeground.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverList _buildList(
      BuildContext context, PiperService svc, List<CallRecord> calls) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) {
          final call = calls[i];
          return _CallItem(call: call, svc: svc)
              .animate()
              .fadeIn(duration: 200.ms)
              .slideX(begin: 0.04, end: 0, duration: 200.ms);
        },
        childCount: calls.length,
      ),
    );
  }
}

class _CallItem extends StatelessWidget {
  final CallRecord call;
  final PiperService svc;

  const _CallItem({required this.call, required this.svc});

  @override
  Widget build(BuildContext context) {
    final isMissed =
        !call.answered && call.direction == CallDirection.incoming;
    final avatarStyle = svc.avatarStyleForPeer(call.peerId);

    return GestureDetector(
      onTap: () async {
        await CallService.instance
            .startCall(call.peerId, call.peerName, call.isVideo);
        if (!context.mounted) return;
        if (CallService.instance.state == CallState.idle) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => call.isVideo
                ? const VideoCallScreen()
                : const VoiceCallScreen(),
          ),
        );
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            AppAvatar(
              style: avatarStyle,
              initials: svc.initialsFor(call.peerName),
              size: 46,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    call.peerName,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isMissed
                          ? AppColors.destructive
                          : AppColors.foreground,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        _directionIcon(call),
                        size: 14,
                        color: isMissed
                            ? AppColors.destructive
                            : AppColors.mutedForeground,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _subtitle(call),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isMissed
                              ? AppColors.destructive.withValues(alpha: 0.8)
                              : AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatTime(call.time),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  call.isVideo
                      ? Icons.videocam_outlined
                      : Icons.phone_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _directionIcon(CallRecord call) {
    if (!call.answered && call.direction == CallDirection.incoming) {
      return Icons.call_missed_rounded;
    }
    if (call.direction == CallDirection.incoming) {
      return Icons.call_received_rounded;
    }
    return Icons.call_made_rounded;
  }

  String _subtitle(CallRecord call) {
    final type = call.isVideo ? 'Видеозвонок' : 'Голосовой';
    if (!call.answered) {
      if (call.direction == CallDirection.incoming) {
        return '$type · Пропущенный';
      }
      return '$type · Отменён';
    }
    return '$type · ${_formatDuration(call.durationSeconds)}';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}с';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m < 60) return '${m}м ${s}с';
    final h = m ~/ 60;
    return '${h}ч ${m % 60}м';
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (d == today) return time;
    if (d == today.subtract(const Duration(days: 1))) return 'Вчера, $time';
    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}, $time';
  }
}
