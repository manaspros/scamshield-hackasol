import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../l10n/strings_shell.dart';
import '../models/verdict.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// One-word headline per risk label (the long phrase is `label.hindi`, shown under it).
/// Verdict for a first-time reader. With `showDebug: false` (the live feed) it reads: Hindi
/// headline, what to do now, the 1930 row, then reasons behind a collapsed "क्यों?". The default
/// `showDebug: true` keeps the original developer layout: "This statement is SCAM · 87%",
/// reasons inline and the engine/ms footer (the paste screen and its tests still rely on it).
/// Tinted surface + solid icon/label, so meaning never rests on colour alone.
class VerdictCard extends StatelessWidget {
  const VerdictCard({
    super.key,
    required this.verdict,
    this.compact = false,
    this.adviceTitle,
    this.advice = const [],
    this.footer,
    this.whyLabel,
    this.showDebug = true,
    this.initiallyExpanded = false,
  });
  final Verdict verdict;
  final bool compact;

  /// Optional "what to do now" block: a calm heading and 1-2 short imperative lines.
  final String? adviceTitle;
  final List<String> advice;

  /// Optional slot under the advice, e.g. a helpline row or a Report button.
  final Widget? footer;

  /// Label before the reason; pass another language here if the caller has one.
  /// Overrides the localized 'Why:' prefix.
  final String? whyLabel;

  /// true: English headline with %, inline reasons, engine/ms footer. false: the calm layout.
  final bool showDebug;

  /// Calm layout only: start with the "क्यों?" disclosure open.
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final v = verdict;
    final lang = AppLanguage.of(context);
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final tt = t.textTheme;
    final st = t.extension<StatusColors>() ?? StatusColors.light;
    final solid = st.solid(v.label);
    final muted = tt.bodySmall?.copyWith(color: cs.onSurfaceVariant);

    final headline = showDebug ? v.headline : v.label.headlineIn(lang);
    final quote = compact
        ? null
        : Text('“${v.text}”',
            style: tt.bodyLarge?.copyWith(fontStyle: FontStyle.italic), maxLines: 3, overflow: TextOverflow.ellipsis);
    final reason = Text(showDebug ? '${whyLabel ?? shellT(lang, 'why_colon')} ${v.reason}' : v.reason, style: tt.bodyLarge);
    final chips = v.triggers.isEmpty
        ? null
        : Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
            for (final trig in v.triggers.take(5))
              Chip(
                // Long masked triggers wrap inside the chip instead of fading out.
                label: Text(trig, softWrap: true, maxLines: 3, overflow: TextOverflow.ellipsis),
                // A rounded rectangle, not a pill: a pill looks bubbly once the text wraps to 2-3 lines.
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Rad.md), side: BorderSide(color: cs.outline)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ]);
    final adviceBlock = <Widget>[
      if (advice.isNotEmpty) ...[
        const SizedBox(height: Sp.m),
        if (adviceTitle != null) Text(adviceTitle!, style: tt.titleMedium),
        for (final line in advice)
          Padding(
            padding: const EdgeInsets.only(top: Sp.s),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.task_alt, size: 28, color: solid),
              const SizedBox(width: Sp.s),
              Expanded(child: Text(line, style: tt.titleMedium)),
            ]),
          ),
      ],
      if (footer != null) ...[const SizedBox(height: Sp.m), footer!],
    ];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(Sp.xl),
      decoration: BoxDecoration(
        color: st.tintOver(v.label, cs.surface),
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: solid.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(v.label.icon, size: 40, color: solid),
          const SizedBox(width: Sp.m),
          Expanded(
            child: Text(headline + (v.preliminary ? ' …' : ''), style: tt.titleLarge?.copyWith(color: solid)),
          ),
        ]),
        const SizedBox(height: Sp.xs),
        Text(v.label.textIn(lang), style: tt.titleMedium),
        if (showDebug) ...[
          if (quote != null) ...[const SizedBox(height: Sp.m), quote],
          const SizedBox(height: Sp.s),
          reason,
          if (chips != null) Padding(padding: const EdgeInsets.only(top: Sp.s), child: chips),
          ...adviceBlock,
          const SizedBox(height: Sp.s),
          Text('${v.engine} · ${v.latencyMs} ms · ${v.source}', style: muted),
        ] else ...[
          ...adviceBlock,
          const SizedBox(height: Sp.s),
          // No divider lines: the card border already frames it. minTileHeight keeps a 56dp target.
          Theme(
            data: t.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const Key('verdict_why'),
              initiallyExpanded: initiallyExpanded,
              minTileHeight: kTouch,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: Sp.s),
              expandedAlignment: Alignment.topLeft,
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(shellT(lang, 'why'), style: tt.titleMedium),
              children: [
                if (quote != null) ...[quote, const SizedBox(height: Sp.s)],
                reason,
                if (chips != null) Padding(padding: const EdgeInsets.only(top: Sp.s), child: chips),
              ],
            ),
          ),
        ],
      ]),
    );
  }
}
