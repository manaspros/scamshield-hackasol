import 'package:flutter/material.dart';

/// Platform font (Roboto + Noto Sans Devanagari on Android). Letter spacing stays 0
/// so Devanagari matras never collide. Weights 400/600/700 only; nothing below 16.
abstract final class AppText {
  static const _w4 = FontWeight.w400, _w6 = FontWeight.w600, _w7 = FontWeight.w700;

  static TextStyle _s(double size, FontWeight w, double h) =>
      TextStyle(fontSize: size, fontWeight: w, height: h, letterSpacing: 0);

  static final display = _s(34, _w7, 1.15);
  static final headline = _s(28, _w6, 1.2);
  static final title = _s(22, _w6, 1.3);
  static final body = _s(20, _w4, 1.5);
  static final bodyStrong = _s(20, _w6, 1.5);
  static final label = _s(20, _w6, 1.2);
  static final caption = _s(16, _w4, 1.45);

  static TextTheme textTheme(Color ink) => TextTheme(
        displayLarge: display,
        displayMedium: display,
        displaySmall: display,
        headlineLarge: headline,
        headlineMedium: headline,
        headlineSmall: title,
        titleLarge: title,
        titleMedium: bodyStrong,
        titleSmall: _s(16, _w6, 1.45),
        bodyLarge: body,
        bodyMedium: body,
        bodySmall: caption,
        labelLarge: label,
        labelMedium: _s(16, _w6, 1.3),
        labelSmall: _s(16, _w6, 1.3),
      ).apply(bodyColor: ink, displayColor: ink);
}
