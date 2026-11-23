// Local visual review only: renders the design system to PNG outside the repo.
// Skips itself when fonts or the output dir are unavailable. Never commit PNGs.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/lessons/lesson_model.dart';
import 'package:scamshield/lessons/quiz_engine.dart';
import 'package:scamshield/models/verdict.dart';
import 'package:scamshield/screens/family_screen.dart';
import 'package:scamshield/screens/lessons_screen.dart';
import 'package:scamshield/screens/live_feed_screen.dart';
import 'package:scamshield/screens/quiz_screen.dart';
import 'package:scamshield/screens/report_screen.dart';
import 'package:scamshield/screens/settings_screen.dart';
import 'package:scamshield/screens/setup_screen.dart';
import 'package:scamshield/theme/app_theme.dart';
import 'package:scamshield/theme/text_styles.dart';
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

Future<bool> _loadFonts(WidgetTester tester) async {
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
    return true;
  } catch (_) {
    return false; // fonts or dir unavailable: skip
  }
}

class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(Uint8List.fromList(File(key).readAsBytesSync()));
}

void main() {
  testWidgets('shots: render design system light + dark', (tester) async {
    if (!await _loadFonts(tester)) return;

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

  testWidgets('shots: restyled screens light + dark', (tester) async {
    if (!await _loadFonts(tester)) return;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/events'), (_) async => null);
    var setupFirstRun = false; // true while the first-run Setup shot renders: no language yet, service off
    messenger.setMockMethodCallHandler(
        const MethodChannel('scamshield/prefs'), (c) async => !setupFirstRun && c.method == 'getString' ? 'hi' : null);
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), (c) async => switch (c.method) {
          'serviceStatus' => {'enabled': !setupFirstRun, 'connected': !setupFirstRun},
          'modelStatus' => {'status': 'READY', 'message': '', 'path': '/data/model.task', 'sizeMb': 555},
          'downloadStatus' => {'status': 'IDLE'},
          'micPermission' => true,
          'perm.notificationsGranted' => false,
          'perm.notificationAccessGranted' => true,
          _ => null,
        });
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/family'), (c) async => switch (c.method) {
          'family.status' => {'paired': true},
          'family.code' => {'code': '123456', 'remainingSec': 20},
          _ => null,
        });
    final reportPack = {
      'targets': [
        {'phone': '1930', 'url': null},
        {'phone': null, 'url': 'https://cybercrime.gov.in'},
      ],
      'evidence': [
        {'time': '2026-11-23 10:15 IST', 'scamType': 'DIGITAL_ARREST', 'source': 'caption', 'triggers': ['CBI', 'arrest warrant']},
      ],
    };
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), (c) async => switch (c.method) {
          'golden.status' => {'started': true, 'startMs': 1, 'remainingMs': 2535000, 'pack': reportPack},
          _ => true,
        });
    addTearDown(() {
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/events'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/prefs'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/family'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), null);
    });
    final lessons = loadLessonsFromJson(File('assets/lessons/hi.json').readAsStringSync());
    final store = InMemoryQuizStore();
    await store.saveBest({'otp': 100});
    final engine = QuizEngine(lessons, store);
    await engine.load();

    for (final dark in [false, true]) {
      final base = dark ? AppTheme.dark() : AppTheme.light();
      TextStyle? f(TextStyle? s) => s?.copyWith(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']);
      final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']),
          appBarTheme: base.appBarTheme.copyWith(titleTextStyle: f(base.appBarTheme.titleTextStyle)),
          chipTheme: base.chipTheme.copyWith(labelStyle: f(base.chipTheme.labelStyle)),
          dialogTheme: base.dialogTheme.copyWith(
              titleTextStyle: f(base.dialogTheme.titleTextStyle), contentTextStyle: f(base.dialogTheme.contentTextStyle)),
          // Buttons set their own text style, so give them the Devanagari fallback too.
          filledButtonTheme: FilledButtonThemeData(
              style: base.filledButtonTheme.style!.copyWith(textStyle: WidgetStatePropertyAll(f(AppText.label)))),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: base.outlinedButtonTheme.style!.copyWith(textStyle: WidgetStatePropertyAll(f(AppText.label)))),
          textButtonTheme: TextButtonThemeData(
              style: base.textButtonTheme.style!.copyWith(textStyle: WidgetStatePropertyAll(f(AppText.label)))));
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final screens = <String, Widget>{
        'lessons': LessonsScreen(store: store, bundle: _DiskBundle()),
        'quiz': QuizScreen(lesson: lessons.first, engine: engine, lang: 'hi'),
        'setup': const SetupScreen(),
        'setup_firstrun': const SetupScreen(),
        'live_feed': const LiveFeedScreen(),
        'live_feed_idle': const LiveFeedScreen(),
        'family': const FamilyScreen(initialLang: 'hi'),
        'family_unpair': const FamilyScreen(initialLang: 'hi'),
        'setup_2x': const SetupScreen(),
        'live_feed_2x': const LiveFeedScreen(),
        'report': const ReportScreen(),
        'report_2x': const ReportScreen(),
      };
      for (final e in screens.entries) {
        final key = GlobalKey();
        final scale = e.key.endsWith('_2x') ? 2.0 : 1.0;
        setupFirstRun = e.key == 'setup_firstrun';
        // Unmount the previous screen first: its event-channel cancel would otherwise
        // clear the handler the next screen just registered.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          // Boundary above the Navigator so dialogs are captured too.
          builder: (c, child) => RepaintBoundary(
              key: key,
              child: MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!)),
          home: Scaffold(appBar: AppBar(title: Text(e.key)), body: e.value),
        ));
        await tester.pumpAndSettle();
        if (e.key == 'family_unpair') {
          await tester.tap(find.byKey(const Key('family_unpair')));
          await tester.pumpAndSettle();
        }
        if (e.key == 'quiz') {
          await tester.tap(find.byKey(const Key('cards_next')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('cards_next')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('cards_next')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('option_1')));
          await tester.pumpAndSettle();
        }
        if (e.key.startsWith('live_feed') && e.key != 'live_feed_idle') {
          messenger.handlePlatformMessage(
              'scamshield/events',
              const StandardMethodCodec().encodeSuccessEnvelope({
                'type': 'verdict',
                'text': 'ओटीपी बताइए',
                'label': 'SCAM',
                'confidence': 0.87,
                'reason': 'कॉल करने वाला ओटीपी माँग रहा है',
                'triggers': ['ओटीपी बताइए'],
                'engine': 'gemma+rules',
                'latencyMs': 1420,
                'source': 'caption',
                'callRisk': 0.8,
                'callLevel': 'SCAM',
              }),
              (_) {});
          await tester.pumpAndSettle();
        }
        await tester.runAsync(() async {
          final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final img = await b.toImage(pixelRatio: 1);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          final name = e.key.replaceAll('_2x', '');
          final suffix = scale == 2.0 ? '_2x' : '';
          File('$_out/ux_${name}_${dark ? 'dark' : 'light'}$suffix.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
      await tester.pumpWidget(const SizedBox()); // dispose the family countdown timer
    }
  });

  testWidgets('shots: settings light + dark + 2x, district saved, scrolled to the export card', (tester) async {
    if (!await _loadFonts(tester)) return;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'),
        (c) async => c.method == 'getSettings' ? <String, Object?>{'useLlm': true, 'overlayEnabled': true} : null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('scamshield/prefs'), (c) async => c.method == 'getString' ? 'Raipur' : null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/prefs'), null);
    });
    for (final (name, dark, scale) in [('light', false, 1.0), ('dark', true, 1.0), ('light_2x', false, 2.0)]) {
      final base = dark ? AppTheme.dark() : AppTheme.light();
      TextStyle? f(TextStyle? s) => s?.copyWith(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']);
      final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']),
          appBarTheme: base.appBarTheme.copyWith(titleTextStyle: f(base.appBarTheme.titleTextStyle)),
          // ListTile text styles bypass the textTheme, so give them the Devanagari fallback too.
          listTileTheme: base.listTileTheme.copyWith(
              titleTextStyle: f(base.listTileTheme.titleTextStyle), subtitleTextStyle: f(base.listTileTheme.subtitleTextStyle)),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: base.outlinedButtonTheme.style!.copyWith(textStyle: WidgetStatePropertyAll(f(AppText.label)))));
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        builder: (c, child) => RepaintBoundary(
            key: key,
            child: MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!)),
        home: Scaffold(appBar: AppBar(title: const Text('सेटिंग')), body: const SettingsScreen()),
      ));
      await tester.pumpAndSettle();
      // Bottom of the list: district, trust card, export.
      await tester.scrollUntilVisible(find.byKey(const Key('exportButton')), 300,
          scrollable: find.byType(Scrollable).first, maxScrolls: 100);
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/ux_settings_$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shots: verdict card with masked 40-char triggers, 2.0x', (tester) async {
    if (!await _loadFonts(tester)) return;
    final base = AppTheme.light();
    final theme = base.copyWith(
        textTheme: base.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']),
        chipTheme: base.chipTheme.copyWith(
            labelStyle: base.chipTheme.labelStyle?.copyWith(fontFamily: 'Roboto', fontFamilyFallback: ['Deva'])));
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(720, 3000); // tall enough to show the whole card
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (c, child) =>
          MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!),
      home: RepaintBoundary(
        key: key,
        child: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: VerdictCard(
              showDebug: false,
              initiallyExpanded: true,
              verdict: Verdict(
                text: 'आपके खाते से पैसे कट जाएंगे',
                label: RiskLabel.scam,
                confidence: 0.87,
                reason: 'कॉल करने वाला ओटीपी माँग रहा है',
                triggers: [
                  'UPI xxxxxx@okhdfcbank को ₹45,000 भेजें…',
                  '+91 98xxxxxx21 से कॉल आया, OTP माँगा…',
                  'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx…',
                ],
                engine: 'rules',
                latencyMs: 12,
                source: 'caption',
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/ux_verdict_masked_light_2x.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
