import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../services/call_service.dart';
import '../../widgets/app_avatar.dart';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({super.key});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  @override
  void initState() {
    super.initState();
    CallService.instance.addListener(_onCallState);
  }

  @override
  void dispose() {
    CallService.instance.removeListener(_onCallState);
    super.dispose();
  }

  void _onCallState() {
    if (CallService.instance.state == CallState.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });
    } else {
      if (mounted) setState(() {});
    }
  }

  String get _timer {
    final s = CallService.instance.callDurationSeconds;
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = CallService.instance;
    final name = cs.peerName ?? '…';
    final avatarStyle = _avatarStyleForPeer(cs.peerId ?? '');
    final initials = _initials(name);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              avatarStyle.color.withValues(alpha: 0.3),
              AppColors.bgBase,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Top bar ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Голосовой звонок',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // ── Avatar + info ─────────────────────────────────────────────
              AppAvatar(
                style: avatarStyle,
                initials: initials,
                size: 100,
                isGroup: false,
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(end: 1.04, duration: 1800.ms, curve: Curves.easeInOut),

              const SizedBox(height: 20),

              Text(
                name,
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                cs.state == CallState.active ? _timer : 'Соединяется...',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppColors.mutedForeground,
                ),
              ).animate(onPlay: (c) => c.repeat()).shimmer(
                    duration: 1800.ms,
                    color: AppColors.primaryLight.withValues(alpha: 0.6),
                  ),

              const Spacer(),

              // ── Controls ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallButton(
                      icon: cs.isMuted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                      color: cs.isMuted ? AppColors.destructive : AppColors.bgSubtle,
                      iconColor: cs.isMuted ? Colors.white : AppColors.foreground,
                      onTap: () => cs.toggleMute(),
                    ),
                    _CallButton(
                      icon: Icons.call_end_rounded,
                      color: AppColors.destructive,
                      iconColor: Colors.white,
                      size: 68,
                      onTap: () {
                        cs.endCall();
                        // _onCallState will pop when state → idle
                      },
                    ),
                    _CallButton(
                      icon: cs.isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      color: cs.isSpeakerOn ? AppColors.primary : AppColors.bgSubtle,
                      iconColor: cs.isSpeakerOn ? Colors.white : AppColors.foreground,
                      onTap: () => cs.toggleSpeaker(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

AvatarStyle _avatarStyleForPeer(String peerId) {
  if (peerId.isEmpty) return AvatarStyle.violet;
  final hash = peerId.codeUnits.fold(0, (a, b) => a + b);
  return AvatarStyle.values[hash % AvatarStyle.values.length];
}

String _initials(String name) {
  if (name.isEmpty) return '?';
  final parts = name.trim().split(' ');
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final double size;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.color,
    required this.iconColor,
    this.size = 56,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: iconColor, size: size * 0.42),
      ),
    );
  }
}
