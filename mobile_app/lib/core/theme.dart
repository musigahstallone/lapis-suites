import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// Lapis Suites Strict 3-Color Executive System (Neutral Canvas + 3 Accents):
///   Neutral:  #F8FAFC canvas, #FFFFFF surface, #172033 / #64748B slate text, #E2E8F0 border
///   Color 1:  Lapis Navy  (#111B35) — Brand, primary CTAs, hero, active navigation
///   Color 2:  Emerald     (#059669) — Payments received, occupied, active, resolved
///   Color 3:  Alert       (#B45309 amber pending / #B91C1C crimson error)
/// Fonts: Strictly Google Sans, Google Sans Flex, Google Sans Code
class C {
  // Neutral Canvas & Surfaces
  static const canvas = Color(0xFFF8FAFC);
  static const scaffold = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const card = Color(0xFFFFFFFF);
  static const cardSubtle = Color(0xFFFAFBFC);

  // Color 1: Lapis Navy (Structural Brand & Primary Actions)
  static const navy = Color(0xFF111B35);
  static const navyBorder = Color(0xFF1E2C4A);
  static const navyHover = Color(0xFF1A284B);
  static const navySoftBg = Color(0xFFF1F5F9);
  static const navySoftBorder = Color(0xFFCBD5E1);

  // Neutral Borders & Text Hierarchy
  static const border = Color(0xFFE2E8F0);
  static const borderLight = Color(0xFFF1F5F9);
  static const divider = Color(0xFFE2E8F0);

  static const textPrimary = Color(0xFF172033);
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF64748B);
  static const textSoft = Color(0xFF94A3B8);

  // Unified Brand Alias (maps into Lapis Navy so UI never exceeds 3 colors)
  static const blueText = Color(0xFF111B35);
  static const blueHover = Color(0xFF1A284B);
  static const blueBg = Color(0xFFF1F5F9);
  static const blueBorder = Color(0xFFCBD5E1);

  // Color 2: Emerald (Success / Paid / Active / Resolved)
  static const mintText = Color(0xFF059669);
  static const mintBg = Color(0xFFECFDF5);
  static const mintBorder = Color(0xFFA7F3D0);

  // Color 3: Alert (Amber Pending + Crimson Error)
  static const amberText = Color(0xFFB45309);
  static const amberBg = Color(0xFFFFFBEB);
  static const amberBorder = Color(0xFFFDE68A);

  static const roseText = Color(0xFFB91C1C);
  static const roseBg = Color(0xFFFEF2F2);
  static const roseBorder = Color(0xFFFECACA);

  // Primary CTA
  static const cta = Color(0xFF111B35);
  static const ctaOn = Color(0xFFFFFFFF);
}

/// Primary UI body font: Google Sans
TextStyle sans(
  double size, {
  Color color = C.textPrimary,
  FontWeight weight = FontWeight.w400,
  double? height,
  double? letterSpacing,
  List<FontFeature>? fontFeatures,
}) =>
    TextStyle(
      fontFamily: 'GoogleSans',
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: height ?? 1.32,
      letterSpacing: letterSpacing ?? -0.1,
      fontFeatures: fontFeatures,
    );

/// Display / Heading / KPI font: Google Sans Flex
TextStyle flex(
  double size, {
  Color color = C.textPrimary,
  FontWeight weight = FontWeight.w700,
  double? height,
  double? letterSpacing,
  List<FontFeature>? fontFeatures,
}) =>
    TextStyle(
      fontFamily: 'GoogleSansFlex',
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: height ?? 1.2,
      letterSpacing: letterSpacing ?? -0.25,
      fontFeatures: fontFeatures,
    );

TextStyle serif(
  double size, {
  Color color = C.textPrimary,
  FontWeight weight = FontWeight.w700,
  double? height,
  double? letterSpacing,
}) =>
    flex(
      size,
      color: color,
      weight: weight,
      height: height,
      letterSpacing: letterSpacing,
    );

/// Special-occasion monospace font: Google Sans Code (OTP digits, M-Pesa refs, Paybill codes)
TextStyle mono(
  double size, {
  Color color = C.textPrimary,
  FontWeight weight = FontWeight.w600,
  double? height,
  double? letterSpacing,
}) =>
    TextStyle(
      fontFamily: 'GoogleSansCode',
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: height ?? 1.25,
      letterSpacing: letterSpacing ?? 0.2,
    );

InputDecoration fieldDecoration({
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? prefixText,
  TextStyle? prefixStyle,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: sans(12.5, color: C.textSoft),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    prefixText: prefixText,
    prefixStyle: prefixStyle,
    filled: true,
    fillColor: C.cardSubtle,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: C.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: C.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: C.navy, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: C.roseText, width: 1.2),
    ),
  );
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'GoogleSans',
  );

  return base.copyWith(
    scaffoldBackgroundColor: C.canvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: C.navy,
      brightness: Brightness.light,
    ).copyWith(
      primary: C.navy,
      onPrimary: C.ctaOn,
      secondary: C.mintText,
      onSecondary: Colors.white,
      surface: C.surface,
      onSurface: C.textPrimary,
      outline: C.border,
      error: C.roseText,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'GoogleSans',
      bodyColor: C.textPrimary,
      displayColor: C.textPrimary,
    ),
    splashFactory: InkRipple.splashFactory,
    dividerTheme: const DividerThemeData(color: C.divider, thickness: 1, space: 1),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: C.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: flex(15, color: C.textPrimary, weight: FontWeight.w700),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: C.cta,
        foregroundColor: C.ctaOn,
        elevation: 0,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: sans(12.5, color: C.ctaOn, weight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.textPrimary,
        side: const BorderSide(color: C.border),
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: sans(12.5, color: C.textPrimary, weight: FontWeight.w600),
      ),
    ),
    cardTheme: const CardThemeData(
      color: C.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: C.border, width: 1),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.navy,
      contentTextStyle: sans(12, color: Colors.white, weight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
