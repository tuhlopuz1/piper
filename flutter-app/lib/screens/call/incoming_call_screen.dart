import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../widgets/app_avatar.dart';
import 'voice_call_screen.dart';

class IncomingCallScreen extends StatelessWidget {
  final Chat chat;
  final bool isVideo;

  const IncomingCallScreen({
    super.key,
    required this.chat,
    this.isVideo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              chat.avatarStyle.color.withValues(alpha: 0.35),
              AppColors.bgBase,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),

              // ── Caller info ───────────────────────────────────────────────
              AppAvatar(
                style: chat.avatarStyle,
                initials: chat.initials,
                size: 110,
                isGroup: chat.isGroup,
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(end: 1.05, duration: 1600.ms, curve: Curves.easeInOut),

              const SizedBox(height: 24),

              Text(
                chat.name,
                style: GoogleFonts.inter(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                isVideo ? 'Входящий видеозвонок...' : 'Входящий звонок...',
                style: GoogleFonts.inter(fontSize: 15, color: AppColors.mutedForeground),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fadeIn(duration: 800.ms)
                  .then()
                  .fadeOut(duration: 800.ms),

              const Spacer(),

              // ── Action buttons ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Decline
                    _RingButton(
                      icon: Icons.call_end_rounded,
                      color: AppColors.destructive,
                      label: 'Отклонить',
                      onTap: () => Navigator.pop(context),
                    ),

                    // Accept
                    _RingButton(
                      icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      color: AppColors.online,
                      label: 'Принять',
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VoiceCallScreen(chat: chat),
                          ),
                        );
                      },
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

class _RingButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _RingButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  State<_RingButton> createState() => _RingButtonState();
}

class _RingButtonState extends State<_RingButton> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulse ring 1
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.15),
                ),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .scale(
                    begin: const Offset(0.8, 0.8),
                    end: const Offset(1.3, 1.3),
                    duration: 1200.ms,
                    curve: Curves.easeOut,
                  )
                  .fadeOut(duration: 1200.ms),

              // Pulse ring 2
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.15),
                ),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .scale(
                    begin: const Offset(0.8, 0.8),
                    end: const Offset(1.3, 1.3),
                    duration: 1200.ms,
                    delay: 400.ms,
                    curve: Curves.easeOut,
                  )
                  .fadeOut(duration: 1200.ms, delay: 400.ms),

              // Button
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                child: Icon(widget.icon, color: Colors.white, size: 30),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.label,
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.mutedForeground),
        ),
      ],
    );
  }
}
