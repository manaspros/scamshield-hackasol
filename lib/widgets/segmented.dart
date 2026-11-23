import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'a11y.dart';

/// iOS-style segmented control: one pill per option, the chosen one raised. Stacks at large text.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.onChanged, required this.items});
  final T value;
  final ValueChanged<T> onChanged;
  final List<(T, String, IconData?, Key)> items;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    final th = Theme.of(context);
    // At large text the segments stack, so each label keeps its full size and words.
    final stacked = MediaQuery.textScalerOf(context).scale(16) > 24;
    final segs = [
        for (final (v, label, icon, key) in items)
            Semantics(
              selected: v == value,
              button: true,
              child: GestureDetector(
                key: key,
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: motion(context, const Duration(milliseconds: 200)),
                  curve: Curves.easeOutCubic,
                  constraints: const BoxConstraints(minHeight: kTouch),
                  decoration: BoxDecoration(
                    color: v == value ? (p.isDark ? const Color(0xFF48484A) : Colors.white) : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: v == value ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 3, offset: Offset(0, 1))] : null,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: Sp.xs, vertical: Sp.s),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: v == value ? p.ink : p.muted),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: th.textTheme.labelMedium?.copyWith(fontSize: 16, color: v == value ? p.ink : p.muted, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFEEEEF1), borderRadius: BorderRadius.circular(14)),
      child: stacked
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: segs)
          : Row(children: [for (final s in segs) Expanded(child: s)]),
    );
  }
}
