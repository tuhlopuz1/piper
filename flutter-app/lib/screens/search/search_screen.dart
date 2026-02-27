import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../widgets/app_avatar.dart';
import '../chat/chat_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  String _query = '';

  List<Chat> get _chatResults => mockChats
      .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
      .toList();

  List<Chat> get _messageResults => mockChats
      .where((c) =>
          _query.isNotEmpty &&
          c.lastMessage.toLowerCase().contains(_query.toLowerCase()))
      .toList();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Column(
        children: [
          // ── Search bar ────────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(12, top + 12, 12, 12),
            color: AppColors.bgSubtle,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.bgBase,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: TextField(
                      controller: _ctrl,
                      autofocus: true,
                      style: GoogleFonts.inter(fontSize: 14, color: AppColors.foreground),
                      decoration: InputDecoration(
                        hintText: 'Поиск по чатам и сообщениям...',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.mutedForeground,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: AppColors.mutedForeground,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Отмена',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.primaryLight,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Results ───────────────────────────────────────────────────────
          Expanded(
            child: _query.isEmpty
                ? _EmptyState()
                : CustomScrollView(
                    slivers: [
                      if (_chatResults.isNotEmpty) ...[
                        _SectionHeader(title: 'Чаты и контакты'),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => _SearchChatTile(
                              chat: _chatResults[i],
                              query: _query,
                            )
                                .animate(delay: Duration(milliseconds: i * 40))
                                .fadeIn(duration: 200.ms),
                            childCount: _chatResults.length,
                          ),
                        ),
                      ],
                      if (_messageResults.isNotEmpty) ...[
                        _SectionHeader(title: 'Сообщения'),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => _SearchMessageTile(
                              chat: _messageResults[i],
                              query: _query,
                            )
                                .animate(delay: Duration(milliseconds: i * 40))
                                .fadeIn(duration: 200.ms),
                            childCount: _messageResults.length,
                          ),
                        ),
                      ],
                      if (_chatResults.isEmpty && _messageResults.isEmpty)
                        SliverFillRemaining(child: _NoResults(query: _query)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          title.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.mutedForeground,
            letterSpacing: 0.9,
          ),
        ),
      ),
    );
  }
}

class _SearchChatTile extends StatelessWidget {
  final Chat chat;
  final String query;
  const _SearchChatTile({required this.chat, required this.query});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AppAvatar(
        style: chat.avatarStyle,
        initials: chat.initials,
        size: 44,
        isGroup: chat.isGroup,
      ),
      title: _HighlightText(text: chat.name, query: query),
      subtitle: Text(
        chat.isGroup ? '${chat.memberCount} участников' : 'Контакт',
        style: GoogleFonts.inter(fontSize: 12, color: AppColors.mutedForeground),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
      ),
    );
  }
}

class _SearchMessageTile extends StatelessWidget {
  final Chat chat;
  final String query;
  const _SearchMessageTile({required this.chat, required this.query});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AppAvatar(
        style: chat.avatarStyle,
        initials: chat.initials,
        size: 44,
        isGroup: chat.isGroup,
      ),
      title: Text(
        chat.name,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.foreground,
        ),
      ),
      subtitle: _HighlightText(text: chat.lastMessage, query: query),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
      ),
    );
  }
}

class _HighlightText extends StatelessWidget {
  final String text;
  final String query;
  const _HighlightText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(
        text,
        style: GoogleFonts.inter(fontSize: 14, color: AppColors.foreground),
      );
    }

    final lower = text.toLowerCase();
    final lowerQ = query.toLowerCase();
    final idx = lower.indexOf(lowerQ);
    if (idx < 0) {
      return Text(
        text,
        style: GoogleFonts.inter(fontSize: 14, color: AppColors.foreground),
      );
    }

    return Text.rich(TextSpan(children: [
      TextSpan(
        text: text.substring(0, idx),
        style: GoogleFonts.inter(fontSize: 14, color: AppColors.foreground),
      ),
      TextSpan(
        text: text.substring(idx, idx + query.length),
        style: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.primaryLight,
          fontWeight: FontWeight.w600,
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
        ),
      ),
      TextSpan(
        text: text.substring(idx + query.length),
        style: GoogleFonts.inter(fontSize: 14, color: AppColors.foreground),
      ),
    ]));
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded, size: 56, color: AppColors.border),
          const SizedBox(height: 16),
          Text(
            'Начните вводить запрос',
            style: GoogleFonts.inter(
              fontSize: 16,
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  final String query;
  const _NoResults({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 56, color: AppColors.border),
          const SizedBox(height: 16),
          Text(
            'Ничего не найдено',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.foreground,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'По запросу «$query» нет результатов',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}
