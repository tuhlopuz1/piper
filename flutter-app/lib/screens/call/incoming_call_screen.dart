import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../services/call_service.dart';
import '../../widgets/app_avatar.dart';
import 'voice_call_screen.dart';
import 'video_call_screen.dart';

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

class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final String peerId;
  final String peerName;
  final bool isVideo;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.peerId,
    required this.peerName,
    this.isVideo = false,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  bool _actionLocked = false;

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
    final cs = CallService.instance;
    final sameCall = cs.currentCallId == widget.callId;
    if (!sameCall || cs.state == CallState.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarStyle = _avatarStyleForPeer(widget.peerId);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              avatarStyle.color.withValues(alpha: 0.35),
              AppColors.bgBase,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              AppAvatar(
                style: avatarStyle,
                initials: _initials(widget.peerName),
                size: 110,
                isGroup: false,
              ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(
                  end: 1.05, duration: 1600.ms, curve: Curves.easeInOut),
              const SizedBox(height: 24),
              Text(
                widget.peerName,
                style: GoogleFonts.inter(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.isVideo
                    ? 'Входящий видеозвонок...'
                    : 'Входящий звонок...',
                style: GoogleFonts.inter(
                    fontSize: 15, color: AppColors.mutedForeground),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fadeIn(duration: 800.ms)
                  .then()
                  .fadeOut(duration: 800.ms),
              const Spacer(),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RingButton(
                      icon: Icons.call_end_rounded,
                      color: AppColors.destructive,
                      label: 'Отклонить',
                      onTap: _actionLocked
                          ? null
                          : () async {
                              setState(() => _actionLocked = true);
                              await CallService.instance.rejectCall();
                              if (!context.mounted) return;
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              }
                            },
                    ),
                    _RingButton(
                      icon: widget.isVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      color: AppColors.online,
                      label: 'Принять',
                      onTap: _actionLocked
                          ? null
                          : () async {
                              setState(() => _actionLocked = true);
                              await CallService.instance.acceptCall();
                              if (!context.mounted) return;
                              if (CallService.instance.state ==
                                  CallState.idle) {
                                if (Navigator.of(context).canPop()) {
                                  Navigator.of(context).pop();
                                }
                                return;
                              }
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => widget.isVideo
                                      ? const VideoCallScreen()
                                      : const VoiceCallScreen(),
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
  final VoidCallback? onTap;

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
    return Opacity(
      opacity: widget.onTap == null ? 0.6 : 1.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: widget.onTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
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
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                      color: widget.color, shape: BoxShape.circle),
                  child: Icon(widget.icon, color: Colors.white, size: 30),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.label,
            style: GoogleFonts.inter(
                fontSize: 13, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}
