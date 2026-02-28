import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class DeviceInfoScreen extends StatefulWidget {
  const DeviceInfoScreen({super.key});

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen> {
  String _hostname = '—';
  String _ip = '—';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final hostname = Platform.localHostname;
      String ip = '—';
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        if (iface.addresses.isNotEmpty) {
          ip = iface.addresses.first.address;
          break;
        }
      }
      if (mounted) {
        setState(() {
          _hostname = hostname;
          _ip = ip;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Скопировано',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              // ── App bar ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.bgSubtle,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border, width: 0.5),
                        ),
                        child: Icon(Icons.arrow_back_ios_new_rounded,
                            color: AppColors.foreground, size: 16),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Информация об устройстве',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.foreground,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Content ───────────────────────────────────────────────────
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2,
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                        children: [
                          // Section label
                          _SectionLabel('Сеть'),
                          const SizedBox(height: 8),

                          // Cards
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.bgSubtle,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: AppColors.border, width: 0.5),
                            ),
                            child: Column(
                              children: [
                                _InfoRow(
                                  icon: Icons.computer_rounded,
                                  label: 'Имя устройства',
                                  value: _hostname,
                                  onCopy: () => _copy(_hostname),
                                  showDivider: true,
                                ),
                                _InfoRow(
                                  icon: Icons.wifi_rounded,
                                  label: 'IP-адрес',
                                  value: _ip,
                                  onCopy: () => _copy(_ip),
                                  showDivider: false,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),
                          _SectionLabel('Piper'),
                          const SizedBox(height: 8),

                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.bgSubtle,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: AppColors.border, width: 0.5),
                            ),
                            child: Column(
                              children: [
                                _InfoRow(
                                  icon: Icons.router_rounded,
                                  label: 'Протокол',
                                  value: 'LAN / mDNS',
                                  showDivider: true,
                                ),
                                _InfoRow(
                                  icon: Icons.lock_outline_rounded,
                                  label: 'Шифрование',
                                  value: 'End-to-End',
                                  showDivider: false,
                                ),
                              ],
                            ),
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

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.mutedForeground,
        letterSpacing: 0.9,
      ),
    );
  }
}

// ─── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onCopy;
  final bool showDivider;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onCopy,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: AppColors.primaryLight),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.foreground,
                  ),
                ),
              ),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.mutedForeground,
                ),
              ),
              if (onCopy != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onCopy,
                  child: Icon(Icons.copy_rounded,
                      size: 15, color: AppColors.mutedForeground),
                ),
              ],
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 0, indent: 52, thickness: 0.5),
      ],
    );
  }
}
