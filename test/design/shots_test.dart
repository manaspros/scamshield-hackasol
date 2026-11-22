// Local visual review only: renders the design system to PNG outside the repo.
// Skips itself when fonts or the output dir are unavailable. Never commit PNGs.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/models/verdict.dart';
import 'package:scamshield/theme/app_theme.dart';
import 'package:scamshield/widgets/action_tile.dart';
import 'package:scamshield/widgets/charts/bar_chart.dart';
import 'package:scamshield/widgets/section_header.dart';
import 'package:scamshield/widgets/stat_tile.dart';
import 'package:scamshield/widgets/status_chip.dart';
import 'package:scamshield/widgets/verdict_card.dart';

const _out = '/private/tmp/claude-501/-Users-manas-choudhary-orca-projects-hackasol/e64f2eb4-9bd8-469c-aefb-75bfaefd4d3f/scratchpad/shots';

Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) throw StateError('missing $path');
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await loader.load();
}

void main() {
  testWidgets('shots: render design system light + dark', (tester) async {
    final flutterBin = Platform.environment['FLUTTER_ROOT'];
    final sdk = flutterBin ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
    final fonts = '$sdk/bin/cache/artifacts/material_fonts';
    try {
      Directory(_out).createSync(recursive: true);
      await tester.runAsync(() async {
        await _font('Roboto', '$fonts/Roboto-Regular.ttf');
        await _font('Roboto', '$fonts/Roboto-Medium.ttf');
        await _font('Roboto', '$fonts/Roboto-Bold.ttf');
        await _font('MaterialIcons', '$fonts/MaterialIcons-Regular.otf');
        await _font('Deva', '/System/Library/Fonts/Supplemental/Devanagari Sangam MN.ttc');
      });
    } catch (_) {
      return; // fonts or dir unavailable: skip
    }

    const verdicts = [
      Verdict(
          text: 'आपके खाते से पैसे कट जाएंगे, अभी ओटीपी बताइए',
          label: RiskLabel.scam,
          confidence: 0.87,
          reason: 'कॉल करने वाला ओटीपी माँग रहा है',
          triggers: ['ओटीपी बताइए', 'खाता बंद'],
          engine: 'gemma+rules',
          latencyMs: 1420,
          source: 'caption'),
      Verdict(
          text: 'आपका पार्सल रुका है, लिंक खोलें',
          label: RiskLabel.suspicious,
          confidence: 0.61,
          reason: 'अनजान लिंक खोलने को कहा गया',
          triggers: ['लिंक खोलें'],
          engine: 'rules',
          latencyMs: 12,
          source: 'sms'),
      Verdict(
          text: 'कल शाम को मिलते हैं',
          label: RiskLabel.safe,
          confidence: 0.93,
          reason: 'सामान्य बातचीत',
          triggers: [],
          engine: 'rules',
          latencyMs: 9,
          source: 'manual'),
    ];

    for (final dark in [false, true]) {
      final base = dark ? AppTheme.dark() : AppTheme.light();
      TextStyle? f(TextStyle? s) => s?.copyWith(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']);
      final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']),
          appBarTheme: base.appBarTheme.copyWith(titleTextStyle: f(base.appBarTheme.titleTextStyle)),
          chipTheme: base.chipTheme.copyWith(labelStyle: f(base.chipTheme.labelStyle)));
      tester.view.physicalSize = const Size(720, 5200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            appBar: AppBar(title: const Text('स्कैमशील्ड · जाँच')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final v in verdicts) VerdictCard(verdict: v),
                const SectionHeader(title: 'आज की जाँच', icon: Icons.shield, subtitle: 'आपके फ़ोन पर हुई कॉल और संदेश'),
                ActionTile(icon: Icons.phone_in_talk, label: 'कॉल की जाँच करें', caption: 'कॉल के दौरान चेतावनी पाएँ', onTap: () {}),
                const SizedBox(height: 8),
                const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: StatTile(value: '87%', caption: 'सही जवाब', icon: Icons.school)),
                  SizedBox(width: 8),
                  Expanded(child: StatTile(value: '124', caption: 'रोके गए संदेश', icon: Icons.block)),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [for (final l in RiskLabel.values) StatusChip(label: l)]),
                const SectionHeader(title: 'ज़िलेवार शिकायतें'),
                const BarChart(data: [
                  BarDatum('रायपुर', 412),
                  BarDatum('बिलासपुर', 268),
                  BarDatum('दुर्ग', 190),
                  BarDatum('बस्तर', 73),
                ]),
                const SizedBox(height: 24),
                FilledButton(onPressed: () {}, child: const Text('1930 पर रिपोर्ट करें')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () {}, child: const Text('सबूत की सूची देखें')),
                TextButton(onPressed: () {}, child: const Text('बाद में')),
              ]),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/design_${dark ? 'dark' : 'light'}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}
