import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/models/verdict.dart';
import 'package:scamshield/theme/app_theme.dart';
import 'package:scamshield/theme/tokens.dart';
import 'package:scamshield/widgets/action_tile.dart';
import 'package:scamshield/widgets/charts/bar_chart.dart';
import 'package:scamshield/widgets/section_header.dart';
import 'package:scamshield/widgets/stat_tile.dart';
import 'package:scamshield/widgets/status_chip.dart';
import 'package:scamshield/widgets/verdict_card.dart';

double _lin(int c) {
  final s = c / 255;
  return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double _lum(Color c) =>
    0.2126 * _lin((c.r * 255).round()) + 0.7152 * _lin((c.g * 255).round()) + 0.0722 * _lin((c.b * 255).round());

double contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  group('T_design niceScale', () {
    test('rounds axis max up to 1/2/5 x 10^n', () {
      expect(niceScale(87).max, 100);
      expect(niceScale(87).step, 50);
      expect(niceScale(100).max, 100);
      expect(niceScale(7).max, 8);
      expect(niceScale(7).step, 2);
      expect(niceScale(1240).max, 1500);
      expect(niceScale(0.42).max, closeTo(0.6, 1e-9));
    });
    test('degenerate input never yields zero or NaN', () {
      for (final v in [0.0, -3.0, double.nan, double.infinity]) {
        final s = niceScale(v);
        expect(s.max, 1);
        expect(s.step, 1);
      }
    });
    test('axis max always covers the data and is a whole number of steps', () {
      for (final v in [1.0, 3.0, 9.0, 11.0, 23.0, 99.0, 101.0, 4999.0]) {
        final s = niceScale(v);
        expect(s.max, greaterThanOrEqualTo(v));
        expect((s.max / s.step) % 1, closeTo(0, 1e-9));
      }
    });
  });

  group('T_design text-scale overflow (2.0x, 360dp, Devanagari)', () {
    const verdict = Verdict(
      text: 'आपके खाते से पैसे कट जाएंगे, अभी ओटीपी बताइए वरना बैंक खाता बंद हो जाएगा',
      label: RiskLabel.scam,
      confidence: 0.87,
      reason: 'यह कॉल धोखाधड़ी हो सकती है: कॉल करने वाला ओटीपी माँग रहा है',
      triggers: ['ओटीपी बताइए', 'खाता बंद हो जाएगा', 'तुरंत भुगतान करें', 'केवाईसी अपडेट'],
      engine: 'gemma+rules',
      latencyMs: 1420,
      source: 'caption',
      preliminary: true,
    );

    final themes = {'light': AppTheme.light(), 'dark': AppTheme.dark()};
    for (final e in themes.entries) {
      testWidgets('no overflow in ${e.key} theme', (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: e.value,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(2.0)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const VerdictCard(verdict: verdict),
                  const VerdictCard(verdict: verdict, compact: true),
                  const SectionHeader(
                      title: 'आज की जाँच', icon: Icons.shield, subtitle: 'आपके फ़ोन पर हुई कॉल और संदेश'),
                  ActionTile(
                      icon: Icons.phone_in_talk,
                      label: 'संदिग्ध कॉल की जाँच करें',
                      caption: 'कॉल के दौरान चेतावनी पाएँ',
                      onTap: () {}),
                  const SizedBox(height: 8),
                  const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: StatTile(value: '87%', caption: 'सही जवाब', icon: Icons.school)),
                    SizedBox(width: 8),
                    Expanded(child: StatTile(value: '१२४', caption: 'रोके गए संदेश', icon: Icons.block)),
                  ]),
                  for (final l in RiskLabel.values) ...[
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: StatusChip(label: l)),
                  ],
                  const SizedBox(height: 16),
                  const BarChart(data: [
                    BarDatum('रायपुर', 412),
                    BarDatum('बिलासपुर', 268),
                    BarDatum('दुर्ग-भिलाई नगर निगम क्षेत्र', 190),
                    BarDatum('बस्तर', 73),
                  ]),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () {}, child: const Text('रिपोर्ट करें: 1930 पर कॉल करें')),
                  OutlinedButton(onPressed: () {}, child: const Text('सबूत की सूची देखें')),
                  const TextField(decoration: InputDecoration(labelText: 'संदेश यहाँ चिपकाएँ')),
                ]),
              ),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('T_design WCAG AA contrast', () {
    for (final name in ['light', 'dark']) {
      final p = name == 'light' ? Pal.light : Pal.dark;
      final st = name == 'light' ? StatusColors.light : StatusColors.dark;

      test('$name text and accent pairs', () {
        for (final bg in [p.canvas, p.page, p.surface, p.surfaceAlt]) {
          expect(contrast(p.ink, bg), greaterThanOrEqualTo(4.5), reason: 'ink on $bg');
          expect(contrast(p.muted, bg), greaterThanOrEqualTo(4.5), reason: 'muted on $bg');
          expect(contrast(p.accent, bg), greaterThanOrEqualTo(4.5), reason: 'accent text on $bg');
        }
        expect(contrast(p.onAccent, p.accent), greaterThanOrEqualTo(4.5), reason: 'button label');
        // non-text: the hairline is decoration; the switch/progress/bars need 3:1
        expect(contrast(p.accent, p.surface), greaterThanOrEqualTo(3.0));
        expect(contrast(p.muted, p.surface), greaterThanOrEqualTo(3.0), reason: 'switch off track');
      });

      test('$name status colour on its own tint (text 4.5:1) and ink on tint', () {
        for (final l in RiskLabel.values) {
          for (final base in [p.page, p.surface]) {
            final tint = st.tintOver(l, base);
            expect(contrast(st.solid(l), tint), greaterThanOrEqualTo(4.5), reason: '${l.name} on tint over $base');
            expect(contrast(p.ink, tint), greaterThanOrEqualTo(4.5), reason: 'ink on ${l.name} tint');
            expect(contrast(st.solid(l), base), greaterThanOrEqualTo(4.5), reason: '${l.name} on $base');
          }
        }
      });
    }
  });
}
