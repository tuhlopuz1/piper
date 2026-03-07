import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../services/piper_service.dart';
import '../../widgets/app_avatar.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  final Set<String> _selected = {};

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
    for (final peerId in _selected) {
      svc.inviteToGroup(groupId, peerId);
    }
    Navigator.pop(context);
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
          // Header
          Container(
            padding: EdgeInsets.fromLTRB(8, top + 8, 8, 8),
            decoration: BoxDecoration(
              color: AppColors.bgSubtle,
              border:
                  Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
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
                    'Новая группа',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _create,
                  child: Text(
                    'Создать',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Name input
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: GoogleFonts.inter(
                  fontSize: 15, color: AppColors.foreground),
              decoration: InputDecoration(
                hintText: 'Название группы',
                hintStyle: GoogleFonts.inter(color: AppColors.mutedForeground),
                filled: true,
                fillColor: AppColors.bgSubtle,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border, width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border, width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),

          // Section label
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(
                  'УЧАСТНИКИ · ${peers.length} в сети',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedForeground,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),

          // Peer list
          Expanded(
            child: peers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline_rounded,
                            color: AppColors.mutedForeground, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'Нет пиров в сети',
                          style: GoogleFonts.inter(
                              color: AppColors.mutedForeground, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Группа будет создана без участников',
                          style: GoogleFonts.inter(
                              color: AppColors.mutedForeground, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: peers.length,
                    itemBuilder: (ctx, i) {
                      final peer = peers[i];
                      final selected = _selected.contains(peer.id);
                      return ListTile(
                        leading: AppAvatar(
                          style: svc.avatarStyleForPeer(peer.id),
                          initials: svc.initialsFor(peer.displayName),
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
                        subtitle: Text(
                          'В сети',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                        trailing: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected
                                ? AppColors.primary
                                : Colors.transparent,
                            border: Border.all(
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.border,
                              width: 1.5,
                            ),
                          ),
                          child: selected
                              ? const Icon(Icons.check_rounded,
                                  size: 14, color: Colors.white)
                              : null,
                        ),
                        onTap: () {
                          setState(() {
                            if (selected) {
                              _selected.remove(peer.id);
                            } else {
                              _selected.add(peer.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
