import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xinji/app/theme/app_palette.dart';
import 'package:xinji/app/theme/app_tokens.dart';

class AppTheme {
  const AppTheme._();

  static const fontFamily = 'Figtree';

  static ThemeData light([Color? accent]) =>
      _build(Brightness.light, accent ?? AppPalette.brand, false);

  static ThemeData dark([Color? accent, bool oled = false]) =>
      _build(Brightness.dark, accent ?? AppPalette.brand, oled);

  static BorderSide cardEdge(bool isDark) => BorderSide(
    color: isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05),
  );

  static Color adaptAccent(Color accent, bool isDark) {
    final luminance = accent.computeLuminance();
    if (isDark && luminance < 0.06) return const Color(0xFFF2F2F2);
    if (!isDark && luminance > 0.82) return const Color(0xFF1C1C1E);
    return accent;
  }

  static SystemUiOverlayStyle systemBars(Brightness brightness) {
    final icons = brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;

    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: brightness,
      statusBarIconBrightness: icons,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarContrastEnforced: true,
    );
  }

  static ThemeData _build(Brightness brightness, Color seed, bool oled) {
    final isDark = brightness == Brightness.dark;
    final accent = adaptAccent(seed, isDark);

    // 背景与内容分层（参考 Streak）：scaffold 背景最暗、surface（底栏层级）
    // 次之、卡片最亮，三层拉开亮度差让内容边界清晰可辨。
    final scaffoldColor = isDark
        ? (oled ? const Color(0xFF000000) : AppPalette.darkBackground)
        : const Color(0xFFEDEDF3);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: accent.computeLuminance() > 0.5
              ? Colors.black
              : Colors.white,
          surface: isDark
              ? (oled ? const Color(0xFF121212) : AppPalette.darkSurface)
              : const Color(0xFFFAFAFC),
          surfaceContainer: isDark
              ? (oled ? const Color(0xFF0A0A0B) : const Color(0xFF1A1A1A))
              : const Color(0xFFEAEAF0),
          surfaceContainerHigh: isDark
              ? (oled ? const Color(0xFF121214) : const Color(0xFF1F1F22))
              : const Color(0xFFE3E3EB),
          surfaceContainerHighest: isDark
              ? (oled ? const Color(0xFF1A1A1E) : AppPalette.darkElevated)
              : const Color(0xFFDCDCE4),
          outlineVariant: isDark
              ? AppPalette.darkBorder
              : const Color(0xFFD9D9E0),
        );

    // OLED：背景纯黑省电，卡片仍用深灰（Streak 纯黑背景时同此做法），
    // 否则卡片与背景完全同色，边界只剩一圈描边。
    final cardColor = isDark
        ? (oled ? const Color(0xFF131313) : AppPalette.darkCard)
        : Colors.white;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,

      scaffoldBackgroundColor: scaffoldColor,
      fontFamily: fontFamily,
      visualDensity: VisualDensity.standard,
      splashFactory: NoSplash.splashFactory,
      extensions: [isDark ? AppTokens.dark : AppTokens.light],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        systemOverlayStyle: systemBars(brightness),
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: isDark ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: isDark ? cardEdge(isDark) : BorderSide.none,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
        ),
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}
