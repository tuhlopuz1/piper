import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/chat.dart';
import '../../native/piper_events.dart';
import '../../services/piper_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_avatar.dart';

/// Screen that shows group details: members list, invite button, leave button.
class GroupInfoScreen extends StatelessWidget {
  final Chat chat;

  const GroupInfoScreen({super.key, required this.chat});

  String get _groupId => chat.id.replaceFirst('group:', '');

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<PiperService>();

    // Find the current group from the service
    final group = svc.groups
        .where((g) => g.id == _groupId)
        .firstOrNull;

    final memberIds = group?.members ?? [];
    final peerMap = {for (final p in svc.peers) p.id: p};

    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(20, top + 8, 20, 32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.2),
                    AppColors.bgBase,
                  ],
                ),
              ),
              child: Column(
                children: [
                  // Back button
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            size: 18),
                        color: AppColors.foreground,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Group avatar
                  AppAvatar(
                    style: AvatarStyle.indigo,
                    initials: svc.initialsFor(chat.name),
                    size: 88,
                    isGroup: true,
                  )
                      .animate()
                      .scale(
                        begin: const Offset(0.7, 0.7),
                        end: const Offset(1, 1),
                        duration: 500.ms,
                        curve: Curves.easeOutBack,
                      )
                      .fadeIn(duration: 400.ms),

                  const SizedBox(height: 14),

                  Text(
                    chat.name,
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground,
                      letterSpacing: -0.5,
                    ),
                  )
                      .animate(delay: 80.ms)
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.2, end: 0, duration: 400.ms),

                  const SizedBox(height: 6),

                  Text(
                    '${memberIds.length} участник${_pluralSuffix(memberIds.length)}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.mutedForeground,
                    ),
                  ).animate(delay: 120.ms).fadeIn(duration: 400.ms),
                ],
              ),
            ),
          ),

          // ── Add member button ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: GestureDetector(
                onTap: () => _showInviteDialog(context, svc, memberIds),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_add_rounded,
                            size: 18, color: AppColors.primaryLight),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Добавить участника',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate(delay: 160.ms).fadeIn(duration: 380.ms),
            ),
          ),

          // ── Members section ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                'УЧАСТНИКИ · ${memberIds.length}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mutedForeground,
                  letterSpacing: 0.9,
                ),
              ),
            ),
          ),

          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                final memberId = memberIds[i];
                final isMe = memberId == svc.myId;
                final peer = peerMap[memberId];
                final name = isMe
                    ? '${svc.myName} (вы)'
                    : (peer?.displayName ?? memberId.substring(0, 8));
                final isOnline = isMe || (peer?.isConnected ?? false);

                return _MemberTile(
                  name: name,
                  initials: svc.initialsFor(
                      isMe ? svc.myName : (peer?.displayName ?? '?')),
                  avatarStyle: isMe
                      ? svc.avatarStyle
                      : svc.avatarStyleForPeer(memberId),
                  isOnline: isOnline,
                  isMe: isMe,
                )
                    .animate(delay: Duration(milliseconds: 200 + i * 40))
                    .fadeIn(duration: 300.ms)
                    .slideX(begin: -0.03, end: 0, duration: 300.ms);
              },
              childCount: memberIds.length,
            ),
          ),

          // ── Leave group ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: GestureDetector(
                onTap: () => _confirmLeave(context, svc),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.destructive.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.destructive.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.exit_to_app_rounded,
                          size: 18, color: AppColors.destructive),
                      const SizedBox(width: 12),
                      Text(
                        'Покинуть группу',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.destructive,
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate(delay: 300.ms).fadeIn(duration: 380.ms),
            ),
          ),
        ],
      ),
    );
  }

  String _pluralSuffix(int count) {
    if (count % 10 == 1 && count % 100 != 11) return '';
    if ([2, 3, 4].contains(count % 10) &&
        ![12, 13, 14].contains(count % 100)) return 'а';
    return 'ов';
  }

  void _confirmLeave(BuildContext context, PiperService svc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border, width: 0.5),
        ),
        title: Text(
          'Покинуть группу?',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: AppColors.foreground,
          ),
        ),
        content: Text(
          'Вы уверены, что хотите покинуть "${chat.name}"?',
          style: GoogleFonts.inter(color: AppColors.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Отмена',
              style: GoogleFonts.inter(color: AppColors.mutedForeground),
            ),
          ),
          TextButton(
            onPressed: () {
              svc.leaveGroup(_groupId);
              Navigator.pop(ctx); // close dialog
              // Pop back to chats list (pop group info + chat screen)
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: Text(
              'Покинуть',
              style: GoogleFonts.inter(
                color: AppColors.destructive,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInviteDialog(
      BuildContext context, PiperService svc, List<String> currentMembers) {
    final available = svc.peers
        .where((p) => p.isConnected && !currentMembers.contains(p.id))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Нет доступных устройств для приглашения')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSubtle,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _InviteMemberSheet(
        peers: available,
        svc: svc,
        groupId: _groupId,
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final String name;
  final String initials;
  final AvatarStyle avatarStyle;
  final bool isOnline;
  final bool isMe;

  const _MemberTile({
    required this.name,
    required this.initials,
    required this.avatarStyle,
    required this.isOnline,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                AppAvatar(
                  style: avatarStyle,
                  initials: initials,
                  size: 40,
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.online,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.bgSubtle, width: 1.5),
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
                    name,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.foreground,
                    ),
                  ),
                  Text(
                    isOnline ? 'В сети' : 'Не в сети',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isOnline
                          ? AppColors.online
                          : AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteMemberSheet extends StatefulWidget {
  final List<PeerInfo> peers;
  final PiperService svc;
  final String groupId;

  const _InviteMemberSheet({
    required this.peers,
    required this.svc,
    required this.groupId,
  });

  @override
  State<_InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends State<_InviteMemberSheet> {
  final _selected = <String>{};

  void _invite() {
    for (final id in _selected) {
      widget.svc.inviteToGroup(widget.groupId, id);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Пригласить в группу',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.foreground,
                  ),
                ),
              ),
              if (_selected.isNotEmpty)
                GestureDetector(
                  onTap: _invite,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Добавить (${_selected.length})',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ...widget.peers.map((peer) {
            final selected = _selected.contains(peer.id);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (selected) {
                    _selected.remove(peer.id);
                  } else {
                    _selected.add(peer.id);
                  }
                });
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : AppColors.bgBase,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.3)
                        : AppColors.border,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    AppAvatar(
                      style: widget.svc.avatarStyleForPeer(peer.id),
                      initials: widget.svc.initialsFor(peer.displayName),
                      size: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        peer.displayName,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.foreground,
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: selected ? AppColors.primary : AppColors.border,
                          width: 1.5,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check_rounded,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
