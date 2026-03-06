import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../models/chat.dart';
import '../../../services/call_service.dart';
import '../../../services/piper_service.dart';
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
  late AnimationController _pulseCtrl;
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() => _scanning = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _scanning = false);
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
            // -- Header
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, top + 16, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Mesh-сеть',
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

            // -- Mesh Graph
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: _MeshGraphWidget(
                    pulseCtrl: _pulseCtrl,
                    topology: svc.topology,
                    myId: svc.myId,
                    myName: svc.myName,
                    contacts: online,
                  ),
                ),
              ),
            ),

            // -- Online section
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

            // -- Empty state (no peers at all)
            if (online.isEmpty && offline.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyNetworkState(),
              ),

            // -- Offline section
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

// -- Mesh Graph Widget (force-directed layout) --------------------------------

class _MeshGraphWidget extends StatelessWidget {
  final AnimationController pulseCtrl;
  final Map<String, dynamic> topology;
  final String myId;
  final String myName;
  final List<Contact> contacts;

  const _MeshGraphWidget({
    required this.pulseCtrl,
    required this.topology,
    required this.myId,
    required this.myName,
    required this.contacts,
  });

  @override
  Widget build(BuildContext context) {
    final nodes = (topology['nodes'] as List<dynamic>?) ?? [];
    final edges = (topology['edges'] as List<dynamic>?) ?? [];

    // Build node positions using circular layout around center.
    final size = 260.0;
    final center = Offset(size / 2, size / 2);
    final radius = size / 2 - 30;

    // Separate self from others.
    final otherNodes = nodes.where((n) => n['id'] != myId).toList();
    final nodeCount = otherNodes.length;

    // Map nodeId -> position.
    final positions = <String, Offset>{};
    positions[myId] = center;
    for (int i = 0; i < nodeCount; i++) {
      final angle = (i * 2 * math.pi / math.max(nodeCount, 1)) - math.pi / 2;
      positions[otherNodes[i]['id'] as String] = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
    }

    // Build contact lookup for colors.
    final contactMap = {for (final c in contacts) c.id: c};

    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: pulseCtrl,
        builder: (context, _) => CustomPaint(
          painter: _MeshGraphPainter(
            myId: myId,
            nodes: nodes,
            edges: edges,
            positions: positions,
            contactMap: contactMap,
            pulseValue: pulseCtrl.value,
          ),
          child: Stack(
            children: [
              // Center node label (self)
              Positioned(
                left: center.dx - 18,
                top: center.dy - 18,
                child: _NodeDot(
                  label: myName.isNotEmpty ? myName[0].toUpperCase() : '?',
                  color: AppColors.primary,
                  isSelf: true,
                  size: 36,
                ),
              ),
              // Other node labels
              for (int i = 0; i < nodeCount; i++)
                Builder(builder: (_) {
                  final nodeId = otherNodes[i]['id'] as String;
                  final pos = positions[nodeId]!;
                  final contact = contactMap[nodeId];
                  final isRelay = otherNodes[i]['is_relay'] == true;
                  final displayName = (otherNodes[i]['display_name'] as String?) ??
                      (otherNodes[i]['name'] as String?) ?? '?';
                  final color = contact?.avatarStyle.color ?? AppColors.accent;
                  return Positioned(
                    left: pos.dx - 15,
                    top: pos.dy - 15,
                    child: Tooltip(
                      message: isRelay ? '$displayName (relay)' : displayName,
                      child: _NodeDot(
                        label: displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                        color: color,
                        isSelf: false,
                        size: 30,
                        isRelay: isRelay,
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeshGraphPainter extends CustomPainter {
  final String myId;
  final List<dynamic> nodes;
  final List<dynamic> edges;
  final Map<String, Offset> positions;
  final Map<String, Contact> contactMap;
  final double pulseValue;

  _MeshGraphPainter({
    required this.myId,
    required this.nodes,
    required this.edges,
    required this.positions,
    required this.contactMap,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background grid rings.
    final center = Offset(size.width / 2, size.height / 2);
    for (final r in [1.0, 0.67, 0.33]) {
      canvas.drawCircle(
        center,
        (size.width / 2) * r,
        Paint()
          ..color = AppColors.primary.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }

    // Draw edges.
    for (final edge in edges) {
      final fromId = edge['from'] as String?;
      final toId = edge['to'] as String?;
      if (fromId == null || toId == null) continue;
      final from = positions[fromId];
      final to = positions[toId];
      if (from == null || to == null) continue;

      final isRelayEdge = fromId != myId && toId != myId;
      final edgePaint = Paint()
        ..strokeWidth = isRelayEdge ? 1.0 : 1.5
        ..style = PaintingStyle.stroke;

      if (isRelayEdge) {
        edgePaint.color = AppColors.accent.withValues(alpha: 0.3 + pulseValue * 0.15);
      } else {
        edgePaint.color = AppColors.primary.withValues(alpha: 0.4 + pulseValue * 0.2);
      }

      canvas.drawLine(from, to, edgePaint);

      // Draw small dot at midpoint for relay edges.
      if (isRelayEdge) {
        final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
        canvas.drawCircle(
          mid,
          2,
          Paint()..color = AppColors.accent.withValues(alpha: 0.5),
        );
      }
    }

    // Draw glow around center node.
    canvas.drawCircle(
      center,
      20 + pulseValue * 4,
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.1 + pulseValue * 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  @override
  bool shouldRepaint(_MeshGraphPainter old) => old.pulseValue != pulseValue || old.edges != edges;
}

class _NodeDot extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelf;
  final double size;
  final bool isRelay;

  const _NodeDot({
    required this.label,
    required this.color,
    required this.isSelf,
    required this.size,
    this.isRelay = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(
          color: isRelay
              ? AppColors.accent.withValues(alpha: 0.7)
              : AppColors.bgBase,
          width: isRelay ? 2 : 2,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isSelf ? 0.5 : 0.35),
            blurRadius: isSelf ? 12 : 8,
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: isSelf ? 14 : 11,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// -- Section label ------------------------------------------------------------

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

// -- Device Tile --------------------------------------------------------------

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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              contact.name,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.foreground,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (contact.isRelay) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'relay',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accent,
                                ),
                              ),
                            ),
                          ],
                        ],
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

// -- Empty network state ------------------------------------------------------

class _EmptyNetworkState extends StatelessWidget {
  const _EmptyNetworkState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.08),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.wifi_find_rounded,
              size: 34,
              color: AppColors.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Пока никого нет',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.foreground,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Piper ищет устройства в сети.\nПопросите других запустить приложение рядом — они появятся здесь автоматически.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.mutedForeground,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bgSubtle,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(AppColors.primaryLight),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Поиск устройств...',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -- Scan button --------------------------------------------------------------

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
