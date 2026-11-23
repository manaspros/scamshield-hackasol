// Local visual review only: renders the design system to PNG outside the repo.
// Skips itself when fonts or the output dir are unavailable. Never commit PNGs.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/lessons/lesson_model.dart';
import 'package:scamshield/main.dart' show HomeShell;
import 'package:scamshield/lessons/quiz_engine.dart';
import 'package:scamshield/models/verdict.dart';
import 'package:scamshield/screens/demo_lab_screen.dart';
import 'package:scamshield/screens/family_screen.dart';
import 'package:scamshield/screens/lessons_screen.dart';
import 'package:scamshield/screens/live_feed_screen.dart';
import 'package:scamshield/screens/quiz_screen.dart';
import 'package:scamshield/screens/recording_screen.dart';
import 'package:scamshield/screens/report_screen.dart';
import 'package:scamshield/screens/settings_screen.dart';
import 'package:scamshield/screens/setup_screen.dart';
import 'package:scamshield/screens/try_api_screen.dart';
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
        'learn_zero': LessonsScreen(store: InMemoryQuizStore(), bundle: _DiskBundle()),
        'quiz': QuizScreen(lesson: lessons.first, engine: engine, lang: 'hi'),
        'quiz_result': QuizScreen(lesson: lessons.first, engine: QuizEngine(lessons, InMemoryQuizStore()), lang: 'hi'),
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
        if (e.key == 'quiz_result') {
          for (var i = 0; i < 3; i++) {
            await tester.tap(find.byKey(const Key('cards_next')));
            await tester.pumpAndSettle();
          }
          for (final q in lessons.first.questions) {
            await tester.tap(find.byKey(Key('option_${q.correctIndex}')));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.byKey(const Key('quiz_next')));
            await tester.tap(find.byKey(const Key('quiz_next')));
            await tester.pumpAndSettle();
          }
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
          if (!dark && scale == 1.0 && const {'setup_firstrun', 'learn_zero', 'live_feed_idle', 'family'}.contains(name)) {
            File('$_out/polish_${name}_light.png').writeAsBytesSync(bytes.buffer.asUint8List());
          }
          if (!dark && scale == 1.0 && const {'lessons', 'quiz_result'}.contains(name)) {
            File('$_out/polish_${name == 'lessons' ? 'learn_progress' : name}_light.png').writeAsBytesSync(bytes.buffer.asUint8List());
          }
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
      if (name == 'light') {
        await tester.runAsync(() async {
          final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final img = await b.toImage(pixelRatio: 1);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/polish_settings_light.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
        final adv = find.byKey(const Key('settings_advanced'));
        for (final expanded in [false, true]) {
          await tester.scrollUntilVisible(adv, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 100);
          if (expanded) {
            await tester.tap(adv);
            await tester.pumpAndSettle();
            await tester.drag(find.byType(ListView), const Offset(0, -300));
          }
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final img = await b.toImage(pixelRatio: 1);
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            File('$_out/polish_settings_advanced_${expanded ? 'expanded' : 'collapsed'}_light.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        }
        // Collapse again so the export-card shot below is unchanged.
        await tester.tap(adv);
        await tester.pumpAndSettle();
      }
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

  testWidgets('shots: recording empty, progress, results light + results dark 2x', (tester) async {
    if (!await _loadFonts(tester)) return;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const ch = MethodChannel('scamshield/recording');
    messenger.setMockMethodCallHandler(ch, (c) async => switch (c.method) {
          'recording.status' => {'modelReady': true, 'busy': false},
          'recording.pending' || 'recording.pick' => false,
          _ => true,
        });
    addTearDown(() => messenger.setMockMethodCallHandler(ch, null));
    final stmts = [
      {'startMs': 0, 'text': 'नमस्ते, मैं आपके बैंक से बोल रहा हूँ', 'label': 'SAFE', 'triggers': <String>[]},
      {'startMs': 12000, 'text': 'आपका खाता बंद हो जाएगा, ओटीपी बताइए', 'label': 'SUSPICIOUS', 'triggers': ['ओटीपी']},
      {'startMs': 65000, 'text': 'अभी पैसे भेजें वरना गिरफ़्तारी होगी', 'label': 'SCAM', 'triggers': ['गिरफ़्तारी', 'पैसे भेजें']},
    ];
    for (final (name, dark, scale) in [
      ('empty_light', false, 1.0),
      ('progress_light', false, 1.0),
      ('results_light', false, 1.0),
      ('results_dark_2x', true, 2.0),
    ]) {
      final base = dark ? AppTheme.dark() : AppTheme.light();
      TextStyle? f(TextStyle? s) => s?.copyWith(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']);
      final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']),
          appBarTheme: base.appBarTheme.copyWith(titleTextStyle: f(base.appBarTheme.titleTextStyle)),
          chipTheme: base.chipTheme.copyWith(labelStyle: f(base.chipTheme.labelStyle)),
          filledButtonTheme: FilledButtonThemeData(
              style: base.filledButtonTheme.style!.copyWith(textStyle: WidgetStatePropertyAll(f(AppText.label)))),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: base.outlinedButtonTheme.style!.copyWith(textStyle: WidgetStatePropertyAll(f(AppText.label)))));
      // Results shots are tall so the whole story timeline is visible in one image.
      tester.view.physicalSize = Size(720, name.startsWith('results') ? 3200 : 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final events = StreamController<Object?>.broadcast();
      final key = GlobalKey();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        builder: (c, child) => RepaintBoundary(
            key: key,
            child: MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!)),
        home: Scaffold(
            appBar: AppBar(title: const Text('रिकॉर्डिंग')),
            body: RecordingScreen(initialLang: 'hi', api: RecordingApi(events: events.stream))),
      ));
      await tester.pumpAndSettle();
      if (name != 'empty_light') {
        events.add({'stage': 'shared', 'pct': 0});
        await tester.pump();
        await tester.pump();
        events.add({
          'stage': name == 'progress_light' ? 'classify' : 'stt',
          'pct': 40,
          'segment': {'startMs': 0, 'text': 'नमस्ते, मैं आपके बैंक से बोल रहा हूँ'},
          if (name == 'progress_light') 'statement': stmts[0],
        });
        await tester.pumpAndSettle();
      }
      if (name.startsWith('results')) {
        events.add({
          'stage': 'done',
          'pct': 100,
          'report': {'overall': 'SCAM', 'risk': 0.87, 'statements': stmts, 'topTriggers': ['गिरफ़्तारी', 'ओटीपी']},
        });
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/ux_recording_$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox()); // unmount before closing the stream
      await events.close();
    }
  });

  testWidgets('shots: try_api empty, scam result, UPI mismatch light + result dark 2x', (tester) async {
    if (!await _loadFonts(tester)) return;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), (c) async => switch (c.method) {
          'classify' => {
              'text': 'SBI se bol raha hoon, aapka KYC update pending hai',
              'label': 'SCAM',
              'confidence': 0.9,
              'reason': 'KYC के नाम पर लिंक खुलवाया जा रहा है',
              'triggers': ['KYC update', 'pending'],
              'engine': 'rules-only',
              'latencyMs': 5,
              'source': 'manual',
              'scamType': 'KYC',
            },
          'upi.check' => {
              'valid': true,
              'payeeName': 'Ravi Kumar',
              'payeeVpa': 'ra•••@oksbi',
              'amount': '500',
              'isCollect': false,
              'mismatch': true,
              'framing': 'You will PAY Rs 500 to Ravi Kumar',
              'framingHi': 'आप Ravi Kumar को ₹500 भेजेंगे',
            },
          _ => null,
        });
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), (_) async => true);
    addTearDown(() {
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), null);
    });
    addTearDown(() => tester.pumpWidget(const SizedBox())); // registered after the mocks
    for (final (name, dark, scale) in [
      ('empty_light', false, 1.0),
      ('result_light', false, 1.0),
      ('upi_mismatch_light', false, 1.0),
      ('result_dark_2x', true, 2.0),
    ]) {
      final base = dark ? AppTheme.dark() : AppTheme.light();
      TextStyle? f(TextStyle? s) => s?.copyWith(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']);
      final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']),
          appBarTheme: base.appBarTheme.copyWith(titleTextStyle: f(base.appBarTheme.titleTextStyle)),
          inputDecorationTheme: base.inputDecorationTheme.copyWith(
              hintStyle: f(base.inputDecorationTheme.hintStyle), labelStyle: f(base.inputDecorationTheme.labelStyle)),
          filledButtonTheme: FilledButtonThemeData(
              style: base.filledButtonTheme.style!.copyWith(textStyle: WidgetStatePropertyAll(f(AppText.label)))),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: base.outlinedButtonTheme.style!.copyWith(textStyle: WidgetStatePropertyAll(f(AppText.label)))),
          textButtonTheme: TextButtonThemeData(
              style: base.textButtonTheme.style!.copyWith(textStyle: WidgetStatePropertyAll(f(AppText.label)))));
      tester.view.physicalSize = Size(720, name == 'result_dark_2x' ? 2400 : 1600);
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
        home: Scaffold(appBar: AppBar(title: const Text('मैसेज जाँचें')), body: const TryApiScreen()),
      ));
      await tester.pumpAndSettle();
      if (name.startsWith('result')) {
        await tester.enterText(find.byType(TextField), 'SBI se bol raha hoon, aapka KYC update pending hai');
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
      } else if (name.startsWith('upi')) {
        await tester.tap(find.byKey(const Key('upi_section')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('upi_link_field')), 'upi://pay?pa=ravi.k@oksbi&pn=Ravi%20Kumar&am=500');
        await tester.enterText(find.byKey(const Key('upi_name_field')), 'Sunita Devi');
        await tester.ensureVisible(find.byKey(const Key('btn_upi_check')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn_upi_check')));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -330));
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/ux_tryapi_$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });

  testWidgets('shots: demo lab idle, results with one FAIL, timeline light + results dark', (tester) async {
    if (!await _loadFonts(tester)) return;
    // s3 is a benign bank message that must stay SAFE; s2 fails (a scam read as SAFE).
    Map<String, Object?> step(int i, bool pass, {bool safe = false}) => safe
        ? {
            'index': i,
            'delayMs': i == 0 ? 0 : 1500,
            'source': 'sms',
            'sender': 'VM-SBIINB',
            'text': i == 0 ? 'Welcome. Alerts are now active.' : 'Rs 250 credited to your account by salary',
            'contextLines': <String>[],
            'ruleTriggers': <String>[],
            'gemma': {'label': 'SAFE', 'scamType': '', 'reason': 'A routine message from a verified bank sender'},
            'fused': {'label': 'SAFE', 'confidence': 0.97, 'scamType': null, 'raisedBy': <String>[]},
            'alert': null,
            'expectedLabel': 'SAFE',
            'expectedFlags': <String>[],
            'actualFlags': <String>[],
            'pass': true,
          }
        : {
          'index': i,
          'delayMs': i == 0 ? 0 : 2500,
          'source': i == 0 ? 'sms' : 'call',
          'sender': i == 0 ? 'AX-FAKEBK' : 'caller_1',
          'text': i == 0 ? 'Rs 5000 debited from your account. Not you? Call back' : 'Galti se paise bhej diye, please wapas bhej do',
          'contextLines': i == 0
              ? <String>[]
              : ['Known context: user-typed SMS about a debit, 2 min ago, not from a bank', 'First message from this sender'],
          'ruleTriggers': i == 0 ? ['debited'] : ['wapas bhej', 'galti se'],
          'gemma': i == 0 ? null : {'label': 'SCAM', 'scamType': 'MISTAKEN_TRANSFER', 'reason': 'The caller refers to a message the user typed, not a bank alert'},
          'fused': {'label': pass || i == 0 ? (i == 0 ? 'SUSPICIOUS' : 'SCAM') : 'SAFE', 'confidence': 0.91, 'scamType': i == 0 ? null : 'MISTAKEN_TRANSFER', 'raisedBy': i == 0 ? ['rules'] : ['graph', 'gemma']},
          'alert': pass && i == 1 ? {'title': '[DEMO] Possible scam call', 'text': 'This caller refers to a message you wrote yourself.', 'reportAction': 'report'} : null,
          'expectedLabel': i == 0 ? 'SUSPICIOUS' : 'SCAM',
          'expectedFlags': i == 0 ? <String>[] : ['MISTAKEN_TRANSFER'],
          'actualFlags': pass || i == 0 ? (i == 0 ? <String>[] : ['MISTAKEN_TRANSFER']) : <String>[],
          'pass': pass || i == 0,
        };
    await tester.runAsync(() => _font('monospace', '/System/Library/Fonts/Menlo.ttc')); // else code blocks render as boxes
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const ch = MethodChannel('scamshield/demo');
    messenger.setMockMethodCallHandler(ch, (c) async => switch (c.method) {
          'demo.scenarios' => [
              {'id': 's1', 'icon': 'sms', 'titleHi': 'खाते से पैसे कटे, फिर कॉल', 'titleEn': 'Debit SMS, then a call', 'storyHi': 'एक SMS आया, फिर कॉल: पैसे लौटा दो', 'storyEn': 'An SMS, then a call: send the money back', 'steps': 2},
              {'id': 's2', 'icon': 'local_shipping', 'titleHi': 'झूठा कूरियर नोटिस', 'titleEn': 'Fake courier notice', 'storyHi': 'पार्सल रुका है, लिंक खोलें', 'storyEn': 'Parcel held, tap the link', 'steps': 2},
              {'id': 's3', 'icon': 'account_balance', 'titleHi': 'बैंक का असली मैसेज', 'titleEn': 'A real bank message', 'storyHi': 'बैंक का सामान्य अलर्ट, इसे सुरक्षित रहना चाहिए', 'storyEn': 'An ordinary bank alert that must stay safe', 'steps': 2},
            ],
          'demo.modelReady' => true,
          'demo.run' => () {
              final id = (c.arguments as Map)['id'];
              return {'scenarioId': id, 'engineUsed': 'gemma', 'steps': [step(0, id != 's2', safe: id == 's3'), step(1, id != 's2', safe: id == 's3')], 'pass': id != 's2'};
            }(),
          _ => true,
        });
    addTearDown(() => messenger.setMockMethodCallHandler(ch, null));
    addTearDown(() => tester.pumpWidget(const SizedBox())); // registered after the mocks
    for (final (name, dark, scale) in [
      ('idle_light', false, 1.0),
      ('results_light', false, 1.0),
      ('timeline_light', false, 1.0),
      ('results_dark', true, 1.0),
    ]) {
      final base = dark ? AppTheme.dark() : AppTheme.light();
      TextStyle? f(TextStyle? s) => s?.copyWith(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']);
      final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']),
          appBarTheme: base.appBarTheme.copyWith(titleTextStyle: f(base.appBarTheme.titleTextStyle)),
          chipTheme: base.chipTheme.copyWith(labelStyle: f(base.chipTheme.labelStyle)),
          listTileTheme: base.listTileTheme.copyWith(
              titleTextStyle: f(base.listTileTheme.titleTextStyle), subtitleTextStyle: f(base.listTileTheme.subtitleTextStyle)),
          filledButtonTheme: FilledButtonThemeData(
              style: base.filledButtonTheme.style!.copyWith(textStyle: WidgetStatePropertyAll(f(AppText.label)))),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: base.outlinedButtonTheme.style!.copyWith(textStyle: WidgetStatePropertyAll(f(AppText.label)))),
          textButtonTheme: TextButtonThemeData(
              style: base.textButtonTheme.style!.copyWith(textStyle: WidgetStatePropertyAll(f(AppText.label)))));
      tester.view.physicalSize = Size(720, name == 'idle_light' ? 3000 : 4400); // tall: the whole list fits one image
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
        home: Scaffold(appBar: AppBar(title: const Text('डेमो लैब')), body: const DemoLabScreen()),
      ));
      await tester.pumpAndSettle();
      if (name == 'timeline_light') {
        await tester.tap(find.byKey(const Key('demo_run_s1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byKey(const Key('demo_skip')));
        await tester.pumpAndSettle();
      } else if (name.startsWith('results')) {
        await tester.tap(find.byKey(const Key('demo_run_all')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byKey(const Key('demo_skip')));
        await tester.pumpAndSettle();
      }
      final pos = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      // The timeline shot starts at the opened card; the others at the top.
      pos.jumpTo(name == 'timeline_light' ? pos.pixels + tester.getTopLeft(find.byKey(const Key('demo_card_s1'))).dy - 90 : 0);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/ux_demolab_$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('shots: polish report after choosing lost, live rows in Hindi, app bar header', (tester) async {
    if (!await _loadFonts(tester)) return;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/events'), (_) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/prefs'), (_) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), (c) async => switch (c.method) {
          'serviceStatus' => {'enabled': true, 'connected': true},
          'modelStatus' => {'status': 'READY', 'message': '', 'path': '/data/model.task', 'sizeMb': 555},
          'downloadStatus' => {'status': 'IDLE'},
          _ => null,
        });
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), (c) async => switch (c.method) {
          'golden.status' => {'started': false},
          'report.pack' => {
              'targets': [
                {'phone': '1930', 'url': null},
                {'phone': null, 'url': 'https://cybercrime.gov.in'},
              ],
              'evidence': <Object?>[],
            },
          _ => true,
        });
    addTearDown(() {
      for (final c in ['events', 'prefs', 'api', 'handoff']) {
        messenger.setMockMethodCallHandler(MethodChannel('scamshield/$c'), null);
      }
    });
    final base = AppTheme.light();
    TextStyle? f(TextStyle? s) => s?.copyWith(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']);
    ButtonStyle b(ButtonStyle? s) => s!.copyWith(textStyle: WidgetStatePropertyAll(f(AppText.label)));
    final theme = base.copyWith(
        textTheme: base.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: ['Deva']),
        appBarTheme: base.appBarTheme.copyWith(titleTextStyle: f(base.appBarTheme.titleTextStyle)),
        chipTheme: base.chipTheme.copyWith(labelStyle: f(base.chipTheme.labelStyle)),
        listTileTheme: base.listTileTheme.copyWith(
            titleTextStyle: f(base.listTileTheme.titleTextStyle), subtitleTextStyle: f(base.listTileTheme.subtitleTextStyle)),
        filledButtonTheme: FilledButtonThemeData(style: b(base.filledButtonTheme.style)),
        outlinedButtonTheme: OutlinedButtonThemeData(style: b(base.outlinedButtonTheme.style)),
        textButtonTheme: TextButtonThemeData(style: b(base.textButtonTheme.style)));
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    GlobalKey? cur;
    Future<void> shoot(Widget home, {double scale = 1.0}) async {
      final key = cur = GlobalKey();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        builder: (c, child) => RepaintBoundary(
            key: key,
            child: MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!)),
        home: home,
      ));
      await tester.pumpAndSettle();
    }

    Future<void> save(String name) async {
      await tester.runAsync(() async {
        final bd = cur!.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await bd.toImage(pixelRatio: 1);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    tester.view.physicalSize = const Size(720, 1600);
    await shoot(Scaffold(appBar: AppBar(title: const Text('रिपोर्ट')), body: const ReportScreen()));
    await tester.tap(find.byKey(const Key('path_lost')));
    await tester.pumpAndSettle();
    await save('polish_report_lost_light');

    await shoot(Scaffold(appBar: AppBar(title: const Text('लाइव')), body: const LiveFeedScreen()));
    for (final m in <Map<String, Object?>>[
      {'type': 'service', 'connected': true},
      {'type': 'call', 'active': true},
      {'type': 'signal', 'kind': 'link', 'trigger': 'लिंक खोलें'},
      {'type': 'call', 'active': false},
    ]) {
      messenger.handlePlatformMessage('scamshield/events', const StandardMethodCodec().encodeSuccessEnvelope(m), (_) {});
    }
    await tester.pumpAndSettle();
    await save('polish_live_rows_light');

    // Whole shell: the real header action in the real AppBar, at 1.0x and at system 2.0x (chrome clamps to 1.2x).
    for (final scale in [1.0, 2.0]) {
      final key = GlobalKey();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        builder: (c, child) => RepaintBoundary(
            key: key,
            child: MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!)),
        home: const HomeShell(),
      ));
      await tester.pumpAndSettle();
      final r = tester.getRect(find.byKey(const Key('btn_report_1930')));
      expect(r.height, greaterThanOrEqualTo(48));
      expect(r.right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull, reason: 'header shell at $scale');
      await tester.runAsync(() async {
        final bd = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await bd.toImage(pixelRatio: 1);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/polish_header_light${scale == 2.0 ? '_2x' : ''}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
}
