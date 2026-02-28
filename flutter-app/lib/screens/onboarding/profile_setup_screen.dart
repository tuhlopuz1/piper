import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../services/ipc_service.dart';
import '../../widgets/app_avatar.dart';
import '../home/home_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  AvatarStyle _avatar = AvatarStyle.violet;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() => _ready = _ctrl.text.trim().isNotEmpty));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _done() {
    if (!_ready) return;
    _focus.unfocus();
    // Update daemon with user's chosen name and avatar colour
    IpcService.instance.setProfile(
      _ctrl.text.trim(),
      '#${_avatar.color.toARGB32().toRadixString(16).substring(2)}',
    );
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 450),
      ),
    );
  }

  String get _initials {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return '?';
    final parts = t.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return t.substring(0, t.length.clamp(0, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _focus.unfocus(),
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(gradient: AppColors.bgGradient),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 56),

                  // ── Header ──────────────────────────────────────────────────
                  Text(
                    'Создайте профиль',
                    style: GoogleFonts.inter(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground,
                      letterSpacing: -1,
                    ),
                  ).animate(delay: 50.ms).fadeIn(duration: 400.ms).slideY(
                      begin: 0.2, end: 0, duration: 400.ms),

                  const SizedBox(height: 6),

                  Text(
                    'Вас увидят другие пользователи сети',
                    style: GoogleFonts.inter(
                        fontSize: 14, color: AppColors.mutedForeground),
                  ).animate(delay: 100.ms).fadeIn(duration: 400.ms),

                  const SizedBox(height: 44),

                  // ── Avatar preview ──────────────────────────────────────────
                  Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AppAvatar(
                          style: _avatar,
                          initials: _initials,
                          size: 88,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppColors.bgBase, width: 2.5),
                            ),
                            child: const Icon(Icons.edit_rounded,
                                color: Colors.white, size: 13),
                          ),
                        ),
                      ],
                    ),
                  )
                      .animate(delay: 150.ms)
                      .fadeIn(duration: 500.ms)
                      .scale(
                          begin: const Offset(0.8, 0.8),
                          end: const Offset(1, 1),
                          duration: 500.ms,
                          curve: Curves.easeOutBack),

                  const SizedBox(height: 40),

                  // ── Name input ──────────────────────────────────────────────
                  Text(
                    'Ваше имя или никнейм',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedForeground,
                      letterSpacing: 0.4,
                    ),
                  ).animate(delay: 200.ms).fadeIn(duration: 400.ms),

                  const SizedBox(height: 8),

                  TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Например: Alex или alex_99',
                      prefixIcon: Icon(Icons.person_outline_rounded,
                          color: AppColors.mutedForeground, size: 20),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _done(),
                  ).animate(delay: 250.ms).fadeIn(duration: 400.ms).slideY(
                      begin: 0.1, end: 0, duration: 400.ms),

                  const SizedBox(height: 36),

                  // ── Avatar selector ─────────────────────────────────────────
                  Text(
                    'Выберите аватар',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedForeground,
                      letterSpacing: 0.4,
                    ),
                  ).animate(delay: 300.ms).fadeIn(duration: 400.ms),

                  const SizedBox(height: 14),

                  _AvatarGrid(
                    selected: _avatar,
                    onSelect: (s) => setState(() => _avatar = s),
                  ).animate(delay: 340.ms).fadeIn(duration: 400.ms),

                  const SizedBox(height: 52),

                  // ── Done button ─────────────────────────────────────────────
                  _DoneButton(isReady: _ready, onTap: _done)
                      .animate(delay: 400.ms)
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.2, end: 0, duration: 400.ms),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Avatar grid ──────────────────────────────────────────────────────────────

class _AvatarGrid extends StatelessWidget {
  final AvatarStyle selected;
  final ValueChanged<AvatarStyle> onSelect;

  const _AvatarGrid({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: AvatarStyle.values.map((style) {
        final isSelected = style == selected;
        return GestureDetector(
          onTap: () => onSelect(style),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: style.color.withValues(alpha: isSelected ? 1.0 : 0.12),
              border: Border.all(
                color: isSelected ? style.color : AppColors.border,
                width: isSelected ? 2.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: style.color.withValues(alpha: 0.4),
                        blurRadius: 14,
                      )
                    ]
                  : null,
            ),
            child: Center(
              child: AnimatedScale(
                scale: isSelected ? 1.0 : 0.8,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  style.emoji,
                  style: TextStyle(fontSize: isSelected ? 26 : 22),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Done button ──────────────────────────────────────────────────────────────

class _DoneButton extends StatefulWidget {
  final bool isReady;
  final VoidCallback onTap;

  const _DoneButton({required this.isReady, required this.onTap});

  @override
  State<_DoneButton> createState() => _DoneButtonState();
}

class _DoneButtonState extends State<_DoneButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isReady ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.isReady
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            gradient: widget.isReady ? AppColors.primaryGradient : null,
            color: widget.isReady ? null : AppColors.muted,
            borderRadius: BorderRadius.circular(12),
            boxShadow: widget.isReady
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.38),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    )
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              'Готово',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: widget.isReady
                    ? Colors.white
                    : AppColors.mutedForeground,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
