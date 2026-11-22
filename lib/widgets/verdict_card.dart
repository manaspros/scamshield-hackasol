import 'package:flutter/material.dart';

import '../models/verdict.dart';

/// Mirrors the on-call overlay bubble: "This statement is SCAM · 87%".
class VerdictCard extends StatelessWidget {
  const VerdictCard({super.key, required this.verdict, this.compact = false});
  final Verdict verdict;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final v = verdict;
    final fg = Colors.white;
    return Card(
      color: v.label.color,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(v.label.icon, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(v.headline + (v.preliminary ? ' …' : ''),
                  style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(v.label.hindi, style: TextStyle(color: fg.withValues(alpha: 0.95))),
          if (!compact) ...[
            const SizedBox(height: 8),
            Text('“${v.text}”',
                style: TextStyle(color: fg, fontStyle: FontStyle.italic), maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 6),
          Text('Why: ${v.reason}', style: TextStyle(color: fg)),
          if (v.triggers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final t in v.triggers.take(5))
                  Chip(
                    label: Text(t, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ]),
            ),
          const SizedBox(height: 6),
          Text('${v.engine} · ${v.latencyMs} ms · ${v.source}',
              style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 12)),
        ]),
      ),
    );
  }
}
