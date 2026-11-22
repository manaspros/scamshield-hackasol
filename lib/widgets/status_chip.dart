import 'package:flutter/material.dart';

import '../models/verdict.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Verdict meaning as icon + word on a tinted pill. Never colour alone.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, this.text});
  final RiskLabel label;

  /// Overrides the default Hindi word.
  final String? text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final st = t.extension<StatusColors>() ?? StatusColors.light;
    final solid = st.solid(label);
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: Sp.xs),
      decoration: ShapeDecoration(
        color: st.tintOver(label, t.colorScheme.surface),
        shape: const StadiumBorder(),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(label.icon, size: 24, color: solid),
        const SizedBox(width: Sp.s),
        Flexible(child: Text(text ?? label.hindi, style: t.textTheme.labelMedium?.copyWith(color: solid))),
      ]),
    );
  }
}
