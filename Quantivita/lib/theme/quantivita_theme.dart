import 'package:flutter/material.dart';

import 'quantivita_colors.dart';

abstract final class QuantivitaTheme {
  static ThemeData light() {
    return _theme(
      brightness: Brightness.light,
      background: QuantivitaColors.lightBackground,
      surface: QuantivitaColors.lightSurface,
      surfaceContainer: QuantivitaColors.lightSurfaceElevated,
      outline: QuantivitaColors.lightOutline,
      onSurface: QuantivitaColors.ink,
      body: QuantivitaColors.lightBody,
      muted: QuantivitaColors.lightMuted,
    );
  }

  static ThemeData dark() {
    return _theme(
      brightness: Brightness.dark,
      background: QuantivitaColors.background,
      surface: QuantivitaColors.surface,
      surfaceContainer: QuantivitaColors.surfaceElevated,
      outline: QuantivitaColors.outline,
      onSurface: QuantivitaColors.ivory,
      body: QuantivitaColors.body,
      muted: QuantivitaColors.muted,
      primary: QuantivitaColors.recoveryDark,
      secondary: QuantivitaColors.sleepDark,
      tertiary: QuantivitaColors.strainDark,
    );
  }

  static ThemeData _theme({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceContainer,
    required Color outline,
    required Color onSurface,
    required Color body,
    required Color muted,
    Color primary = QuantivitaColors.recovery,
    Color secondary = QuantivitaColors.sleep,
    Color tertiary = QuantivitaColors.strain,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      fontFamily: 'SF Pro Display',
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        secondary: secondary,
        tertiary: tertiary,
        error: const Color(0xFFFF5A6A),
        onError: Colors.white,
        surface: surface,
        surfaceContainerHighest: surfaceContainer,
        outline: outline,
        onPrimary: QuantivitaColors.onAccent,
        onSecondary: QuantivitaColors.onAccent,
        onTertiary: QuantivitaColors.onAccent,
        onSurface: onSurface,
      ),
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontSize: 40,
          height: 0.95,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
          color: onSurface,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          height: 1.05,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
          color: onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          height: 1.15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.2,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: body,
          letterSpacing: 0,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          height: 1.1,
          fontWeight: FontWeight.w800,
          color: muted,
          letterSpacing: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: outline),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          backgroundColor: surfaceContainer,
          foregroundColor: onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: outline),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
      ),
    );
  }
}
