import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../widgets/app_avatar.dart';

class VideoCallScreen extends StatefulWidget {
  final Chat chat;
  const VideoCallScreen({super.key, required this.chat});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  bool _muted = false;
  bool _cameraOff = false;
  Offset _pipOffset = const Offset(16, 100);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Remote video (full screen placeholder) ────────────────────────
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.chat.avatarStyle.color.withValues(alpha: 0.6),
                  Colors.black,
                ],
              ),
            ),
            child: Center(
              child: AppAvatar(
                style: widget.chat.avatarStyle,
                initials: widget.chat.initials,
                size: 110,
                isGroup: widget.chat.isGroup,
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(end: 1.03, duration: 2000.ms, curve: Curves.easeInOut),
            ),
          ),

          // ── Top overlay ───────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Text(
                  widget.chat.name,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Видеозвонок',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),

          // ── Draggable PiP (own camera) ────────────────────────────────────
          Positioned(
            left: _pipOffset.dx,
            top: _pipOffset.dy,
            child: GestureDetector(
              onPanUpdate: (d) {
                setState(() {
                  _pipOffset = Offset(
                    (_pipOffset.dx + d.delta.dx).clamp(8, size.width - 108),
                    (_pipOffset.dy + d.delta.dy).clamp(8, size.height - 168),
                  );
                });
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 100,
                  height: 160,
                  color: _cameraOff ? Colors.grey.shade900 : AppColors.primary.withValues(alpha: 0.5),
                  child: _cameraOff
                      ? const Center(child: Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 28))
                      : Center(
                          child: Text(
                            'ME',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),

          // ── Bottom controls ───────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(32, 20, 32, MediaQuery.of(context).padding.bottom + 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _VideoButton(
                    icon: _muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                    active: _muted,
                    onTap: () => setState(() => _muted = !_muted),
                  ),
                  _VideoButton(
                    icon: Icons.call_end_rounded,
                    isEnd: true,
                    onTap: () => Navigator.pop(context),
                  ),
                  _VideoButton(
                    icon: _cameraOff ? Icons.videocam_off_outlined : Icons.videocam_outlined,
                    active: _cameraOff,
                    onTap: () => setState(() => _cameraOff = !_cameraOff),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final bool isEnd;
  final VoidCallback onTap;

  const _VideoButton({
    required this.icon,
    this.active = false,
    this.isEnd = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isEnd ? 64 : 54,
        height: isEnd ? 64 : 54,
        decoration: BoxDecoration(
          color: isEnd
              ? AppColors.destructive
              : active
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: isEnd ? 30 : 24,
        ),
      ),
    );
  }
}
