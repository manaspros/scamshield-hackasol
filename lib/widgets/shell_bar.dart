import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../l10n/strings_shell.dart';
import '../screens/report_screen.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'island.dart';

/// Chrome stops growing at 1.2x so it fits at system 2.0x; page content keeps full scale.
Widget clampedChrome(Widget child) =>
    Builder(builder: (context) => MediaQuery.withClampedTextScaling(maxScaleFactor: 1.2, child: child));

/// The app bar every screen uses: title, then the language island, the theme toggle and Report.
PreferredSizeWidget shellBar({Widget? title, String? titleText, bool showReport = true, VoidCallback? onReport}) =>
    PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: clampedChrome(
        AppBar(
          title: title ?? (titleText == null ? null : Text(titleText, overflow: TextOverflow.ellipsis)),
          titleSpacing: Sp.l,
          actions: [
            const LanguageButton(),
            const ThemeToggleButton(),
            if (showReport) ReportButton(onTap: onReport),
            const SizedBox(width: Sp.m),
          ],
        ),
      ),
    );

/// Opens the 1930 report flow under the shell bar (without its own Report button).
Future<void> openReport(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (ctx) => Scaffold(
      appBar: shellBar(titleText: shellT(AppLanguage.of(ctx), 'report_title'), showReport: false),
      body: const ReportScreen(),
    ),
  ),
);

/// "文A": the translate mark, drawn with text so it stays crisp and bold at any size.
class TranslateGlyph extends StatelessWidget {
  const TranslateGlyph({super.key, this.size = 24, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? palOf(context).ink;
    final s = TextStyle(color: c, fontWeight: FontWeight.w900, height: 1, fontSize: size * 0.56, letterSpacing: 0);
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            Positioned(left: 0, top: 0, child: Text('文', style: s)),
            Positioned(right: 0, bottom: 0, child: Text('A', style: s)),
          ],
        ),
      ),
    );
  }
}

const _langRows = [
  ('en', 'English', 'English', 'EN', 'A'),
  ('hi', 'हिंदी', 'Hindi', 'हिं', 'अ'),
  ('hne', 'छत्तीसगढ़ी', 'Chhattisgarhi', 'छग', 'छ'),
];

/// Top-bar language switch: no border or fill, bold glyph + short code; opens a floating island list.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    final p = palOf(context);
    final th = Theme.of(context);
    final cur = _langRows.firstWhere((r) => r.$1 == lang, orElse: () => _langRows[1]);
    return IslandMenu<String>(
      header: 'LANGUAGE · भाषा',
      width: 264,
      onSelected: AppLanguage.set,
      items: [
        for (final r in _langRows)
          IslandMenuItem(
            key: Key('lang_menu_${r.$1}'),
            value: r.$1,
            label: r.$2,
            caption: r.$3,
            selected: r.$1 == lang,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: p.isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF0F0F2),
              child: Text(
                r.$5,
                style: th.textTheme.titleSmall?.copyWith(color: p.ink, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
      builder: (context, open, toggle) => Semantics(
        button: true,
        label: shellT(lang, 'lang_sem').replaceAll('{0}', cur.$2),
        excludeSemantics: true,
        child: InkWell(
          key: const Key('btn_lang'),
          borderRadius: BorderRadius.circular(Rad.pill),
          onTap: toggle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TranslateGlyph(color: open ? p.accent : p.ink),
                  const SizedBox(width: 3),
                  // At most 3 characters and the bar is clamped at 1.2x, so it keeps the user's size (no FittedBox).
                  Text(
                    cur.$4,
                    style: th.textTheme.titleSmall?.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: open ? p.accent : p.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sun / moon icon with no border or fill; flips the theme opposite to what is on screen.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final dark = b == Brightness.dark;
    final lang = AppLanguage.of(context);
    return IconButton(
      key: const Key('btn_theme'),
      tooltip: shellT(lang, dark ? 'theme_light' : 'theme_dark'),
      style: IconButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: palOf(context).ink),
      onPressed: () => ThemeController.toggle(b),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        transitionBuilder: (child, a) => RotationTransition(
          turns: Tween(begin: 0.6, end: 1.0).animate(a),
          child: FadeTransition(opacity: a, child: child),
        ),
        child: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, key: ValueKey(dark), size: 26),
      ),
    );
  }
}

/// Red "Report" pill with a call icon: the fastest way to the 1930 flow (the dial happens only in ReportScreen).
class ReportButton extends StatelessWidget {
  const ReportButton({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final st = Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lang = AppLanguage.of(context);
    // Capped so the bar never overflows on a narrow phone at large text; the label wraps instead of shrinking.
    final maxW = MediaQuery.sizeOf(context).width * 0.34;
    return Padding(
      padding: const EdgeInsets.only(left: Sp.xs),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Semantics(
          button: true,
          label: shellT(lang, 'report_sem'),
          excludeSemantics: true,
          child: FilledButton.icon(
            key: const Key('btn_report_1930'),
            style: FilledButton.styleFrom(
              backgroundColor: st.scam,
              foregroundColor: dark ? Colors.black : Colors.white,
              minimumSize: const Size(48, 40),
              padding: const EdgeInsets.fromLTRB(Sp.m, 0, Sp.m + 2, 0),
              textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            onPressed: onTap ?? () => openReport(context),
            icon: const Icon(Icons.call_rounded, size: 18),
            label: Text(shellT(lang, 'report_btn'), textAlign: TextAlign.center, softWrap: true),
          ),
        ),
      ),
    );
  }
}
