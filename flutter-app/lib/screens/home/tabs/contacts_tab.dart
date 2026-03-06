import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../models/chat.dart';
import '../../../services/call_service.dart';
import '../../../services/piper_service.dart';
import '../../../widgets/app_avatar.dart';
import '../../../widgets/mesh_graph_widget.dart';
import '../../contacts/contact_info_screen.dart';
import '../../chat/chat_screen.dart';
import '../../call/voice_call_screen.dart';
import '../../call/video_call_screen.dart';

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _refresh() {
    setState(() => _scanning = true);
    context.read<PiperService>().refreshNetwork().whenComplete(() {
      if (mounted) {
        setState(() => _scanning = false);
      }
    });
  }

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
    final svc = context.watch<PiperService>();
    final all = svc.contacts;
    final online = all.where((c) => c.isOnline).toList();
    final offline = all.where((c) => !c.isOnline).toList();

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
                  child: MeshGraphWidget(topology: svc.topology),
                ),
              ),
            ),

            // ── Online section ──────────────────────────────────────────────
            if (online.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionLabel(
                  label: 'В СЕТИ · ${online.length}',
                  color: AppColors.online,
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _DeviceTile(
                    contact: online[i],
                    onCall: () async {
                      final c = online[i];
                      await CallService.instance.startCall(c.id, c.name, false);
                      if (!context.mounted) return;
                      if (CallService.instance.state == CallState.idle) return;
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const VoiceCallScreen(),
                      ));
                    },
                    onVideo: () async {
                      final c = online[i];
                      await CallService.instance.startCall(c.id, c.name, true);
                      if (!context.mounted) return;
                      if (CallService.instance.state == CallState.idle) return;
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const VideoCallScreen(),
                      ));
                    },
                    onChat: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(chat: _contactToChat(online[i])),
                      ),
                    ),
                    onInfo: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContactInfoScreen(chat: _contactToChat(online[i])),
                      ),
                    ),
                  )
                      .animate(delay: Duration(milliseconds: i * 60))
                      .fadeIn(duration: 300.ms)
                      .slideX(begin: -0.05, end: 0, duration: 300.ms),
                  childCount: online.length,
                ),
              ),
            ],

            // ── Offline section ─────────────────────────────────────────────
            if (offline.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionLabel(label: 'НЕ В СЕТИ · ${offline.length}'),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _DeviceTile(
                    contact: offline[i],
                    dimmed: true,
                    onCall: () async {
                      final c = offline[i];
                      await CallService.instance.startCall(c.id, c.name, false);
                      if (!context.mounted) return;
                      if (CallService.instance.state == CallState.idle) return;
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const VoiceCallScreen(),
                      ));
                    },
                    onVideo: () async {
                      final c = offline[i];
                      await CallService.instance.startCall(c.id, c.name, true);
                      if (!context.mounted) return;
                      if (CallService.instance.state == CallState.idle) return;
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const VideoCallScreen(),
                      ));
                    },
                    onChat: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(chat: _contactToChat(offline[i])),
                      ),
                    ),
                    onInfo: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContactInfoScreen(chat: _contactToChat(offline[i])),
                      ),
                    ),
                  )
                      .animate(delay: Duration(milliseconds: i * 60))
                      .fadeIn(duration: 300.ms),
                  childCount: offline.length,
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
