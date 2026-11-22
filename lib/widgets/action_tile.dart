import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'press_scale.dart';

/// Big icon-first tap target: 40dp icon, one-line word, optional caption.
class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.icon, required this.label, this.caption, this.onTap});
  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final enabled = onTap != null;
    return PressScale(
      enabled: enabled,
      child: Semantics(
        button: true,
        enabled: enabled,
        child: Material(
          color: cs.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Rad.lg), side: BorderSide(color: cs.outline)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.all(Sp.l),
                child: Row(children: [
                  Icon(icon, size: 40, color: enabled ? cs.primary : cs.onSurfaceVariant),
                  const SizedBox(width: Sp.l),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: t.textTheme.titleMedium),
                      if (caption != null)
                        Text(caption!, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  Icon(Icons.chevron_right, size: 32, color: cs.onSurfaceVariant),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
