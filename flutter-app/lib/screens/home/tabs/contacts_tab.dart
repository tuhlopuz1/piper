import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../models/chat.dart';
import '../../../services/peer_store.dart';
import '../../../widgets/app_avatar.dart';
import '../../contacts/contact_info_screen.dart';
import '../../chat/chat_screen.dart';
import '../../call/voice_call_screen.dart';
import '../../call/video_call_screen.dart';

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _radarCtrl;
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    PeerStore.instance.addListener(_onPeersChanged);
  }

  @override
  void dispose() {
    PeerStore.instance.removeListener(_onPeersChanged);
    _radarCtrl.dispose();
    super.dispose();
  }

  void _onPeersChanged() => setState(() {});

  void _refresh() {
    setState(() => _scanning = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  List<Contact> get _online => PeerStore.instance.peers;
  List<Contact> get _offline => const [];

  Chat _contactToChat(Contact c) => Chat(
        id: c.id,
        name: c.name,
        lastMessage: '',
        lastMessageTime: DateTime.now(),
        unreadCount: 0,
        isGroup: false,
        avatarStyle: c.avatarStyle,
        initials: c.initials,
        isOnline: c.isOnline,
        lastMessageType: MessageType.text,
      );

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        color: AppColors.primary,
        backgroundColor: AppColors.bgSubtle,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Header ─────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, top + 16, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Устройства',
                        style: GoogleFonts.inter(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.foreground,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    _ScanButton(scanning: _scanning, onTap: _refresh),
                  ],
                ),
              ),
            ),

            // ── Radar ───────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: _RadarWidget(
                    controller: _radarCtrl,
                    contacts: _online,
                  ),
                ),
              ),
            ),

            // ── Online section ──────────────────────────────────────────────
            if (_online.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionLabel(
                  label: 'В СЕТИ · ${_online.length}',
                  color: AppColors.online,
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _DeviceTile(
                    contact: _online[i],
                    onCall: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VoiceCallScreen(chat: _contactToChat(_online[i])),
                      ),
                    ),
                    onVideo: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoCallScreen(chat: _contactToChat(_online[i])),
                      ),
                    ),
                    onChat: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(chat: _contactToChat(_online[i])),
                      ),
                    ),
                    onInfo: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContactInfoScreen(chat: _contactToChat(_online[i])),
                      ),
                    ),
                  )
                      .animate(delay: Duration(milliseconds: i * 60))
                      .fadeIn(duration: 300.ms)
                      .slideX(begin: -0.05, end: 0, duration: 300.ms),
                  childCount: _online.length,
                ),
              ),
            ],

            // ── Offline section ─────────────────────────────────────────────
            if (_offline.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionLabel(label: 'НЕ В СЕТИ · ${_offline.length}'),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _DeviceTile(
                    contact: _offline[i],
                    dimmed: true,
                    onCall: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VoiceCallScreen(chat: _contactToChat(_offline[i])),
                      ),
                    ),
                    onVideo: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoCallScreen(chat: _contactToChat(_offline[i])),
                      ),
                    ),
                    onChat: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(chat: _contactToChat(_offline[i])),
                      ),
                    ),
                    onInfo: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContactInfoScreen(chat: _contactToChat(_offline[i])),
                      ),
                    ),
                  )
                      .animate(delay: Duration(milliseconds: i * 60))
                      .fadeIn(duration: 300.ms),
                  childCount: _offline.length,
                ),
              ),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

// ─── Radar Widget ─────────────────────────────────────────────────────────────

class _RadarWidget extends StatelessWidget {
  final AnimationController controller;
  final List<Contact> contacts;

  const _RadarWidget({required this.controller, required this.contacts});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rings
          for (final r in [1.0, 0.67, 0.33])
            Container(
              width: 220 * r,
              height: 220 * r,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
            ),

          // Sweep
          AnimatedBuilder(
            animation: controller,
            builder: (_, __) => CustomPaint(
              size: const Size(220, 220),
              painter: _RadarSweepPainter(
                angle: controller.value * 2 * math.pi,
                color: AppColors.primary,
              ),
            ),
          ),

