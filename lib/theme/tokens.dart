import 'package:flutter/material.dart';

/// Spacing on an 8px base.
abstract final class Sp {
  static const double xs = 4, s = 8, m = 12, l = 16, xl = 24, xxl = 32, x3 = 48, x4 = 80;
}

/// Corner radii.
abstract final class Rad {
  static const double sm = 8, md = 11, lg = 18, pill = 9999;
}

/// Minimum touch target edge, dp.
const double kTouch = 56;

/// One colour set per brightness. Blue (`accent`) is the only interactive colour.
class Pal {
  const Pal({
    required this.canvas,
    required this.page,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.accent,
    required this.onAccent,
  });

  final Color canvas; // app bar, dialogs
  final Color page; // scaffold background
  final Color surface; // cards
  final Color surfaceAlt; // inputs, chips, nav
  final Color ink;
  final Color muted;
  final Color hairline;
  final Color accent;
  final Color onAccent;

  static const Color focus = Color(0xFF0071E3);

  static const light = Pal(
    canvas: Color(0xFFFFFFFF),
    page: Color(0xFFF5F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFAFAFC),
    ink: Color(0xFF1D1D1F),
    muted: Color(0xFF6E6E73), // 4.66:1 on parchment; DESIGN.md's #7A7A7A fails AA
    hairline: Color(0xFFE0E0E0),
    accent: Color(0xFF0066CC),
    onAccent: Color(0xFFFFFFFF),
  );

  static const dark = Pal(
    canvas: Color(0xFF000000),
    page: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceAlt: Color(0xFF272729),
    ink: Color(0xFFF5F5F7),
    muted: Color(0xFFA1A1A6),
    hairline: Color(0xFF38383A),
    accent: Color(0xFF2997FF),
    onAccent: Color(0xFF000000), // white on Sky Blue is only 3.0:1
  );
}
