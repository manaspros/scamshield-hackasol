import 'package:flutter/material.dart';

/// The ScamShield mark: a shield whose sides run straight into a V point.
enum ShieldStyle {
  /// Blue shield with "SCAM / SHIELD" and a V tick: the full logo (headers, onboarding, splash).
  full,

  /// Blue shield with a bold tick only: small sizes (chat avatar, app bar), where text cannot be read.
  mark,

  /// White shield on a coloured tile with blue text: the app icon look.
  onBrand,
}

/// Brand blue; the same in light and dark so the mark is recognisable everywhere.
const kBrandBlue = Color(0xFF0066CC);

class ShieldLogo extends StatelessWidget {
  const ShieldLogo({super.key, this.size = 40, this.style = ShieldStyle.mark, this.semanticLabel});

  /// Height in logical pixels; width follows the 120:132 drawing.
  final double size;
  final ShieldStyle style;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final w = size * 120 / 132;
    final paint = CustomPaint(size: Size(w, size), painter: _ShieldPainter(style));
    if (semanticLabel == null) return ExcludeSemantics(child: paint);
    return Semantics(image: true, label: semanticLabel, child: paint);
  }
}

/// "ScamShield" wordmark next to the mark, for app bars and onboarding.
class ShieldLockup extends StatelessWidget {
  const ShieldLockup({super.key, this.size = 28, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color;
    return Semantics(
      label: 'ScamShield',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ShieldLogo(size: size),
        SizedBox(width: size * 0.32),
        Text('ScamShield',
            style: TextStyle(fontSize: size * 0.72, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: c, height: 1)),
      ]),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  const _ShieldPainter(this.style);
  final ShieldStyle style;

  static Path _outline() => Path()
    ..moveTo(60, 6)
    ..cubicTo(78, 14, 94, 17, 110, 18)
    ..lineTo(110, 64)
    ..lineTo(60, 126)
    ..lineTo(10, 64)
    ..lineTo(10, 18)
    ..cubicTo(26, 17, 42, 14, 60, 6)
    ..close();

  static Path _inner() => Path()
    ..moveTo(60, 14.5)
    ..cubicTo(75, 21, 89, 24, 101.5, 25)
    ..lineTo(101.5, 61)
    ..lineTo(60, 112.5)
    ..lineTo(18.5, 61)
    ..lineTo(18.5, 25)
    ..cubicTo(31, 24, 45, 21, 60, 14.5)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 120, size.height / 132);
    final onBrand = style == ShieldStyle.onBrand;
    final body = onBrand ? Colors.white : kBrandBlue;
    final ink = onBrand ? kBrandBlue : Colors.white;
    canvas.drawPath(_outline(), Paint()..color = body..isAntiAlias = true);

    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (style == ShieldStyle.mark) {
      canvas.drawPath(Path()..moveTo(40, 62)..lineTo(56, 80)..lineTo(82, 46), stroke..strokeWidth = 12);
    } else {
      if (!onBrand) {
        canvas.drawPath(_inner(), Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }
      _text(canvas, 'SCAM', 21, FontWeight.w900, 1, 54, ink);
      _text(canvas, 'SHIELD', 12.5, FontWeight.w700, 1.2, 71, ink);
      canvas.drawPath(Path()..moveTo(48, 82)..lineTo(60, 97)..lineTo(72, 82), stroke..strokeWidth = onBrand ? 7 : 6);
    }
    canvas.restore();
  }

  // [baseline] is the SVG text baseline; TextPainter draws from the top, so shift by the ascent.
  void _text(Canvas c, String s, double fs, FontWeight w, double ls, double baseline, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: fs, fontWeight: w, letterSpacing: ls, color: color, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.paint(c, Offset(60 - (tp.width - ls) / 2, baseline - ascent));
  }

  @override
  bool shouldRepaint(_ShieldPainter old) => old.style != style;
}
