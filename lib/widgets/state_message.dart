import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Empty, loading and error states in one shape: icon (or a small spinner), one line,
/// an optional second line, and an optional next action.
class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.loading = false,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });
  final String title;
  final IconData? icon;
  final String? subtitle;

  /// Shows a small progress indicator instead of [icon].
  final bool loading;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(Sp.xl),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (loading)
          const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3))
        else if (icon != null)
          Icon(icon, size: 64, color: cs.onSurfaceVariant),
        const SizedBox(height: Sp.m),
        Semantics(
          liveRegion: true,
          child: Text(title, textAlign: TextAlign.center, style: t.textTheme.titleLarge),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: Sp.xs),
          Text(subtitle!, textAlign: TextAlign.center, style: t.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
        ],
        if (onAction != null && actionLabel != null) ...[
          const SizedBox(height: Sp.l),
          OutlinedButton.icon(
            onPressed: onAction,
            icon: Icon(actionIcon ?? Icons.refresh),
            label: Text(actionLabel!, textAlign: TextAlign.center),
          ),
        ],
      ]),
    );
  }
}
