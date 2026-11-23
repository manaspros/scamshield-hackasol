import 'package:flutter/material.dart';

import '../models/verdict.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Mirrors the on-call overlay bubble: "This statement is SCAM · 87%".
/// Tinted surface + solid icon/label, so meaning never rests on colour alone.
class VerdictCard extends StatelessWidget {
  const VerdictCard({
    super.key,
    required this.verdict,
    this.compact = false,
    this.adviceTitle,
    this.advice = const [],
    this.footer,
    this.whyLabel = 'क्यों:',
  });
  final Verdict verdict;
  final bool compact;

  /// Optional "what to do now" block: a calm heading and 1-2 short imperative lines.
  final String? adviceTitle;
  final List<String> advice;

  /// Optional slot under the advice, e.g. a helpline row or a Report button.
  final Widget? footer;

  /// Label before the reason; pass another language here if the caller has one.
  final String whyLabel;

  @override
  Widget build(BuildContext context) {
    final v = verdict;
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final tt = t.textTheme;
    final st = t.extension<StatusColors>() ?? StatusColors.light;
    final solid = st.solid(v.label);
    final muted = tt.bodySmall?.copyWith(color: cs.onSurfaceVariant);
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
            child: Text(v.headline + (v.preliminary ? ' …' : ''),
                style: tt.titleLarge?.copyWith(color: solid)),
          ),
        ]),
        const SizedBox(height: Sp.xs),
        Text(v.label.hindi, style: tt.titleMedium),
        if (!compact) ...[
          const SizedBox(height: Sp.m),
          Text('“${v.text}”',
              style: tt.bodyLarge?.copyWith(fontStyle: FontStyle.italic), maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: Sp.s),
        Text('$whyLabel ${v.reason}', style: tt.bodyLarge),
        if (v.triggers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Sp.s),
            child: Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
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
            ]),
          ),
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
        const SizedBox(height: Sp.s),
        Text('${v.engine} · ${v.latencyMs} ms · ${v.source}', style: muted),
      ]),
    );
  }
}
