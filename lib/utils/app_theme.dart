import 'package:flutter/material.dart';

class AppTheme {
  // ── Base backgrounds ─────────────────────────────────────────────────────
  static const Color bg        = Color(0xFF0F1117);
  static const Color bgDark    = Color(0xFF080B10);
  static const Color sidebar   = Color(0xFF13161D);
  static const Color card      = Color(0xFF1A1D26);
  static const Color cardAlt   = Color(0xFF20242F);
  static const Color surface   = Color(0xFF1A1D26);
  static const Color surfaceAlt= Color(0xFF20242F);

  // Legacy aliases
  static const Color panel     = Color(0xFF1A1D26);
  static const Color panelSoft = Color(0xFF20242F);
  static const Color bgSecondary = Color(0xFF080B10);

  // ── Accents ───────────────────────────────────────────────────────────────
  static const Color primary   = Color(0xFF6C63FF);
  static const Color primaryLt = Color(0xFF9B95FF);
  static const Color accent    = Color(0xFF6C63FF);
  static const Color secondary = Color(0xFFF5A623);
  static const Color accentPink= Color(0xFFFF6B9D);
  static const Color cyan      = Color(0xFF00D4FF);
  static const Color emerald   = Color(0xFF00E5A0);
  static const Color purple    = Color(0xFFB44FFF);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFF0F2F8);
  static const Color textSecondary = Color(0xFF7B82A0);
  static const Color textMuted     = Color(0xFF464C68);
  static const Color border        = Color(0xFF1F2235);

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF00E5A0);
  static const Color warning = Color(0xFFF5A623);
  static const Color error   = Color(0xFFFF4D6A);
  static const Color info    = Color(0xFF00D4FF);

  // ── Timetable ─────────────────────────────────────────────────────────────
  static const Color theoryColor   = Color(0xFF6C63FF);
  static const Color labColor      = Color(0xFFF5A623);
  static const Color specialColor  = Color(0xFFFF6B9D);
  static const Color reservedColor = Color(0xFFFF6B9D);
  static const Color freeColor     = Color(0xFF1A1D26);
  static const Color breakColor    = Color(0xFF13161D);

  // ── Gradients ─────────────────────────────────────────────────────────────
  static LinearGradient get purpleGradient => const LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF7B6FFF), Color(0xFF5B4FEF)]);

  static LinearGradient get orangeGradient => const LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFF5A623), Color(0xFFE08810)]);

  static LinearGradient get cyanGradient => const LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF00D4FF), Color(0xFF0099DD)]);

  static LinearGradient get greenGradient => const LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF00E5A0), Color(0xFF00B87A)]);

  static LinearGradient get heroGradient    => purpleGradient;
  static LinearGradient get brandGradient   => purpleGradient;
  static LinearGradient get pageGradient    => const LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF080B10), Color(0xFF0F1117)]);

  // ── Shadows ───────────────────────────────────────────────────────────────
  static BoxShadow get glowPurple => BoxShadow(
    color: primary.withOpacity(0.35),
    blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 8));

  static BoxShadow get glowOrange => BoxShadow(
    color: secondary.withOpacity(0.35),
    blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 8));

  static BoxShadow get cardShadow => BoxShadow(
    color: Colors.black.withOpacity(0.4),
    blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 8));

  static BoxShadow get glowBlue => glowPurple;
  static BoxShadow get glowPink => BoxShadow(
    color: accentPink.withOpacity(0.3),
    blurRadius: 20, offset: const Offset(0, 8));

  // ── Legacy aliases used by ds.dart / app_sidebar / faculty / student ──────
  static LinearGradient get purpleGrad => purpleGradient;
  static const Color surfaceEl = Color(0xFF20242F);
  static const Color amber     = Color(0xFFF5A623);
  static const Color rose      = Color(0xFFFF4D6A);

  static Color periodColor(bool isLab, bool isSpecial, bool isFree) {
    if (isSpecial) return specialColor;
    if (isFree)    return freeColor;
    if (isLab)     return labColor;
    return theoryColor;
  }

  static ThemeData get theme {
    return ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: primary, secondary: secondary,
        surface: card, error: error),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent, elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary),
      cardTheme: CardThemeData(
        color: card, elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: cardAlt,
        hintStyle: const TextStyle(color: textMuted),
        labelStyle: const TextStyle(color: textSecondary),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primary, width: 1.5))),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: WidgetStateProperty.all(0),
          backgroundColor: WidgetStateProperty.all(primary),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          shape: WidgetStateProperty.all(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12))),
          textStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(textPrimary),
          side: WidgetStateProperty.all(const BorderSide(color: border)),
          shape: WidgetStateProperty.all(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12))))),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primaryLt)),
      tabBarTheme: const TabBarThemeData(
        labelColor: textPrimary,
        unselectedLabelColor: textSecondary,
        indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: primary, width: 2)),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      checkboxTheme: CheckboxThemeData(
        checkColor: WidgetStateProperty.all(Colors.white),
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : cardAlt),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardAlt,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating),
    );
  }
}
