import 'package:flutter/material.dart';

const Color appSeed = Color(0xFF0175C2);
const Color appSeedSoft = Color(0xFF6CB6FF);

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(seedColor: appSeed, brightness: brightness);
  final scheme = base.copyWith(
    primary: dark ? appSeedSoft : appSeed,
    onPrimary: dark ? const Color(0xFF002F5A) : Colors.white,
    primaryContainer: dark ? const Color(0xFF004B7A) : const Color(0xFFD6E9FA),
    onPrimaryContainer: dark
        ? const Color(0xFFD6E9FA)
        : const Color(0xFF001D33),
    surface: dark ? const Color(0xFF171B22) : const Color(0xFFFFFFFF),
    surfaceContainerHighest: dark
        ? const Color(0xFF232A35)
        : const Color(0xFFEEF2F7),
    outlineVariant: dark ? const Color(0xFF2B3340) : const Color(0xFFDDE3EA),
    error: dark ? const Color(0xFFFF8D8D) : const Color(0xFFC02A3A),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF0F1218)
        : const Color(0xFFF5F7FA),
    visualDensity: VisualDensity.compact,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1C222B) : const Color(0xFFF8FAFC),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: TextStyle(fontSize: 12, color: scheme.onSurface),
      secondaryLabelStyle: TextStyle(
        fontSize: 12,
        color: scheme.onSecondaryContainer,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      linearMinHeight: 6,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
    ),
  );
}
