import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Screen section title with an optional leading icon and one-line helper.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.icon, this.subtitle, this.muted = false});
  final String title;
  final IconData? icon;
  final String? subtitle;

  /// Informational headers use the neutral grey icon; action headers use the accent.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Sp.xl, bottom: Sp.m),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[
          Icon(icon, size: 32, color: muted ? t.colorScheme.onSurfaceVariant : t.colorScheme.primary),
          const SizedBox(width: Sp.m),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(title, style: t.textTheme.headlineMedium)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: Sp.xs),
                child: Text(subtitle!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ),
          ]),
        ),
      ]),
    );
  }
}
