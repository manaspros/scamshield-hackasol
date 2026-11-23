import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'a11y.dart';
import 'press_scale.dart';

/// Rounded floating card used across the redesign (Home, Profile, Learn).
class PCard extends StatelessWidget {
  const PCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Sp.l),
    this.color,
    this.onTap,
    this.radius = RadX.card,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    final br = BorderRadius.circular(radius);
    final body = Material(
      color: color ?? p.surface,
      borderRadius: br,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: color == null ? Elev.card(Theme.of(context).brightness) : null,
      ),
      child: body,
    );
    return onTap == null ? card : PressScale(child: card);
  }
}

/// Section heading with an optional trailing link.
class PSection extends StatelessWidget {
  const PSection({super.key, required this.title, this.action, this.onAction, this.actionKey});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    // The link sits flush with the right edge of the content below it. (It used to be Flexible next to an
    // Expanded title, which split the row 50/50 and left "See all" / "Add member" floating mid-row.)
    return Padding(
      padding: const EdgeInsets.only(top: Sp.l + 4, bottom: Sp.s + 2),
      child: LayoutBuilder(
        builder: (context, box) => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20)),
              ),
            ),
            if (action != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth * 0.5),
                child: TextButton(
                  key: actionKey,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.only(left: Sp.m),
                    alignment: Alignment.centerRight,
                    textStyle: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  onPressed: onAction,
                  child: Text(action!, textAlign: TextAlign.end, maxLines: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Square-ish tinted icon tile.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.tint, this.size = 44, this.iconSize = 24});
  final IconData icon;
  final Color color;
  final Color? tint;
  final double size, iconSize;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: tint ?? color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(size * 0.32),
    ),
    child: Icon(icon, color: color, size: iconSize),
  );
}

/// One row inside a grouped [PCard] list: label, value, chevron.
class PRow extends StatelessWidget {
  const PRow({
    super.key,
    required this.label,
    this.value,
    this.valueColor,
    this.leading,
    this.onTap,
    this.last = false,
    this.subtitle,
  });
  final String label;
  final String? value, subtitle;
  final Color? valueColor;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    final th = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: kTouch + 4),
        padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.s),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF0F0F2))),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: Sp.m + 2)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: th.textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.3)),
                  if (subtitle != null) Text(subtitle!, style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
                ],
              ),
            ),
            if (value != null)
              // Tight: the value box always spans to the chevron, so "Add" / values line up on the right edge
              // in every row (loose, it shrank to its text and floated mid-row).
              Flexible(
                fit: FlexFit.tight,
                child: Padding(
                  padding: const EdgeInsets.only(left: Sp.s),
                  child: Text(
                    value!,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: th.textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.3, color: valueColor ?? p.muted),
                  ),
                ),
              ),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: Sp.xs),
                child: Icon(Icons.chevron_right_rounded, color: p.muted, size: 22),
              ),
          ],
        ),
      ),
    );
  }
}

/// A grouped list card: rows separated by hairlines.
class PGroup extends StatelessWidget {
  const PGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => PCard(
    padding: EdgeInsets.zero,
    child: Column(children: children),
  );
}

/// Ring progress with a centred child (score, avatar, completeness).
class RingProgress extends StatelessWidget {
  const RingProgress({
    super.key,
    required this.value,
    required this.size,
    required this.stroke,
    required this.color,
    required this.track,
    this.child,
  });
  final double value, size, stroke;
  final Color color, track;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0, 1)),
            duration: motion(context, const Duration(milliseconds: 700)),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => CircularProgressIndicator(
              value: v,
              strokeWidth: stroke,
              strokeCap: StrokeCap.round,
              color: color,
              backgroundColor: track,
            ),
          ),
        ),
        ?child,
      ],
    ),
  );
}
