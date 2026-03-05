import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../services/call_service.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/call_device_sheet.dart';

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

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  Offset _pipOffset = const Offset(16, 100);

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

  bool get _isMobile =>
      !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    final cs = CallService.instance;
    final name = cs.peerName ?? '…';
    final avatarStyle = _avatarStyleForPeer(cs.peerId ?? '');
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Remote video (full screen) ─────────────────────────────────────
          // Always keep RTCVideoView in the tree so the Windows texture
          // renderer attaches before onTrack fires.
          Positioned.fill(
            child: RTCVideoView(
              cs.remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),

          // ── Connecting overlay (on top of video) ──────────────────────────
          if (cs.state != CallState.active)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      avatarStyle.color.withValues(alpha: 0.6),
                      Colors.black,
                    ],
                  ),
                ),
                child: Center(
                  child: AppAvatar(
                    style: avatarStyle,
                    initials: _initials(name),
                    size: 110,
                    isGroup: false,
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(
                          end: 1.03,
                          duration: 2000.ms,
                          curve: Curves.easeInOut),
                ),
              ),
            ),

          // ── Top overlay ────────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  cs.state == CallState.active
                      ? 'Видеозвонок'
                      : 'Соединяется...',
                  style:
                      GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),

          // ── Draggable PiP (local camera) ───────────────────────────────────
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
                child: SizedBox(
                  width: 100,
                  height: 160,
                  child: cs.isCameraOff
                      ? Container(
                          color: Colors.grey.shade900,
                          child: const Center(
                            child: Icon(Icons.videocam_off_outlined,
                                color: Colors.white54, size: 28),
                          ),
                        )
                      : RTCVideoView(
                          cs.localRenderer,
                          mirror: true,
                          objectFit: RTCVideoViewObjectFit
                              .RTCVideoViewObjectFitCover,
                        ),
                ),
              ),
            ),
          ),

          // ── Bottom controls ────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  32, 20, 32, MediaQuery.of(context).padding.bottom + 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _VideoButton(
                    icon: cs.isMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_none_rounded,
                    active: cs.isMuted,
                    onTap: () => cs.toggleMute(),
                  ),
                  if (_isMobile)
                    _VideoButton(
                      icon: Icons.flip_camera_ios_outlined,
                      onTap: () => cs.flipCamera(),
                    ),
                  _VideoButton(
                    icon: Icons.call_end_rounded,
                    isEnd: true,
                    onTap: () => cs.endCall(),
                  ),
                  _VideoButton(
                    icon: cs.isCameraOff
                        ? Icons.videocam_off_outlined
                        : Icons.videocam_outlined,
                    active: cs.isCameraOff,
                    onTap: () => cs.toggleCamera(),
                  ),
                  _VideoButton(
                    icon: Icons.surround_sound_rounded,
                    onTap: () => showCallDeviceSheet(context),
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
