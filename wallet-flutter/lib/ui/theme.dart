import 'package:flutter/material.dart';

/// PDC brand colors (website/css/site.css): deep navy surfaces, electric blue actions, cyan and pink accents.
class PdcColors {
  PdcColors._();

  static const Color navy = Color(0xFF05060D);
  static const Color card = Color(0xFF10132B);
  static const Color blue = Color(0xFF1E30F3);
  static const Color blueDeep = Color(0xFF121D92);
  static const Color cyan = Color(0xFF3BC7FF);
  static const Color pink = Color(0xFFE21E80);

  /// Positive and negative amounts in history: readable on both themes.
  static Color incoming(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF4ADE9A) : const Color(0xFF0B7A4B);
  static Color outgoing(Brightness b) =>
      b == Brightness.dark ? const Color(0xFFFF8FB5) : const Color(0xFFB4235E);
}

class PdcTheme {
  PdcTheme._();

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: PdcColors.blue,
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFF5B6BFF),
          onPrimary: Colors.white,
          primaryContainer: PdcColors.blueDeep,
          onPrimaryContainer: const Color(0xFFDDE1FF),
          secondary: PdcColors.cyan,
          onSecondary: PdcColors.navy,
          secondaryContainer: const Color(0xFF0E3550),
          onSecondaryContainer: const Color(0xFFCDEEFF),
          tertiary: const Color(0xFFFF5CAB),
          surface: const Color(0xFF080A18),
          onSurface: const Color(0xFFF4F6FF),
          onSurfaceVariant: const Color(0xFFB7BDD6),
          surfaceContainerLowest: PdcColors.navy,
          surfaceContainerLow: const Color(0xFF0C0F22),
          surfaceContainer: PdcColors.card,
          surfaceContainerHigh: const Color(0xFF171B3A),
          surfaceContainerHighest: const Color(0xFF1F2447),
          outline: const Color(0xFF5A6190),
          outlineVariant: const Color(0xFF262B52),
          error: const Color(0xFFFF8FA8),
          errorContainer: const Color(0xFF5A1A38),
          onErrorContainer: const Color(0xFFFFD9E5),
        );
    return _build(scheme);
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: PdcColors.blue).copyWith(
      primary: const Color(0xFF2B3CE0),
      onPrimary: Colors.white,
      secondary: const Color(0xFF0A78A8),
      surface: const Color(0xFFF6F7FD),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF0F2FC),
      surfaceContainer: Colors.white,
      surfaceContainerHigh: const Color(0xFFE9ECFA),
      surfaceContainerHighest: const Color(0xFFE0E4F7),
      outlineVariant: const Color(0xFFD5D9EE),
    );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme s) {
    final base = ThemeData(
      colorScheme: s,
      useMaterial3: true,
      brightness: s.brightness,
    );
    final radius = BorderRadius.circular(14);
    return base.copyWith(
      scaffoldBackgroundColor: s.surface,
      visualDensity: VisualDensity.standard,
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: s.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: s.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: s.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: s.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: s.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: s.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: s.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius),
        width: 480,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: s.surfaceContainerLow,
        indicatorColor: s.primaryContainer,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: s.surfaceContainerLow,
        indicatorColor: s.primaryContainer,
        selectedLabelTextStyle: TextStyle(
          color: s.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: s.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(color: s.outlineVariant, space: 1),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide.none,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    );
  }
}
