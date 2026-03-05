import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/call_service.dart';

/// Bottom sheet for switching audio/video devices during a call.
/// Mobile: shows speaker / earpiece / bluetooth.
/// Desktop: shows mic, speaker, camera dropdowns.
Future<void> showCallDeviceSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CallDeviceSheet(),
  );
}

class _CallDeviceSheet extends StatefulWidget {
  const _CallDeviceSheet();

  @override
  State<_CallDeviceSheet> createState() => _CallDeviceSheetState();
}

class _CallDeviceSheetState extends State<_CallDeviceSheet> {
  List<MediaDeviceInfo> _mics = [];
  List<MediaDeviceInfo> _speakers = [];
  List<MediaDeviceInfo> _cameras = [];
  bool _loading = true;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cs = CallService.instance;
    _mics = await cs.getAudioInputs();
    _speakers = await cs.getAudioOutputs();
    if (cs.isVideoCall) {
      _cameras = await cs.getVideoInputs();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = CallService.instance;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSubtle,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.muted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Устройства',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.foreground,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else if (_isDesktop)
            _buildDesktop(cs)
          else
            _buildMobile(cs),
        ],
      ),
    );
  }

  Widget _buildMobile(CallService cs) {
    // Mobile: simple speaker toggle + bluetooth (if available)
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DeviceTile(
          icon: Icons.phone_in_talk_rounded,
          label: 'Динамик телефона',
          selected: !cs.isSpeakerOn,
          onTap: () {
            if (cs.isSpeakerOn) cs.toggleSpeaker();
            Navigator.pop(context);
          },
        ),
        _DeviceTile(
          icon: Icons.volume_up_rounded,
          label: 'Громкая связь',
          selected: cs.isSpeakerOn,
          onTap: () {
            if (!cs.isSpeakerOn) cs.toggleSpeaker();
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  Widget _buildDesktop(CallService cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_mics.isNotEmpty) ...[
          _SectionHeader(icon: Icons.mic_none_rounded, label: 'Микрофон'),
          ..._mics.map((d) => _DeviceTile(
                icon: Icons.mic_none_rounded,
                label: d.label.isNotEmpty ? d.label : 'Микрофон',
                selected: cs.selectedMicId == d.deviceId ||
                    (cs.selectedMicId == null && _mics.first == d),
                onTap: () {
                  cs.setMicrophone(d.deviceId);
                  Navigator.pop(context);
                },
              )),
          const SizedBox(height: 12),
        ],
        if (_speakers.isNotEmpty) ...[
          _SectionHeader(icon: Icons.volume_up_rounded, label: 'Динамик'),
          ..._speakers.map((d) => _DeviceTile(
                icon: Icons.volume_up_rounded,
                label: d.label.isNotEmpty ? d.label : 'Динамик',
                selected: cs.selectedSpeakerId == d.deviceId ||
                    (cs.selectedSpeakerId == null && _speakers.first == d),
                onTap: () {
                  cs.setAudioOutput(d.deviceId);
                  Navigator.pop(context);
                },
              )),
          const SizedBox(height: 12),
        ],
        if (_cameras.isNotEmpty) ...[
          _SectionHeader(icon: Icons.videocam_outlined, label: 'Камера'),
          ..._cameras.map((d) => _DeviceTile(
                icon: Icons.videocam_outlined,
                label: d.label.isNotEmpty ? d.label : 'Камера',
                selected: cs.selectedCameraId == d.deviceId ||
                    (cs.selectedCameraId == null && _cameras.first == d),
                onTap: () {
                  cs.setCamera(d.deviceId);
                  Navigator.pop(context);
                },
              )),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.primaryLight),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.mutedForeground,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DeviceTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.primary : AppColors.foreground,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, color: AppColors.primary, size: 18),
          ],
        ),
      ),
    );
  }
}
