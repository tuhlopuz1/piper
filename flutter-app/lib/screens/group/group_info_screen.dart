import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../native/piper_events.dart';
import '../../services/piper_service.dart';
import '../../widgets/app_avatar.dart';

class GroupInfoScreen extends StatelessWidget {
  final Chat chat;

  const GroupInfoScreen({super.key, required this.chat});

  String get _groupId => chat.id.replaceFirst('group:', '');

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<PiperService>();
    final top = MediaQuery.of(context).padding.top;

    // Find the live GroupInfo for this chat
    final groupInfo = svc.groups
        .where((g) => g.id == _groupId)
        .firstOrNull;

    final members = groupInfo?.members ?? [];
    final isOwner = members.isNotEmpty && members.first == svc.myId;

    // Peer map for name/status lookup
    final peerMap = {for (final p in svc.peers) p.id: p};

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(8, top + 8, 8, 8),
              decoration: BoxDecoration(
                color: AppColors.bgSubtle,
                border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    color: AppColors.foreground,
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      'Информация о группе',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Group avatar + name
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  AppAvatar(
                    style: chat.avatarStyle,
                    initials: chat.initials,
                    size: 72,
                    isGroup: true,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    chat.name,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${members.length} участников',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Members section label
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'УЧАСТНИКИ',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedForeground,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (isOwner)
                    GestureDetector(
                      onTap: () => _showAddMemberSheet(context, svc, members),
                      child: Text(
                        'Добавить',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Member list
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final memberId = members[i];
                final peer = peerMap[memberId];
                final isMe = memberId == svc.myId;
                final displayName = isMe
                    ? '${svc.myName} (вы)'
                    : (peer?.displayName ?? memberId.substring(0, 8));
                final isOnline = isMe || (peer?.isConnected ?? false);

                return ListTile(
                  leading: AppAvatar(
                    style: svc.avatarStyleForPeer(memberId),
                    initials: svc.initialsFor(
                        isMe ? svc.myName : (peer?.displayName ?? memberId)),
                    size: 42,
                    isGroup: false,
                  ),
                  title: Text(
                    displayName,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.foreground,
                    ),
                  ),
                  subtitle: Text(
                    isOnline ? 'В сети' : 'Не в сети',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isOnline
                          ? AppColors.primary
                          : AppColors.mutedForeground,
                    ),
                  ),
                  trailing: isOwner && !isMe
                      ? IconButton(
                          icon: const Icon(Icons.person_remove_outlined,
                              size: 18),
                          color: AppColors.destructive,
                          tooltip: 'Удалить из группы',
                          onPressed: () =>
                              _confirmKick(context, svc, memberId, displayName),
                        )
                      : null,
                );
              },
              childCount: members.length,
            ),
          ),

          // Actions
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: _ActionTile(
                icon: Icons.exit_to_app_rounded,
                label: 'Покинуть группу',
                color: AppColors.destructive,
                onTap: () => _confirmLeave(context, svc),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  void _showAddMemberSheet(
      BuildContext context, PiperService svc, List<String> currentMembers) {
    final available = svc.peers
        .where((p) => p.isConnected && !currentMembers.contains(p.id))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет новых пиров для добавления')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSubtle,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddMemberSheet(
        peers: available,
        svc: svc,
        groupId: _groupId,
      ),
    );
  }

  void _confirmKick(BuildContext context, PiperService svc, String peerId, String peerName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSubtle,
        title: Text(
          'Удалить участника?',
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w600, color: AppColors.foreground),
        ),
        content: Text(
          '$peerName будет удалён из группы «${chat.name}».',
          style: GoogleFonts.inter(color: AppColors.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена',
                style: GoogleFonts.inter(color: AppColors.mutedForeground)),
          ),
          TextButton(
            onPressed: () {
              svc.kickFromGroup(_groupId, peerId);
              Navigator.pop(ctx);
            },
            child: Text('Удалить',
                style: GoogleFonts.inter(color: AppColors.destructive)),
          ),
        ],
      ),
    );
  }

  void _confirmLeave(BuildContext context, PiperService svc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSubtle,
        title: Text(
          'Покинуть группу?',
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w600, color: AppColors.foreground),
        ),
        content: Text(
          'Вы покинете группу «${chat.name}».',
          style: GoogleFonts.inter(color: AppColors.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена',
                style: GoogleFonts.inter(color: AppColors.mutedForeground)),
          ),
          TextButton(
            onPressed: () {
              svc.leaveGroup(_groupId);
              Navigator.pop(ctx);
              Navigator.popUntil(context, (r) => r.isFirst);
            },
            child: Text('Покинуть',
                style: GoogleFonts.inter(color: AppColors.destructive)),
          ),
        ],
      ),
    );
  }
}

// ── Add member bottom sheet ───────────────────────────────────────────────────

class _AddMemberSheet extends StatefulWidget {
  final List<PeerInfo> peers;
  final PiperService svc;
  final String groupId;

  const _AddMemberSheet({
    required this.peers,
    required this.svc,
    required this.groupId,
  });

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final Set<String> _selected = {};

  void _invite() {
    for (final id in _selected) {
      widget.svc.inviteToGroup(widget.groupId, id);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Добавить участников',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.foreground,
                ),
              ),
              TextButton(
                onPressed: _selected.isEmpty ? null : _invite,
                child: Text(
                  'Добавить (${_selected.length})',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _selected.isEmpty
                        ? AppColors.mutedForeground
                        : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.peers.length,
            itemBuilder: (ctx, i) {
              final peer = widget.peers[i];
              final selected = _selected.contains(peer.id);
              return ListTile(
                leading: AppAvatar(
                  style: widget.svc.avatarStyleForPeer(peer.id),
                  initials: widget.svc.initialsFor(peer.displayName),
                  size: 42,
                  isGroup: false,
                ),
                title: Text(
                  peer.displayName,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.foreground,
                  ),
                ),
                trailing: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        selected ? AppColors.primary : Colors.transparent,
                    border: Border.all(
                      color:
                          selected ? AppColors.primary : AppColors.border,
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          size: 14, color: Colors.white)
                      : null,
                ),
                onTap: () => setState(() {
                  if (selected) {
                    _selected.remove(peer.id);
                  } else {
                    _selected.add(peer.id);
                  }
                }),
              );
            },
          ),
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
      ],
    );
  }
}

// ── Action tile ───────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.bgSubtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
