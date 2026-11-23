import 'package:flutter/material.dart';

import '../models/verdict.dart';
import 'text_styles.dart';
import 'tokens.dart';

/// Verdict meaning colours: the one sanctioned exception to "blue only".
/// Always pair with an icon + word. Use `tint` as the surface, `solid` for icon/label.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.scam,
    required this.suspicious,
    required this.safe,
    required this.tintAlpha,
  });

  final Color scam, suspicious, safe;
  final double tintAlpha;

  // Light hexes were darkened from the design lead's #B25000 / #1A7F37 so that
  // the solid colour clears 4.5:1 on its own tint over parchment (4.15 / 4.09 before).
  static const light = StatusColors(
    scam: Color(0xFFC8102E),
    suspicious: Color(0xFF9A4500),
    safe: Color(0xFF166F2E),
    tintAlpha: 0.10,
  );
  static const dark = StatusColors(
    scam: Color(0xFFFF6961),
    suspicious: Color(0xFFFFB340),
    safe: Color(0xFF30D158),
    tintAlpha: 0.14,
  );

  Color solid(RiskLabel l) => switch (l) {
        RiskLabel.scam => scam,
        RiskLabel.suspicious => suspicious,
        RiskLabel.safe => safe,
      };

  /// Translucent tint; blend over the card surface with [tintOver].
  Color tint(RiskLabel l) => solid(l).withValues(alpha: tintAlpha);

  Color tintOver(RiskLabel l, Color base) => Color.alphaBlend(tint(l), base);

  @override
  StatusColors copyWith({Color? scam, Color? suspicious, Color? safe, double? tintAlpha}) => StatusColors(
        scam: scam ?? this.scam,
        suspicious: suspicious ?? this.suspicious,
        safe: safe ?? this.safe,
        tintAlpha: tintAlpha ?? this.tintAlpha,
      );

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    return StatusColors(
      scam: Color.lerp(scam, other.scam, t)!,
      suspicious: Color.lerp(suspicious, other.suspicious, t)!,
      safe: Color.lerp(safe, other.safe, t)!,
      tintAlpha: tintAlpha + (other.tintAlpha - tintAlpha) * t,
    );
  }
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light, Pal.light, StatusColors.light);
  static ThemeData dark() => _build(Brightness.dark, Pal.dark, StatusColors.dark);

  static ThemeData _build(Brightness b, Pal p, StatusColors st) {
    final scheme = ColorScheme(
      brightness: b,
      primary: p.accent,
      onPrimary: p.onAccent,
      secondary: p.accent,
      onSecondary: p.onAccent,
      error: st.scam,
      onError: b == Brightness.light ? Colors.white : Colors.black,
      surface: p.surface,
      onSurface: p.ink,
      onSurfaceVariant: p.muted,
      outline: p.hairline,
      outlineVariant: p.hairline,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: p.canvas,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surfaceAlt,
      surfaceContainerHighest: p.surfaceAlt,
      shadow: Colors.transparent,
    );
    final text = AppText.textTheme(p.ink);
    final hairline = BorderSide(color: p.hairline);
    final fieldSide = BorderSide(color: p.fieldLine); // hairline is 1.3:1, too faint to find a field by
    const focusSide = BorderSide(color: Pal.focus, width: 2);
    final focusInk = BorderSide(color: p.ink, width: 2); // focus-blue is invisible on a blue fill
    const stadium = StadiumBorder();
    const pad = EdgeInsets.symmetric(horizontal: Sp.xl, vertical: Sp.m);
    const minSize = Size(kTouch, kTouch);

    WidgetStateProperty<Color?> pressedOverlay(Color c) => WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.pressed) ? c.withValues(alpha: 0.12) : null);

    WidgetStateProperty<BorderSide?> side(BorderSide base, BorderSide focus) =>
        WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused) ? focus : base);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.page,
      canvasColor: p.canvas,
      textTheme: text,
      primaryTextTheme: text,
      splashFactory: NoSplash.splashFactory,
      highlightColor: p.accent.withValues(alpha: 0.08),
      hoverColor: p.accent.withValues(alpha: 0.06),
      focusColor: Pal.focus.withValues(alpha: 0.12),
      shadowColor: Colors.transparent,
      dividerColor: p.hairline,
      dividerTheme: DividerThemeData(color: p.hairline, thickness: 1, space: 1),
      extensions: [st],
      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        centerTitle: false,
        toolbarHeight: 64,
        titleTextStyle: AppText.title.copyWith(color: p.ink),
        iconTheme: IconThemeData(color: p.ink, size: 28),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.lg), side: hairline),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(minSize),
          padding: const WidgetStatePropertyAll(pad),
          shape: const WidgetStatePropertyAll(stadium),
          elevation: const WidgetStatePropertyAll(0),
          textStyle: WidgetStatePropertyAll(AppText.label),
          splashFactory: NoSplash.splashFactory,
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled) ? p.hairline : p.accent),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled) ? p.muted : p.onAccent),
          overlayColor: pressedOverlay(p.onAccent),
          side: side(BorderSide.none, focusInk),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(minSize),
          padding: const WidgetStatePropertyAll(pad),
          shape: const WidgetStatePropertyAll(stadium),
          elevation: const WidgetStatePropertyAll(0),
          textStyle: WidgetStatePropertyAll(AppText.label),
          splashFactory: NoSplash.splashFactory,
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled) ? p.muted : p.accent),
          overlayColor: pressedOverlay(p.accent),
          side: side(BorderSide(color: p.accent), focusSide),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(minSize),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.m)),
          shape: const WidgetStatePropertyAll(stadium),
          textStyle: WidgetStatePropertyAll(AppText.label),
          splashFactory: NoSplash.splashFactory,
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled) ? p.muted : p.accent),
          overlayColor: pressedOverlay(p.accent),
          side: side(BorderSide.none, focusSide),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(minSize),
          iconSize: const WidgetStatePropertyAll(28),
          foregroundColor: WidgetStatePropertyAll(p.accent),
          splashFactory: NoSplash.splashFactory,
          overlayColor: pressedOverlay(p.accent),
          side: side(BorderSide.none, focusSide),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.all(Sp.l),
        hintStyle: AppText.body.copyWith(color: p.muted),
        labelStyle: AppText.caption.copyWith(color: p.muted),
        floatingLabelStyle: AppText.caption.copyWith(color: p.accent),
        helperStyle: AppText.caption.copyWith(color: p.muted),
        errorStyle: AppText.caption.copyWith(color: st.scam),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.md), borderSide: fieldSide),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.md), borderSide: fieldSide),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.md), borderSide: focusSide),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.md), borderSide: BorderSide(color: st.scam)),
        focusedErrorBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.md), borderSide: BorderSide(color: st.scam, width: 2)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceAlt,
        selectedColor: p.accent.withValues(alpha: 0.12),
        side: hairline,
        shape: const StadiumBorder(),
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
        labelStyle: AppText.caption.copyWith(color: p.ink),
        padding: const EdgeInsets.symmetric(horizontal: Sp.s, vertical: Sp.s),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.canvas,
        elevation: 0,
        height: 80,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: p.accent.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 32, color: s.contains(WidgetState.selected) ? p.accent : p.muted)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => AppText.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.selected) ? p.accent : p.muted)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.ink,
        textColor: p.ink,
        minTileHeight: kTouch,
        contentPadding: const EdgeInsets.symmetric(horizontal: Sp.l),
        titleTextStyle: AppText.bodyStrong.copyWith(color: p.ink),
        subtitleTextStyle: AppText.caption.copyWith(color: p.muted),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.accent : p.muted),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.canvas,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.lg), side: hairline),
        titleTextStyle: AppText.title.copyWith(color: p.ink),
        contentTextStyle: AppText.body.copyWith(color: p.ink),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.ink,
        contentTextStyle: AppText.body.copyWith(color: p.canvas),
        actionTextColor: b == Brightness.light ? Pal.dark.accent : Pal.light.accent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.md)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.hairline,
        linearMinHeight: 8,
        borderRadius: BorderRadius.circular(Rad.pill),
      ),
    );
  }
}
