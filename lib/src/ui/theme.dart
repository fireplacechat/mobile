import 'package:flutter/material.dart';

import 'design_tokens.dart';

class FP {
  static const ember = Color(0xFFE8590C);
  static const flame = Color(0xFFC92A2A);
  static const gold = Color(0xFFFFB347);
  static const hearth = Color(0xFF4E2A1A);
  static const brick = Color(0xFF7A3B24);
  static const cream = Color(0xFFFFF4E6);
  static const sand = Color(0xFFF3DFC8);
  static const night = Color(0xFF1C1210);
  static const coal = Color(0xFF2A1B16);
}

ThemeData fireplaceTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final t = dark ? FireplaceUiTokens.dark : FireplaceUiTokens.light;
  final fontFamily = ThemeData(brightness: brightness)
      .textTheme
      .bodyMedium!
      .fontFamily;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: t.accent,
        brightness: brightness,
      ).copyWith(
        primary: t.accent,
        onPrimary: Colors.white,
        surface: t.page,
        onSurface: t.text,
        onSurfaceVariant: t.secondaryText,
        surfaceContainerHighest: t.panel,
        outlineVariant: t.separator,
        error: t.danger,
      );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: t.separator),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[t],
    scaffoldBackgroundColor: t.page,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: t.text,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: t.text,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: t.text,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: t.text,
      ),
      titleSmall: TextStyle(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: t.text,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: t.text),
      bodyMedium: TextStyle(fontSize: 16, height: 1.5, color: t.text),
      bodySmall: TextStyle(fontSize: 14, height: 1.45, color: t.secondaryText),
      labelLarge: TextStyle(
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: t.text,
      ),
      labelSmall: TextStyle(fontSize: 12, height: 1.4, color: t.secondaryText),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: t.page,
      foregroundColor: t.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        color: t.text,
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: t.panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: t.separator),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.separator, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      iconColor: t.secondaryText,
      textColor: t.text,
      selectedTileColor: t.selectedRow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: t.secondaryText,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.accent,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: TextStyle(color: t.secondaryText),
      hintStyle: TextStyle(color: t.secondaryText),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: t.accent, width: 2),
      ),
      errorBorder: border.copyWith(borderSide: BorderSide(color: t.danger)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        side: BorderSide(color: t.separator),
        foregroundColor: t.accentText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: t.accentText,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.page,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    chipTheme: ChipThemeData(
      backgroundColor: t.panel,
      selectedColor: t.selectedRow,
      side: BorderSide(color: t.separator),
      labelStyle: TextStyle(
        color: t.text,
        fontSize: 14,
        fontFamily: fontFamily,
      ),
      checkmarkColor: t.accentText,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
