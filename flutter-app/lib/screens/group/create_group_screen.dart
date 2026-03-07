import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/chat.dart';
import '../../services/piper_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_avatar.dart';
import '../chat/chat_screen.dart';

/// Screen for creating a new group chat.
/// The user enters a group name and selects peers to invite.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _selectedPeers = <String>{};

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _create() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название группы')),
      );
      return;
    }

    final svc = context.read<PiperService>();
    final groupId = svc.createGroup(name);

    if (groupId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось создать группу')),
      );
      return;
    }

    // Invite selected peers
    for (final peerId in _selectedPeers) {
      svc.inviteToGroup(groupId, peerId);
    }

    // Navigate to the new group chat
    final chatId = 'group:$groupId';
    final chat = Chat(
      id: chatId,
      name: name,
      lastMessage: '',
      lastMessageTime: DateTime.now(),
      unreadCount: 0,
      isGroup: true,
      avatarStyle: AvatarStyle.indigo,
      initials: svc.initialsFor(name),
      isOnline: false,
      lastMessageType: MessageType.text,
      memberCount: _selectedPeers.length + 1,
    );

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<PiperService>();
    final peers = svc.peers.where((p) => p.isConnected).toList();
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Column(
        children: [
          // ── App bar ──────────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(8, top + 8, 8, 8),
            decoration: BoxDecoration(
              color: AppColors.bgSubtle,
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  color: AppColors.foreground,
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Новая группа',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _nameCtrl.text.trim().isNotEmpty ? _create : null,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Создать',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // ── Group name input ────────────────────────────────────────
                Text(
                  'НАЗВАНИЕ ГРУППЫ',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedForeground,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgSubtle,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: AppColors.heroGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.group_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _nameCtrl,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            color: AppColors.foreground,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Введите название...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 15,
                              color: AppColors.mutedForeground,
                            ),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .slideY(begin: 0.05, end: 0, duration: 300.ms),

                const SizedBox(height: 24),

                // ── Selected peers chips ────────────────────────────────────
                if (_selectedPeers.isNotEmpty) ...[
                  Text(
                    'ВЫБРАНО · ${_selectedPeers.length}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedForeground,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedPeers.map((id) {
                      final peer = svc.peers.firstWhere(
                        (p) => p.id == id,
                        orElse: () => peers.first,
                      );
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedPeers.remove(id)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                peer.displayName,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.primaryLight,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.close_rounded,
                                  size: 14, color: AppColors.primaryLight),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Peer list ───────────────────────────────────────────────
                Text(
                  'УСТРОЙСТВА В СЕТИ · ${peers.length}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedForeground,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 8),

                if (peers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Column(
                      children: [
                        Icon(Icons.wifi_off_rounded,
                            color: AppColors.mutedForeground, size: 40),
                        const SizedBox(height: 12),
                        Text(
                          'Нет устройств в сети',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Вы можете создать группу и пригласить\nучастников позже',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),

                ...peers.asMap().entries.map((entry) {
                  final i = entry.key;
                  final peer = entry.value;
                  final selected = _selectedPeers.contains(peer.id);
                  return _PeerTile(
                    name: peer.displayName,
                    initials: svc.initialsFor(peer.displayName),
                    avatarStyle: svc.avatarStyleForPeer(peer.id),
                    selected: selected,
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _selectedPeers.remove(peer.id);
                        } else {
                          _selectedPeers.add(peer.id);
                        }
                      });
                    },
                  )
                      .animate(delay: Duration(milliseconds: i * 40))
                      .fadeIn(duration: 250.ms)
                      .slideX(begin: -0.03, end: 0, duration: 250.ms);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  final String name;
  final String initials;
  final AvatarStyle avatarStyle;
  final bool selected;
  final VoidCallback onTap;

  const _PeerTile({
    required this.name,
    required this.initials,
    required this.avatarStyle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.bgSubtle,
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
            Stack(
              children: [
                AppAvatar(
                  style: avatarStyle,
                  initials: initials,
                  size: 40,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.online,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? AppColors.bgBase : AppColors.bgSubtle,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.foreground,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
