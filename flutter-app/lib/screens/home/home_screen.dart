import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../services/call_manager.dart';
import '../../widgets/app_avatar.dart';
import '../call/voice_call_screen.dart';
import 'tabs/chats_tab.dart';
import 'tabs/contacts_tab.dart';
import 'tabs/settings_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static final _tabs = [const ChatsTab(), const ContactsTab(), const SettingsTab()];

  static const _items = [
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded,    'Чаты'),
    (Icons.people_outline_rounded,      Icons.people_rounded,          'Контакты'),
    (Icons.settings_outlined,           Icons.settings_rounded,        'Настройки'),
  ];

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return ValueListenableBuilder<Chat?>(
      valueListenable: CallManager.instance.activeCall,
      builder: (context, activeCall, _) {
        if (w >= 900) return _DesktopLayout(index: _index, onTap: _setIndex, activeCall: activeCall);
        if (w >= 600) return _TabletLayout(index: _index, onTap: _setIndex, activeCall: activeCall);
        return _MobileLayout(index: _index, onTap: _setIndex, activeCall: activeCall);
      },
    );
  }

  void _setIndex(int i) => setState(() => _index = i);

  // ── shared body ────────────────────────────────────────────────────────────
  static Widget _body(int index) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        child: KeyedSubtree(key: ValueKey(index), child: _tabs[index]),
      );

}

// ─── Mobile layout ────────────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final Chat? activeCall;

  const _MobileLayout({required this.index, required this.onTap, this.activeCall});

  static const _items = _HomeScreenState._items;

  Widget _buildNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSubtle,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: List.generate(_items.length, (i) {
              final (icon, activeIcon, label) = _items[i];
              final sel = i == index;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: sel
                              ? AppColors.primary.withValues(alpha: 0.14)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          sel ? activeIcon : icon,
                          color: sel ? AppColors.primary : AppColors.mutedForeground,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                          color: sel ? AppColors.primary : AppColors.mutedForeground,
                        ),
                        child: Text(label),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _HomeScreenState._body(index),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (activeCall != null) _MinimizedCallBar(chat: activeCall!),
          _buildNav(),
        ],
      ),
    );
  }
}

// ─── Tablet layout ────────────────────────────────────────────────────────────

class _TabletLayout extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final Chat? activeCall;

  const _TabletLayout({required this.index, required this.onTap, this.activeCall});

  static const _items = _HomeScreenState._items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  backgroundColor: AppColors.bgSubtle,
                  selectedIndex: index,
                  onDestinationSelected: onTap,
                  labelType: NavigationRailLabelType.selected,
                  leading: const SizedBox(height: 8),
                  destinations: _items.map((item) {
                    final (icon, activeIcon, label) = item;
                    return NavigationRailDestination(
                      icon: Icon(icon),
                      selectedIcon: Icon(activeIcon),
                      label: Text(
                        label,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    );
                  }).toList(),
                ),
                const VerticalDivider(width: 0.5),
                Expanded(child: _HomeScreenState._body(index)),
              ],
            ),
          ),
          if (activeCall != null) _MinimizedCallBar(chat: activeCall!),
        ],
      ),
    );
  }
}

// ─── Desktop layout ───────────────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final Chat? activeCall;

  const _DesktopLayout({required this.index, required this.onTap, this.activeCall});

  static const _items = _HomeScreenState._items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Side nav
          Container(
            width: 220,
            decoration: BoxDecoration(
              color: AppColors.bgSubtle,
              border: Border(
                  right: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 28),
                // Logo
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: AppColors.heroGradient,
                        ),
                        child: Center(
                          child: Text(
                            'P',
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Piper',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.foreground,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                // Nav items
                ...List.generate(_items.length, (i) {
                  final (icon, activeIcon, label) = _items[i];
                  final sel = i == index;
                  return GestureDetector(
                    onTap: () => onTap(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            sel ? activeIcon : icon,
                            color: sel
                                ? AppColors.primary
                                : AppColors.mutedForeground,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            label,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: sel
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: sel
                                  ? AppColors.primary
                                  : AppColors.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Column(
              children: [
                Expanded(child: _HomeScreenState._body(index)),
                if (activeCall != null) _MinimizedCallBar(chat: activeCall!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Minimized call bar ───────────────────────────────────────────────────────

class _MinimizedCallBar extends StatelessWidget {
  final Chat chat;
  const _MinimizedCallBar({required this.chat});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VoiceCallScreen(chat: chat)),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.95),
              chat.avatarStyle.color.withValues(alpha: 0.85),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          border: Border(
            top: BorderSide(color: AppColors.primaryLight.withValues(alpha: 0.3), width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Pulsing mic icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_none_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            AppAvatar(
              style: chat.avatarStyle,
              initials: chat.initials,
              size: 28,
              isGroup: chat.isGroup,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    chat.name,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Голосовой звонок · Нажмите, чтобы вернуться',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => CallManager.instance.endCall(),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
