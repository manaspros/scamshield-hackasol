import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../l10n/strings_shell.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'a11y.dart';

/// Floating "island" surface: rounded, translucent, blurred, with a soft shadow.
/// The one container for dropdowns, alerts and floating bars.
class IslandSurface extends StatelessWidget {
  const IslandSurface({
    super.key,
    required this.child,
    this.radius = RadX.island,
    this.padding = const EdgeInsets.all(Sp.s),
    this.color,
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final br = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: br, boxShadow: Elev.island(b)),
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: ColoredBox(
            color: color ?? palOf(context).island,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// One row of an [IslandMenu].
class IslandMenuItem<T> {
  const IslandMenuItem({
    required this.value,
    required this.label,
    this.caption,
    this.leading,
    this.trailing,
    this.selected = false,
    this.enabled = true,
    this.key,
  });
  final T value;
  final String label;
  final String? caption;
  final Widget? leading, trailing;
  final bool selected, enabled;
  final Key? key;
}

/// A dropdown that opens as a floating island anchored under its trigger.
/// [builder] draws the trigger; call `toggle` from it.
class IslandMenu<T> extends StatefulWidget {
  const IslandMenu({
    super.key,
    required this.items,
    required this.onSelected,
    required this.builder,
    this.header,
    this.width = 264,
    this.alignEnd = true,
    this.matchAnchorWidth = false,
  });
  final List<IslandMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final Widget Function(BuildContext context, bool open, VoidCallback toggle) builder;
  final String? header;
  final double width;

  /// Right-align the island with the trigger (top bar); false = left-align.
  final bool alignEnd;

  /// Make the island as wide as the trigger (form dropdowns).
  final bool matchAnchorWidth;

  @override
  State<IslandMenu<T>> createState() => _IslandMenuState<T>();
}

class _IslandMenuState<T> extends State<IslandMenu<T>> {
  final _ctrl = OverlayPortalController();
  final _anchorKey = GlobalKey();

  void _toggle() => setState(() => _ctrl.isShowing ? _ctrl.hide() : _ctrl.show());

  void _close() {
    if (_ctrl.isShowing) setState(_ctrl.hide);
  }

  void _pick(T v) {
    _close();
    widget.onSelected(v);
  }

  double _width() {
    if (!widget.matchAnchorWidth) return widget.width;
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.width ?? widget.width;
  }

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    final th = Theme.of(context);
    final lang = AppLanguage.of(context);
    return OverlayPortal(
      controller: _ctrl,
      // Its own route for TalkBack: focus stays inside the open menu, and the backdrop is a labelled close button.
      overlayChildBuilder: (ctx) => Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: widget.header ?? shellT(lang, 'menu'),
        child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              key: const Key('island_menu_dismiss'),
              label: shellT(lang, 'close'),
              button: true,
              onTap: _close,
              onDismiss: _close,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: ColoredBox(color: Colors.black.withValues(alpha: p.isDark ? 0.45 : 0.18)),
              ),
            ),
          ),
          Builder(
            builder: (ctx) {
              // Anchor under the trigger, but always fully on screen with a 12 px margin.
              final overlayBox = Overlay.of(ctx).context.findRenderObject() as RenderBox?;
              final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
              if (overlayBox == null || box == null || !box.attached) return const SizedBox.shrink();
              final screen = overlayBox.size;
              final at = box.localToGlobal(Offset.zero, ancestor: overlayBox);
              final w = math.min(_width(), screen.width - 2 * Sp.m);
              final left = (widget.alignEnd ? at.dx + box.size.width - w : at.dx).clamp(
                Sp.m,
                math.max(Sp.m, screen.width - w - Sp.m),
              );
              final top = at.dy + box.size.height + Sp.s;
              return Positioned(
                left: left.toDouble(),
                top: top,
                width: w,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: motion(ctx, const Duration(milliseconds: 180)),
                  curve: Curves.easeOutCubic,
                  builder: (_, t, child) => Opacity(
                    opacity: t,
                    child: Transform.scale(
                      scale: 0.92 + 0.08 * t,
                      alignment: widget.alignEnd ? Alignment.topRight : Alignment.topLeft,
                      child: child,
                    ),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: math.max(120, screen.height - top - Sp.l)),
                      child: IslandSurface(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.header != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(Sp.m, Sp.s, Sp.m, Sp.xs),
                                  child: Text(
                                    widget.header!,
                                    style: th.textTheme.labelMedium?.copyWith(color: p.muted, fontSize: 14),
                                  ),
                                ),
                              for (final it in widget.items) _row(context, it),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      ),
      child: KeyedSubtree(key: _anchorKey, child: widget.builder(context, _ctrl.isShowing, _toggle)),
    );
  }

  Widget _row(BuildContext context, IslandMenuItem<T> it) {
    final p = palOf(context);
    final th = Theme.of(context);
    return Semantics(
      selected: it.selected,
      button: true,
      enabled: it.enabled,
      child: Opacity(
        opacity: it.enabled ? 1 : 0.55,
        child: Material(
          color: it.selected ? p.accentTint : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: it.key,
            borderRadius: BorderRadius.circular(18),
            onTap: it.enabled ? () => _pick(it.value) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kTouch),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: Sp.s),
                child: Row(
                  children: [
                    if (it.leading != null) ...[it.leading!, const SizedBox(width: Sp.m)],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(it.label, style: th.textTheme.titleMedium?.copyWith(fontSize: 17, color: p.ink)),
                          if (it.caption != null)
                            Text(it.caption!, style: th.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: 14)),
                        ],
                      ),
                    ),
                    if (it.trailing != null) it.trailing!,
                    if (it.selected && it.trailing == null) Icon(Icons.check_rounded, color: p.accent, size: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum IslandTone { info, success, warning, danger }

OverlayEntry? _current;

/// A short alert that drops in from the top as a dark island, then leaves by itself (or on an upward swipe).
/// Replaces SnackBars app-wide.
void showIsland(
  BuildContext context,
  String message, {
  String? title,
  IconData? icon,
  IslandTone tone = IslandTone.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _current?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _IslandToast(
      message: message,
      title: title,
      icon: icon,
      tone: tone,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
      onGone: () {
        if (_current == entry) _current = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

class _IslandToast extends StatefulWidget {
  const _IslandToast({
    required this.message,
    required this.tone,
    required this.duration,
    required this.onGone,
    this.title,
    this.icon,
    this.actionLabel,
    this.onAction,
  });
  final String message;
  final String? title, actionLabel;
  final IconData? icon;
  final IslandTone tone;
  final Duration duration;
  final VoidCallback onGone;
  final VoidCallback? onAction;

  @override
  State<_IslandToast> createState() => _IslandToastState();
}

class _IslandToastState extends State<_IslandToast> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  Timer? _timer;
  bool _leaving = false;

  // MediaQuery is not readable in initState: start once dependencies are known.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _anim.duration = motion(context, const Duration(milliseconds: 260));
    if (_timer != null) return;
    _anim.forward();
    // With TalkBack on, stay long enough to be found and read (never cut at 3 s).
    _timer = Timer(readingTime(context, widget.duration), _leave);
  }

  Future<void> _leave() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    await _anim.reverse();
    widget.onGone();
  }

  @override
  void dispose() {
    _timer?.cancel(); // never leave a pending timer behind (tests, hot restart)
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const st = StatusColors.dark; // bright status colours read on the dark island in both themes
    final c = switch (widget.tone) {
      IslandTone.success => st.safe,
      IslandTone.warning => st.suspicious,
      IslandTone.danger => st.scam,
      IslandTone.info => Pal.dark.accent,
    };
    final ic =
        widget.icon ??
        switch (widget.tone) {
          IslandTone.success => Icons.check_rounded,
          IslandTone.warning => Icons.priority_high_rounded,
          IslandTone.danger => Icons.warning_amber_rounded,
          IslandTone.info => Icons.info_outline_rounded,
        };
    final th = Theme.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, 0),
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, -1.2),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn)),
            child: FadeTransition(
              opacity: _anim,
              child: GestureDetector(
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) < 0) _leave();
                },
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Semantics(
                        liveRegion: true,
                        child: IslandSurface(
                          radius: 26,
                          padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: Sp.m),
                          color: dark ? const Color(0xF23A3A3C) : const Color(0xEB1C1C1E),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                                child: Icon(ic, color: const Color(0xFF1C1C1E), size: 22),
                              ),
                              const SizedBox(width: Sp.m),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.title != null)
                                      Text(
                                        widget.title!,
                                        style: th.textTheme.titleSmall?.copyWith(
                                          color: const Color(0xFFF5F5F7),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    Text(
                                      widget.message, // never clipped: the whole message must be readable
                                      style: th.textTheme.bodySmall?.copyWith(
                                        color: widget.title == null ? const Color(0xFFF5F5F7) : const Color(0xFFC7C7CC),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (widget.actionLabel != null)
                                TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: Pal.dark.accent,
                                    minimumSize: const Size(48, 44),
                                    textStyle: th.textTheme.titleSmall,
                                  ),
                                  onPressed: () {
                                    widget.onAction?.call();
                                    _leave();
                                  },
                                  child: Text(widget.actionLabel!),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A floating bottom sheet: an island card with side margins and a large radius.
Future<T?> showIslandSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withValues(alpha: palOf(context).isDark ? 0.6 : 0.38),
    builder: (ctx) {
      final p = palOf(ctx);
      return Padding(
        padding: EdgeInsets.fromLTRB(Sp.m, 0, Sp.m, Sp.l + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(RadX.sheet),
            border: p.isDark ? Border.all(color: p.hairline) : null,
            boxShadow: Elev.island(Theme.of(ctx).brightness),
          ),
          padding: const EdgeInsets.fromLTRB(Sp.l + 4, Sp.s, Sp.l + 4, Sp.l + 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: Sp.m),
                  decoration: BoxDecoration(color: p.hairline, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              Flexible(child: builder(ctx)),
            ],
          ),
        ),
      );
    },
  );
}
