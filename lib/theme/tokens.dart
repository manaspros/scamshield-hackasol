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
    required this.fieldLine,
    required this.accent,
    required this.onAccent,
  });

  final Color canvas; // app bar, dialogs
  final Color page; // scaffold background
  final Color surface; // cards
  final Color surfaceAlt; // inputs, chips, nav
  final Color ink;
  final Color muted;
  final Color hairline; // decorative dividers only (not a boundary anyone must see)
  final Color fieldLine; // input outlines: >= 3:1 on the field fill and the page (WCAG 1.4.11)
  final Color accent;
  final Color onAccent;

  static const Color focus = Color(0xFF0071E3);

  static const light = Pal(
    canvas: Color(0xFFFFFFFF),
    page: Color(0xFFF5F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFAFAFC),
    ink: Color(0xFF1D1D1F),
    // 5.5:1 on page, 5.2:1 on #EEEEF1, 4.8:1 on accentTint; #6E6E73 was 4.38:1 on #EEEEF1
    muted: Color(0xFF636366),
    hairline: Color(0xFFE0E0E0),
    fieldLine: Color(0xFF86868B), // 3.6:1 on white, 3.3:1 on page
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
    fieldLine: Color(0xFF7C7C80), // 4.1:1 on #1C1C1E, 5.1:1 on black
    accent: Color(0xFF2997FF),
    onAccent: Color(0xFF000000), // white on Sky Blue is only 3.0:1
  );
}

/// Soft elevation for the premium look: cards float a little, islands float a lot.
abstract final class Elev {
  static List<BoxShadow> card(Brightness b) => b == Brightness.dark
      ? const [BoxShadow(color: Color(0x0DFFFFFF), spreadRadius: 1)]
      : const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0F000000), blurRadius: 24, offset: Offset(0, 8)),
        ];

  static List<BoxShadow> island(Brightness b) => b == Brightness.dark
      ? const [
          BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x14FFFFFF), spreadRadius: 1),
        ]
      : const [
          BoxShadow(color: Color(0x24000000), blurRadius: 30, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x0D000000), spreadRadius: 1),
        ];
}

/// Large radii used by the redesign (cards 22, islands 28).
abstract final class RadX {
  static const double card = 22, island = 28, sheet = 32;
}

extension PalX on Pal {
  bool get isDark => page == Pal.dark.page;

  /// Accent wash behind selected / informational things.
  Color get accentTint => accent.withValues(alpha: isDark ? 0.18 : 0.10);

  /// Island (floating overlay) fill: slightly translucent so the blur shows through.
  Color get island => isDark ? const Color(0xF22C2C2E) : const Color(0xF5FFFFFF);
}

/// The palette for the current theme brightness.
Pal palOf(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Pal.dark : Pal.light;
