import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../widgets/app_avatar.dart';
import '../../services/call_manager.dart';

class VoiceCallScreen extends StatefulWidget {
  final Chat chat;
  const VoiceCallScreen({super.key, required this.chat});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  bool _muted = false;
  bool _speaker = false;
  int _seconds = 0;

  String get _timer {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              widget.chat.avatarStyle.color.withValues(alpha: 0.3),
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
                style: widget.chat.avatarStyle,
                initials: widget.chat.initials,
                size: 100,
                isGroup: widget.chat.isGroup,
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(end: 1.04, duration: 1800.ms, curve: Curves.easeInOut),

              const SizedBox(height: 20),

              Text(
                widget.chat.name,
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                _seconds > 0 ? _timer : 'Соединяется...',
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
                      icon: _muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                      label: _muted ? 'Вкл. мик.' : 'Выкл. мик.',
                      color: _muted ? AppColors.destructive : AppColors.bgSubtle,
                      iconColor: _muted ? Colors.white : AppColors.foreground,
                      onTap: () => setState(() => _muted = !_muted),
                    ),
                    _CallButton(
                      icon: Icons.call_end_rounded,
                      label: 'Завершить',
                      color: AppColors.destructive,
                      iconColor: Colors.white,
                      size: 68,
                      onTap: () {
                        CallManager.instance.endCall();
                        Navigator.pop(context);
                      },
                    ),
                    _CallButton(
                      icon: _speaker ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      label: _speaker ? 'Динамик вкл.' : 'Динамик выкл.',
                      color: _speaker ? AppColors.primary : AppColors.bgSubtle,
                      iconColor: _speaker ? Colors.white : AppColors.foreground,
                      onTap: () => setState(() => _speaker = !_speaker),
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

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final double size;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    this.size = 56,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: size * 0.42),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.mutedForeground),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
