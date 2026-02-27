import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../models/chat.dart';
import '../../../widgets/chat_item.dart';
import '../../search/search_screen.dart';

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  final List<Chat> _filtered = mockChats;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: CustomScrollView(
        slivers: [
          _buildHeader(),
          _buildSectionLabel(),
          _buildList(),
          const SliverToBoxAdapter(child: SizedBox(height: 88)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildHeader() {
    final top = MediaQuery.of(context).padding.top;
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, top + 16, 20, 12),
        child: Row(
          children: [
            Text(
              'Piper',
              style: GoogleFonts.inter(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.foreground,
                letterSpacing: -1,
              ),
            ),
            const Spacer(),
            _NavBtn(
              icon: Icons.search_rounded,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              ),
            ),
            const SizedBox(width: 8),
            _NavBtn(icon: Icons.person_add_outlined, onTap: () {}),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildSectionLabel() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Text(
          'НЕДАВНИЕ · ${_filtered.length}',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.mutedForeground,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  SliverList _buildList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) {
          if (_filtered.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                children: [
                  Icon(Icons.search_off_rounded,
                      color: AppColors.mutedForeground, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Ничего не найдено',
                    style: GoogleFonts.inter(
                        color: AppColors.mutedForeground, fontSize: 15),
                  ),
                ],
              ),
            );
          }
          final chat = _filtered[i];
          return ChatItem(chat: chat)
              .animate(delay: Duration(milliseconds: i * 35))
              .fadeIn(duration: 380.ms)
              .slideX(
                  begin: -0.04,
                  end: 0,
                  duration: 380.ms,
                  curve: Curves.easeOutCubic);
        },
        childCount: _filtered.isEmpty ? 1 : _filtered.length,
      ),
    );
  }
}

// ─── Small icon button ────────────────────────────────────────────────────────

class _NavBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavBtn({required this.icon, required this.onTap});

  @override
  State<_NavBtn> createState() => _NavBtnState();
}

class _NavBtnState extends State<_NavBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.bgSubtle,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Icon(widget.icon, color: AppColors.foreground, size: 18),
        ),
      ),
    );
  }
}
