import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/chat.dart';
import '../../widgets/app_avatar.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _ctrl = TextEditingController(text: 'Мой профиль');
  final _focus = FocusNode();
  AvatarStyle _avatar = AvatarStyle.violet;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _ready => _ctrl.text.trim().isNotEmpty;

  void _save() {
    if (!_ready) return;
    _focus.unfocus();
    Navigator.pop(context);
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
        backgroundColor: AppColors.bgBase,
        body: Container(
          decoration: BoxDecoration(gradient: AppColors.bgGradient),
          child: SafeArea(
            child: Column(
              children: [
                // ── App bar ─────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.bgSubtle,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border, width: 0.5),
                          ),
                          child: Icon(Icons.arrow_back_ios_new_rounded,
                              color: AppColors.foreground, size: 16),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Редактировать профиль',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.foreground,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Content ─────────────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 32),

                        // ── Avatar preview ──────────────────────────────────
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
                        ),

                        const SizedBox(height: 36),

                        // ── Name label ──────────────────────────────────────
                        Text(
                          'Имя или никнейм',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.mutedForeground,
                            letterSpacing: 0.4,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // ── Name field ──────────────────────────────────────
                        TextField(
                          controller: _ctrl,
                          focusNode: _focus,
                          onChanged: (_) => setState(() {}),
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
                          onSubmitted: (_) => _save(),
                        ),

                        const SizedBox(height: 32),

                        // ── Avatar selector ─────────────────────────────────
                        Text(
                          'Выберите аватар',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.mutedForeground,
                            letterSpacing: 0.4,
                          ),
                        ),

                        const SizedBox(height: 14),

                        _AvatarGrid(
                          selected: _avatar,
                          onSelect: (s) => setState(() => _avatar = s),
                        ),

                        const SizedBox(height: 40),

                        // ── Save button ─────────────────────────────────────
                        _SaveButton(isReady: _ready, onTap: _save),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
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

// ─── Save button ──────────────────────────────────────────────────────────────

class _SaveButton extends StatefulWidget {
  final bool isReady;
  final VoidCallback onTap;

  const _SaveButton({required this.isReady, required this.onTap});

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
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
              'Сохранить',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: widget.isReady ? Colors.white : AppColors.mutedForeground,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
