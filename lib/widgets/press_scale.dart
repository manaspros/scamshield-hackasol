import 'package:flutter/material.dart';

import 'a11y.dart';

/// Scales its child to 0.95 while a pointer is down. Uses a raw [Listener] so it
/// never competes with the child's own tap handling.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (widget.enabled && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          // Reduced motion: no press bounce at all.
          scale: _down && motion(context, const Duration(milliseconds: 100)) > Duration.zero ? 0.95 : 1,
          duration: motion(context, const Duration(milliseconds: 100)),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}
