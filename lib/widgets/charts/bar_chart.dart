import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

class BarDatum {
  const BarDatum(this.label, this.value);
  final String label;
  final double value;
}

/// Axis maximum and tick step, both rounded to 1/2/5 x 10^n.
class NiceScale {
  const NiceScale(this.max, this.step);
  final double max, step;
  int get ticks => (max / step).round();
}

/// Round [dataMax] up to a readable axis: at most ~[targetTicks] intervals.
NiceScale niceScale(double dataMax, {int targetTicks = 4}) {
  if (!(dataMax > 0) || dataMax.isInfinite) return const NiceScale(1, 1);
  final raw = dataMax / targetTicks;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floorToDouble()).toDouble();
  final n = raw / mag;
  final step = (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * mag;
  return NiceScale((dataMax / step).ceil() * step, step);
}

/// Horizontal bar chart: one accent hue, label above each bar, value at the bar end.
/// Text lives in ink/muted tokens, never the series colour.
class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.data, this.format, this.semanticsLabel});
  final List<BarDatum> data;
  final String Function(double)? format;
  final String? semanticsLabel;

  static const double _bar = 20, _gap = Sp.l, _labelGap = Sp.xs, _tickGap = Sp.s;

  String _fmt(double v) => (format ?? (x) => x == x.roundToDouble() ? '${x.round()}' : x.toStringAsFixed(1))(v);

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final base = t.textTheme.bodySmall!;
    final scale = niceScale(data.map((d) => d.value).reduce(math.max));

    TextPainter tp(String s, TextStyle style, {double? maxWidth, int? maxLines}) => TextPainter(
          text: TextSpan(text: s, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: maxLines,
          ellipsis: maxLines == null ? null : '…',
        )..layout(maxWidth: maxWidth ?? double.infinity);

    return Semantics(
      label: semanticsLabel ?? data.map((d) => '${d.label}: ${_fmt(d.value)}').join(', '),
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.hasBoundedWidth ? c.maxWidth : 320.0;
        final valueStyle = base.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface);
        final tickStyle = base.copyWith(color: cs.onSurfaceVariant);
        final valuePs = [for (final d in data) tp(_fmt(d.value), valueStyle)];
        final valueW = valuePs.map((p) => p.width).reduce(math.max) + Sp.s;
        final plotW = math.max(1.0, w - valueW);
        final labelPs = [for (final d in data) tp(d.label, base.copyWith(color: cs.onSurface), maxWidth: w, maxLines: 2)];
        final tickPs = [for (var i = 0; i <= scale.ticks; i++) tp(_fmt(i * scale.step), tickStyle)];
        final tickH = tickPs.map((p) => p.height).reduce(math.max);

        final rowTops = <double>[];
        var y = 0.0;
        for (final l in labelPs) {
          rowTops.add(y);
          y += l.height + _labelGap + math.max(_bar, valuePs.first.height) + _gap;
        }
        final plotBottom = y - _gap;
        final height = plotBottom + _tickGap + tickH;

        return CustomPaint(
          size: Size(w, height),
          painter: _BarPainter(
            data: data,
            labels: labelPs,
            values: valuePs,
            ticks: tickPs,
            rowTops: rowTops,
            scale: scale,
            plotW: plotW,
            plotBottom: plotBottom,
            barColor: cs.primary,
            gridColor: cs.outline,
          ),
        );
      }),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.data,
    required this.labels,
    required this.values,
    required this.ticks,
    required this.rowTops,
    required this.scale,
    required this.plotW,
    required this.plotBottom,
    required this.barColor,
    required this.gridColor,
  });

  final List<BarDatum> data;
  final List<TextPainter> labels, values, ticks;
  final List<double> rowTops;
  final NiceScale scale;
  final double plotW, plotBottom;
  final Color barColor, gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < ticks.length; i++) {
      final x = plotW * i / scale.ticks;
      // gridline only through each bar row so it never strikes through a label
      for (var j = 0; j < data.length; j++) {
        final rowY = rowTops[j] + labels[j].height + BarChart._labelGap;
        canvas.drawLine(Offset(x, rowY), Offset(x, rowY + math.max(BarChart._bar, values[j].height)), grid);
      }
      final tp = ticks[i];
      // keep first/last tick label inside the canvas
      final dx = (x - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(dx, plotBottom + BarChart._tickGap));
    }
    final fill = Paint()..color = barColor;
    const r = Radius.circular(4);
    for (var i = 0; i < data.length; i++) {
      final top = rowTops[i];
      labels[i].paint(canvas, Offset(0, top));
      final rowY = top + labels[i].height + BarChart._labelGap;
      final rowH = math.max(BarChart._bar, values[i].height);
      final barY = rowY + (rowH - BarChart._bar) / 2;
      final len = plotW * (data[i].value / scale.max).clamp(0.0, 1.0);
      if (len > 0) {
        // rounded at the data end only, flat on the baseline
        canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTWH(0, barY, len, BarChart._bar), topRight: r, bottomRight: r),
            fill);
      }
      values[i].paint(canvas, Offset(len + Sp.s, rowY + (rowH - values[i].height) / 2));
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) => true; // painters are rebuilt on every layout; data is small
}
