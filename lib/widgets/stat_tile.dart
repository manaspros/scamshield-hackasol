import 'package:flutter/material.dart';

import '../theme/text_styles.dart';
import '../theme/tokens.dart';

/// Big number with a caption, e.g. "87%" / "सही जवाब".
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.caption, this.icon});
  final String value;
  final String caption;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Semantics(
      label: '$value, $caption',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Sp.xl),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(Rad.lg),
          border: Border.all(color: cs.outline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 32, color: cs.onSurface),
            const SizedBox(height: Sp.s),
          ],
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AppText.display.copyWith(fontSize: 48, color: cs.onSurface)),
          ),
          const SizedBox(height: Sp.xs),
          Text(caption, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
