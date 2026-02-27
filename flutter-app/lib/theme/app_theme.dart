import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/theme_notifier.dart';

/// Shadcn/ui inspired color palette — zinc dark + violet primary
abstract class AppColors {
  static bool get _dark => ThemeNotifier.instance.isDark;

  // ── Backgrounds ─────────────────────────────────────────────────────────────
  static Color get bgBase   => _dark ? const Color(0xFF09090B) : const Color(0xFFFAFAFA);
  static Color get bgSubtle => _dark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5);
  static Color get card     => _dark ? const Color(0xFF1C1C1F) : const Color(0xFFFFFFFF);
  static Color get muted    => _dark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);
  static Color get border   => _dark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8);

  // ── Primary — violet ────────────────────────────────────────────────────────
  static const Color primary      = Color(0xFF7C3AED); // violet-600
  static const Color primaryLight = Color(0xFF8B5CF6); // violet-500
  static const Color primaryDark  = Color(0xFF6D28D9); // violet-700

  // ── Accent — cyan ───────────────────────────────────────────────────────────
  static const Color accent = Color(0xFF06B6D4); // cyan-500

  // ── Text ────────────────────────────────────────────────────────────────────
  static Color get foreground       => _dark ? const Color(0xFFFAFAFA) : const Color(0xFF18181B);
  static Color get mutedForeground  => _dark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);
  static Color get subtleForeground => _dark ? const Color(0xFF71717A) : const Color(0xFF71717A);

  // ── Semantic ────────────────────────────────────────────────────────────────
  static const Color online      = Color(0xFF22C55E); // green-500
  static const Color destructive = Color(0xFFEF4444); // red-500

  // ── Gradients ───────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF7C3AED), Color(0xFF06B6D4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get bgGradient => _dark
      ? const LinearGradient(
          colors: [Color(0xFF09090B), Color(0xFF0D0D17)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        )
      : const LinearGradient(
          colors: [Color(0xFFFAFAFA), Color(0xFFF4F4F5)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
}

abstract class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFFAFAFA),
      colorScheme: const ColorScheme.light(
        primary:     AppColors.primary,
        secondary:   AppColors.accent,
        surface:     Color(0xFFF4F4F5),
        onPrimary:   Colors.white,
        onSecondary: Colors.white,
        onSurface:   Color(0xFF18181B),
        outline:     Color(0xFFE4E4E7),
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      inputDecorationTheme: InputDecorationTheme(
        filled:    true,
        fillColor: const Color(0xFFF4F4F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: const DividerThemeData(
        color:     Color(0xFFE4E4E7),
        thickness: 0.5,
        space:     0,
      ),
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgBase,

      colorScheme: ColorScheme.dark(
        primary:    AppColors.primary,
        secondary:  AppColors.accent,
        surface:    AppColors.bgSubtle,
        onPrimary:  Colors.white,
        onSecondary: Colors.white,
        onSurface:  AppColors.foreground,
        outline:    AppColors.border,
      ),

      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor:    AppColors.foreground,
        displayColor: AppColors.foreground,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled:    true,
        fillColor: AppColors.bgSubtle,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: TextStyle(color: AppColors.mutedForeground),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      cardTheme: CardThemeData(
        color: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.border, width: 0.5),
        ),
        elevation: 0,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor:         AppColors.bgBase,
        elevation:               0,
        scrolledUnderElevation:  0,
        titleTextStyle: GoogleFonts.inter(
          color:        AppColors.foreground,
          fontSize:     20,
          fontWeight:   FontWeight.w700,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: AppColors.foreground),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor:       AppColors.bgSubtle,
        selectedIconTheme:     const IconThemeData(color: AppColors.primary),
        unselectedIconTheme:   IconThemeData(color: AppColors.mutedForeground),
        selectedLabelTextStyle: GoogleFonts.inter(
          color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: GoogleFonts.inter(
          color: AppColors.mutedForeground, fontSize: 12),
      ),

      dividerTheme: DividerThemeData(
        color:     AppColors.border,
        thickness: 0.5,
        space:     0,
      ),
    );
  }
}
