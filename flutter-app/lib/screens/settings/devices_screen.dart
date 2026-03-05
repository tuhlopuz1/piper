import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/call_service.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<MediaDeviceInfo> _audioInputs = [];
  List<MediaDeviceInfo> _audioOutputs = [];
  List<MediaDeviceInfo> _videoInputs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cs = CallService.instance;
    final mic = await cs.getAudioInputs();
    final spk = await cs.getAudioOutputs();
    final cam = await cs.getVideoInputs();
    if (!mounted) return;
    setState(() {
      _audioInputs = mic;
      _audioOutputs = spk;
      _videoInputs = cam;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final cs = CallService.instance;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, top + 16, 20, 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        color: AppColors.foreground, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Устройства для звонков',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.foreground,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _DeviceSection(
                      icon: Icons.mic_none_rounded,
                      title: 'Микрофон',
                      devices: _audioInputs,
                      selected: cs.selectedMicId,
                      onSelect: (id) async {
                        await cs.saveDevicePreferences(micId: id);
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 20),
                    _DeviceSection(
                      icon: Icons.volume_up_rounded,
                      title: 'Динамик',
                      devices: _audioOutputs,
                      selected: cs.selectedSpeakerId,
                      onSelect: (id) async {
                        await cs.saveDevicePreferences(speakerId: id);
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 20),
                    _DeviceSection(
                      icon: Icons.videocam_outlined,
                      title: 'Камера',
                      devices: _videoInputs,
                      selected: cs.selectedCameraId,
                      onSelect: (id) async {
                        await cs.saveDevicePreferences(cameraId: id);
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<MediaDeviceInfo> devices;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _DeviceSection({
    required this.icon,
    required this.title,
    required this.devices,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primaryLight),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mutedForeground,
                  letterSpacing: 0.9,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSubtle,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: devices.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Text(
                    'Устройства не найдены',
                    style: GoogleFonts.inter(
                        fontSize: 14, color: AppColors.mutedForeground),
                  ),
                )
              : Column(
                  children: devices.indexed.map((entry) {
                    final (i, device) = entry;
                    final isSelected = selected == device.deviceId ||
                        (selected == null && i == 0);
                    return Column(
                      children: [
                        GestureDetector(
                          onTap: () => onSelect(device.deviceId),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    device.label.isNotEmpty
                                        ? device.label
                                        : 'Устройство ${i + 1}',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.foreground,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(Icons.check_rounded,
                                      color: AppColors.primary, size: 18),
                              ],
                            ),
                          ),
                        ),
                        if (i < devices.length - 1)
                          const Divider(height: 0, thickness: 0.5),
                      ],
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}