          // Contact dots
          ...contacts.asMap().entries.map((e) {
            final angle = e.key * (2 * math.pi / math.max(contacts.length, 1)) - math.pi / 2;
            final dist = e.key.isEven ? 55.0 : 80.0;
            return Positioned(
              left: 110 + dist * math.cos(angle) - 16,
              top: 110 + dist * math.sin(angle) - 16,
              child: _RadarDot(contact: e.value),
            );
          }),

          // Center dot
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(end: 1.4, duration: 800.ms, curve: Curves.easeInOut),
        ],
      ),
    );
  }
}

class _RadarSweepPainter extends CustomPainter {
  final double angle;
  final Color color;

  _RadarSweepPainter({required this.angle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const sweepWidth = 1.4;
    const slices = 28;

    // Draw arc slices with linearly increasing opacity — avoids SweepGradient seam
    for (int i = 0; i < slices; i++) {
      final t = (i + 1) / slices;
      final startA = angle - sweepWidth + (i / slices) * sweepWidth;
      const sliceSize = sweepWidth / slices + 0.005; // tiny overlap
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startA,
        sliceSize,
        true,
        Paint()..color = color.withValues(alpha: t * 0.4),
      );
    }

    // Leading edge line
    canvas.drawLine(
      center,
      center + Offset(radius * math.cos(angle), radius * math.sin(angle)),
      Paint()
        ..color = color.withValues(alpha: 0.75)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_RadarSweepPainter old) => old.angle != angle;
}

class _RadarDot extends StatelessWidget {
  final Contact contact;
  const _RadarDot({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: contact.name,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: contact.avatarStyle.color,
          border: Border.all(color: AppColors.bgBase, width: 2),
          boxShadow: [
            BoxShadow(
              color: contact.avatarStyle.color.withValues(alpha: 0.5),
              blurRadius: 8,
            ),
          ],
        ),
        child: Center(
          child: Text(
            contact.initials.substring(0, 1),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(end: 1.1, duration: 1200.ms, curve: Curves.easeInOut);
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color? color;

  const _SectionLabel({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color ?? AppColors.mutedForeground,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

// ─── Device Tile ──────────────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  final Contact contact;
  final bool dimmed;
  final VoidCallback onCall;
  final VoidCallback onVideo;
  final VoidCallback onChat;
  final VoidCallback onInfo;

  const _DeviceTile({
    required this.contact,
    this.dimmed = false,
    required this.onCall,
    required this.onVideo,
    required this.onChat,
    required this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.6 : 1.0,
      child: GestureDetector(
        onTap: onInfo,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bgSubtle,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    AppAvatar(
                      style: contact.avatarStyle,
                      initials: contact.initials,
                      size: 44,
                    ),
                    if (contact.isOnline)
                      Positioned(
                        right: 1,
                        bottom: 1,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: AppColors.online,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.bgSubtle, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.name,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        contact.address,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    _TileAction(
                      icon: Icons.call_outlined,
                      onTap: onCall,
                    ),
                    const SizedBox(width: 6),
                    _TileAction(
                      icon: Icons.videocam_outlined,
                      onTap: onVideo,
                    ),
                    const SizedBox(width: 6),
                    _TileAction(
                      icon: Icons.chat_bubble_outline_rounded,
                      primary: true,
                      onTap: onChat,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TileAction extends StatelessWidget {
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;

  const _TileAction({required this.icon, this.primary = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: primary
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.bgBase,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: primary
                ? AppColors.primary.withValues(alpha: 0.25)
                : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: primary ? AppColors.primaryLight : AppColors.mutedForeground,
        ),
      ),
    );
  }
}

// ─── Scan button ──────────────────────────────────────────────────────────────

class _ScanButton extends StatelessWidget {
  final bool scanning;
  final VoidCallback onTap;

  const _ScanButton({required this.scanning, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: scanning ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (scanning)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(AppColors.primaryLight),
                ),
              )
            else
              Icon(Icons.refresh_rounded, size: 14, color: AppColors.primaryLight),
            const SizedBox(width: 6),
            Text(
              scanning ? 'Сканирую...' : 'Обновить',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
