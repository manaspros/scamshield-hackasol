import 'package:flutter/material.dart';

import '../models/verdict.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Mirrors the on-call overlay bubble: "This statement is SCAM · 87%".
/// Tinted surface + solid icon/label, so meaning never rests on colour alone.
class VerdictCard extends StatelessWidget {
  const VerdictCard({super.key, required this.verdict, this.compact = false});
  final Verdict verdict;
  final bool compact;

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
        Text('Why: ${v.reason}', style: tt.bodyLarge),
        if (v.triggers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Sp.s),
            child: Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
              for (final trig in v.triggers.take(5))
                Chip(
                  label: Text(trig),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ]),
          ),
        const SizedBox(height: Sp.s),
        Text('${v.engine} · ${v.latencyMs} ms · ${v.source}', style: muted),
      ]),
    );
  }
}
