// Restyled screens must not overflow at text scale 2.0 on a 360x800 phone, light or dark.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/lessons/lesson_model.dart';
import 'package:scamshield/lessons/quiz_engine.dart';
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
import 'package:scamshield/widgets/verdict_card.dart';

class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(File(key).readAsBytesSync()));
}

const _events = 'scamshield/events';

Future<void> _show(WidgetTester t, ThemeData theme, Widget home) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(2.0)),
      child: Scaffold(body: home),
    ),
  ));
  await t.pumpAndSettle();
}

// Jump the screen's own ListView to its end. A drag would start at the list centre, which a multi-line input can cover.
Future<void> _toBottom(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    final p = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    p.jumpTo(p.maxScrollExtent);
    await t.pumpAndSettle();
  }
}

void _emit(Map<String, Object?> m) => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .handlePlatformMessage(_events, const StandardMethodCodec().encodeSuccessEnvelope(m), (_) {});

// Demo Lab fixtures: s2 fails, the others pass. [slow] puts a gap before each later event.
Map<String, Object?> _demoStep(int i, {required bool pass, required int delayMs}) => {
      'index': i,
      'delayMs': delayMs,
      'source': i == 0 ? 'sms' : 'call',
      'sender': i == 0 ? 'AX-FAKEBK' : 'caller_1',
      'text': 'Rs 5000 debited from your account, please send the money back',
      'contextLines': i == 0 ? <String>[] : ['Known context: user-typed SMS about a debit, 2 min ago, not from a bank'],
      'ruleTriggers': ['debited', 'send back'],
      'gemma': i == 0 ? null : {'label': 'SUSPICIOUS', 'scamType': 'FAKE_DEBIT', 'reason': 'Looks typed by a person, not sent by a bank'},
      'fused': {'label': pass ? 'SCAM' : 'SAFE', 'confidence': 0.93, 'scamType': 'MISTAKEN_TRANSFER', 'raisedBy': ['graph', 'rules']},
      'alert': pass ? {'title': '[DEMO] Possible scam call', 'text': 'This caller refers to a message you wrote yourself.', 'reportAction': 'report'} : null,
      'expectedLabel': 'SCAM',
      'expectedFlags': ['MISTAKEN_TRANSFER'],
      'actualFlags': pass ? ['MISTAKEN_TRANSFER'] : <String>[],
      'pass': pass,
    };

Future<Object?> _demoCall(MethodCall c, {required bool slow}) async => switch (c.method) {
      'demo.scenarios' => [
          for (final (id, hi, en) in const [('s1', 'खाते से पैसे कटे, फिर कॉल', 'Debit SMS, then a call'), ('s2', 'झूठा कूरियर नोटिस', 'Fake courier notice'), ('s3', 'बैंक का असली मैसेज', 'A real bank message')])
            {'id': id, 'icon': 'sms', 'titleHi': hi, 'titleEn': en, 'storyHi': 'एक SMS आया, फिर कॉल: पैसे लौटा दो', 'storyEn': 'An SMS, then a call: send the money back', 'steps': 2}
        ],
      'demo.modelReady' => true,
      'demo.run' => () {
          final id = (c.arguments as Map)['id'];
          final pass = id != 's2';
          return {
            'scenarioId': id,
            'engineUsed': 'gemma',
            'steps': [_demoStep(0, pass: pass, delayMs: 0), _demoStep(1, pass: pass, delayMs: slow ? 800 : 0)],
            'pass': pass,
          };
        }(),
      _ => true,
    };

void main() {
  final themes = {'light': AppTheme.light(), 'dark': AppTheme.dark()};

  for (final e in themes.entries) {
    testWidgets('lessons_screen_noOverflow_${e.key}_scale2', (t) async {
      await _show(t, e.value, LessonsScreen(store: InMemoryQuizStore(), bundle: _DiskBundle()));
      expect(find.byKey(const Key('score_value')), findsOneWidget);
      // Score 0: the compact one-line card, not the big StatTile.
      expect(find.text('पहला पाठ पूरा करें — आपका स्कोर यहाँ दिखेगा'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('lessons_progress_noOverflow_${e.key}_scale2', (t) async {
      final store = InMemoryQuizStore();
      await store.saveBest({'otp': 100});
      await _show(t, e.value, LessonsScreen(store: store, bundle: _DiskBundle()));
      expect(find.text('पाठ 1/8 पूरे'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('score_value'))).data, '13');
      expect(t.takeException(), isNull);
    });

    testWidgets('quiz_result_earned_noOverflow_${e.key}_scale2', (t) async {
      final lessons = loadLessonsFromJson(File('assets/lessons/hi.json').readAsStringSync());
      final engine = QuizEngine(lessons, InMemoryQuizStore());
      await engine.load();
      await _show(t, e.value, QuizScreen(lesson: lessons.first, engine: engine, lang: 'hi'));
      for (var i = 0; i < 3; i++) {
        await t.tap(find.byKey(const Key('cards_next')));
        await t.pumpAndSettle();
      }
      for (final q in lessons.first.questions) {
        final opt = find.byKey(Key('option_${q.correctIndex}'));
        await t.ensureVisible(opt);
        await t.pumpAndSettle();
        await t.tap(opt);
        await t.pumpAndSettle();
        await t.scrollUntilVisible(find.byKey(const Key('quiz_next')), 200);
        await t.ensureVisible(find.byKey(const Key('quiz_next')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('quiz_next')));
        await t.pumpAndSettle();
      }
      expect(find.text('+13 अंक'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('result_score'))).data, '13');
      expect(t.takeException(), isNull);
    });

    testWidgets('family_howItWorks_noOverflow_${e.key}_scale2', (t) async {
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const ch = MethodChannel('scamshield/family');
      var paired = false;
      m.setMockMethodCallHandler(ch, (c) async => switch (c.method) {
            'family.status' => {'paired': paired},
            'family.code' => {'code': '123456', 'remainingSec': 20},
            _ => null,
          });
      addTearDown(() => m.setMockMethodCallHandler(ch, null));
      await _show(t, e.value, const FamilyScreen(initialLang: 'hi'));
      expect(find.byKey(const Key('family_how')), findsOneWidget);
      expect(t.takeException(), isNull); // choose
      paired = true;
      await t.pumpWidget(const SizedBox());
      await _show(t, e.value, const FamilyScreen(initialLang: 'hi'));
      await t.scrollUntilVisible(find.byKey(const Key('family_ask_caller')), 100);
      expect(find.text('फ़ोन करने वाले से यह कोड पूछें'), findsOneWidget);
      expect(t.takeException(), isNull); // code
      await t.pumpWidget(const SizedBox()); // stop the countdown timer
    });

    for (final lang in ['hi', 'en']) {
      testWidgets('quiz_screen_noOverflow_${e.key}_${lang}_scale2', (t) async {
        final lessons = loadLessonsFromJson(File('assets/lessons/$lang.json').readAsStringSync());
        final engine = QuizEngine(lessons, InMemoryQuizStore());
        await engine.load();
        await _show(t, e.value, QuizScreen(lesson: lessons.first, engine: engine, lang: lang));
        expect(t.takeException(), isNull); // cards
        await t.tap(find.byKey(const Key('cards_next')));
        await t.pumpAndSettle();
        for (var i = 0; i < 2; i++) {
          await t.tap(find.byKey(const Key('cards_next')));
          await t.pumpAndSettle();
        }
        expect(t.takeException(), isNull); // quiz, unanswered
        final q = lessons.first.questions;
        for (var n = 0; n < q.length; n++) {
          await t.drag(find.byType(ListView), const Offset(0, 3000)); // back to the top
          await t.pumpAndSettle();
          final wrong = (q[n].correctIndex + 1) % q[n].options.length;
          await t.scrollUntilVisible(find.byKey(Key('option_$wrong')), 200);
          await t.ensureVisible(find.byKey(Key('option_$wrong'))); // centre must be on screen to hit
          await t.pumpAndSettle();
          await t.tap(find.byKey(Key('option_$wrong')));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull); // answered
          await t.scrollUntilVisible(find.byKey(const Key('quiz_next')), 200);
          await t.ensureVisible(find.byKey(const Key('quiz_next')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('quiz_next')));
          await t.pumpAndSettle();
        }
        expect(find.byKey(const Key('result_score')), findsOneWidget);
        expect(t.takeException(), isNull); // result
      });
    }

    testWidgets('setup_screen_noOverflow_${e.key}_scale2', (t) async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel(_events), (_) async => null);
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), (c) async => switch (c.method) {
            'serviceStatus' => {'enabled': true, 'connected': true},
            'modelStatus' => {'status': 'READY', 'message': 'ok', 'path': '/data/model.task', 'sizeMb': 555},
            'downloadStatus' => {'status': 'RUNNING', 'done': 100 * 1024 * 1024, 'total': 555 * 1024 * 1024},
            'micPermission' => true,
            'perm.notificationsGranted' => false,
            'perm.notificationAccessGranted' => true,
            _ => null,
          });
      addTearDown(() {
        messenger.setMockMethodCallHandler(const MethodChannel(_events), null);
        messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), null);
      });
      await _show(t, e.value, const SetupScreen());
      expect(t.takeException(), isNull);
      await t.drag(find.byType(ListView), const Offset(0, -6000)); // reach the lower steps
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    for (final firstRun in [true, false]) {
      testWidgets('setup_screen_${firstRun ? 'firstRun' : 'langChosen_advancedOpen'}_noOverflow_${e.key}_scale2', (t) async {
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(const MethodChannel(_events), (_) async => null);
        messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), (c) async => switch (c.method) {
              'serviceStatus' => {'enabled': false, 'connected': false},
              'modelStatus' => {'status': 'MISSING', 'message': 'none'},
              'downloadStatus' => {'status': 'IDLE'},
              'micPermission' => false,
              'perm.notificationsGranted' => false,
              'perm.notificationAccessGranted' => false,
              _ => null,
            });
        messenger.setMockMethodCallHandler(const MethodChannel('scamshield/prefs'),
            (c) async => !firstRun && c.method == 'getString' ? 'hi' : null);
        addTearDown(() {
          messenger.setMockMethodCallHandler(const MethodChannel(_events), null);
          messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), null);
          messenger.setMockMethodCallHandler(const MethodChannel('scamshield/prefs'), null);
        });
        // Unmount before the handlers go away (teardowns run last-in first), so the screen's
        // event-channel cancel cannot hit a missing or the next test's handler.
        addTearDown(() => t.pumpWidget(const SizedBox()));
        await _show(t, e.value, const SetupScreen());
        await t.pump(const Duration(milliseconds: 100)); // let the mocked channel replies land
        await t.pumpAndSettle();
        expect(find.byKey(const Key('setup_firstrun_card')), firstRun ? findsOneWidget : findsNothing);
        expect(find.text('0 / 4 ज़रूरी कदम पूरे'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(find.byKey(const Key('setup_prepermission_card')), 200);
        expect(find.byKey(const Key('setup_prepermission_card')), findsOneWidget);
        // back to the top (the AppBar owns the "सेटअप" title; the counter is the first line)
        await t.scrollUntilVisible(find.text('0 / 4 ज़रूरी कदम पूरे'), -500, maxScrolls: 100);
        if (firstRun) {
          await t.ensureVisible(find.byKey(const Key('lang_hne')));
          await t.pumpAndSettle();
          // Language rows are full-width 56dp buttons, not chips.
          expect(t.getSize(find.byKey(const Key('lang_hne'))).height, greaterThanOrEqualTo(56));
          expect(find.byType(ChoiceChip), findsNothing);
          await t.tap(find.byKey(const Key('lang_hne')));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('setup_firstrun_card')), findsNothing);
        } else {
          await t.scrollUntilVisible(find.byKey(const Key('setup_advanced')), 500, maxScrolls: 100);
          await t.tap(find.byKey(const Key('setup_advanced')));
          await t.pumpAndSettle();
          await t.drag(find.byType(ListView), const Offset(0, -6000));
          await t.pumpAndSettle();
        }
        expect(t.takeException(), isNull);
      });
    }

    for (final golden in [true, false]) {
      testWidgets('report_screen_noOverflow_${e.key}_golden${golden ? 'Active' : 'Inactive'}_scale2', (t) async {
        Map<String, Object?> pack() => {
              'targets': [
                {'phone': '1930', 'url': null},
                {'phone': null, 'url': 'https://cybercrime.gov.in'},
              ],
              'evidence': [
                {'time': '2026-11-23 10:15 IST', 'scamType': 'DIGITAL_ARREST', 'source': 'caption', 'triggers': ['CBI', 'arrest warrant']},
              ],
            };
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), (c) async => switch (c.method) {
              'golden.status' => golden
                  ? {'started': true, 'startMs': 1, 'remainingMs': 3000000, 'pack': pack()}
                  : {'started': false},
              'report.pack' => pack(),
              _ => true,
            });
        addTearDown(() => messenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), null));
        await _show(t, e.value, const ReportScreen());
        expect(t.takeException(), isNull);
        if (!golden) {
          await t.ensureVisible(find.byKey(const Key('path_lost')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('path_lost')));
          await t.pumpAndSettle();
        }
        expect(find.byKey(const Key('golden_timer')), golden ? findsOneWidget : findsNothing);
        await t.drag(find.byType(SingleChildScrollView), const Offset(0, -6000)); // reach the lower cards
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox()); // cancels the golden-hour ticker
      });
    }

    for (final saved in [true, false]) {
      testWidgets('settings_screen_${saved ? 'districtSaved' : 'noDistrict'}_noOverflow_${e.key}_scale2', (t) async {
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'),
            (c) async => c.method == 'getSettings' ? <String, Object?>{'useLlm': true} : null);
        messenger.setMockMethodCallHandler(const MethodChannel('scamshield/prefs'),
            (c) async => saved && c.method == 'getString' ? 'Durg' : null);
        messenger.setMockMethodCallHandler(const MethodChannel('scamshield/trend'), (_) async => {'count': 3});
        addTearDown(() {
          messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), null);
          messenger.setMockMethodCallHandler(const MethodChannel('scamshield/prefs'), null);
          messenger.setMockMethodCallHandler(const MethodChannel('scamshield/trend'), null);
        });
        addTearDown(() => t.pumpWidget(const SizedBox())); // registered after the mocks: runs before they go away
        await _show(t, e.value, const SettingsScreen());
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(find.byKey(const Key('exportButton')), 300,
            scrollable: find.byType(Scrollable).first, maxScrolls: 100);
        await t.pumpAndSettle();
        expect(find.byKey(const Key('districtPicker')), findsOneWidget);
        expect(find.text(saved ? 'Durg' : 'ज़िला चुनें'), findsOneWidget);
        expect(find.text('आपके मैसेज, कॉल, नंबर और नाम कभी फ़ोन से बाहर नहीं जाते'), findsOneWidget);
        expect(t.getSize(find.byKey(const Key('exportButton'))).height, greaterThanOrEqualTo(56));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('settings_screen_advanced_collapsedThenExpanded_noOverflow_${e.key}_scale2', (t) async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'),
          (c) async => c.method == 'getSettings' ? <String, Object?>{'useLlm': true} : null);
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/prefs'), (_) async => null);
      addTearDown(() {
        messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), null);
        messenger.setMockMethodCallHandler(const MethodChannel('scamshield/prefs'), null);
      });
      addTearDown(() => t.pumpWidget(const SizedBox())); // registered after the mocks: runs before they go away
      await _show(t, e.value, const SettingsScreen());
      final adv = find.byKey(const Key('settings_advanced'));
      await t.scrollUntilVisible(adv, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 100);
      // Collapsed by default: developer controls are not in the tree.
      expect(find.text('Use on-device Gemma'), findsNothing);
      expect(find.byKey(const Key('demoModeSwitch')), findsNothing);
      expect(t.takeException(), isNull);
      await t.ensureVisible(adv);
      await t.pumpAndSettle();
      await t.tap(adv);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('Use on-device Gemma'), 300,
          scrollable: find.byType(Scrollable).first, maxScrolls: 100);
      expect(find.text('Use on-device Gemma'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('live_feed_screen_noOverflow_${e.key}_scale2', (t) async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel(_events), (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(const MethodChannel(_events), null));
      await _show(t, e.value, const LiveFeedScreen());
      expect(t.takeException(), isNull); // empty state
      _emit({'type': 'call', 'active': true});
      _emit({'type': 'caption', 'text': 'आपके खाते से पैसे कट जाएंगे, अभी ओटीपी बताइए', 'via': 'a11y'});
      _emit({'type': 'statement', 'text': 'आपका पार्सल रुका है, लिंक खोलें'});
      _emit({'type': 'signal', 'kind': 'otp', 'trigger': 'ओटीपी'});
      _emit({'type': 'mic_probe', 'status': 'SILENT', 'source': 'VOICE_CALL', 'dbfs': -90.0, 'peak': 0, 'path': '/x.wav'});
      _emit({'type': 'error', 'where': 'model', 'message': 'something went wrong while loading'});
      _emit({
        'type': 'verdict',
        'text': 'ओटीपी बताइए',
        'label': 'SCAM',
        'confidence': 0.87,
        'reason': 'कॉल करने वाला ओटीपी माँग रहा है',
        'triggers': ['ओटीपी बताइए', 'खाता बंद'],
        'engine': 'gemma+rules',
        'latencyMs': 1420,
        'source': 'caption',
        'callRisk': 0.8,
        'callLevel': 'SCAM',
      });
      await t.pumpAndSettle();
      expect(find.byType(VerdictCard), findsOneWidget); // events reached the screen
      expect(t.takeException(), isNull);
    });

    testWidgets('live_feed_rows_hindiFirst_englishMuted_${e.key}_scale2', (t) async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel(_events), (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(const MethodChannel(_events), null));
      await _show(t, e.value, const LiveFeedScreen());
      t.view.physicalSize = const Size(360, 3000); // rows are lazily built: keep all of them on screen
      await t.pumpAndSettle();
      _emit({'type': 'call', 'active': true});
      _emit({'type': 'signal', 'kind': 'link', 'trigger': 'लिंक'});
      _emit({'type': 'service', 'connected': false});
      await t.pumpAndSettle();
      expect(find.text('कॉल शुरू हुई'), findsOneWidget);
      expect(find.text('Call started'), findsOneWidget);
      expect(find.text('कॉल के दौरान संकेत: लिंक'), findsOneWidget);
      expect(find.text('In-call signal: link (लिंक)'), findsOneWidget);
      expect(find.text('सुरक्षा सेवा बंद हो गई'), findsOneWidget);
      expect(find.text('Protection service stopped'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('report_chooseLost_scrollsDetailIntoView_${e.key}_scale2', (t) async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), (c) async => switch (c.method) {
            'golden.status' => {'started': false},
            'report.pack' => {
                'targets': [
                  {'phone': '1930', 'url': null},
                ],
                'evidence': <Object?>[],
              },
            _ => true,
          });
      addTearDown(() => messenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), null));
      await _show(t, e.value, const ReportScreen());
      final scroll = t.state<ScrollableState>(find.byType(Scrollable).first).position;
      await t.ensureVisible(find.byKey(const Key('path_lost'))); // off screen at 2.0x
      await t.pumpAndSettle();
      final before = scroll.pixels;
      await t.tap(find.byKey(const Key('path_lost')));
      await t.pumpAndSettle();
      expect(scroll.pixels, greaterThan(before)); // the page moved: the detail is now the first thing seen
      final top = t.getTopLeft(find.byKey(const Key('golden_start'))).dy;
      expect(top, inInclusiveRange(0, 600)); // inside the 608dp scroll viewport
      expect(t.takeException(), isNull);
    });

    for (final state in ['empty', 'result', 'upi_mismatch', 'failed']) {
      testWidgets('try_api_screen_${state}_noOverflow_${e.key}_scale2', (t) async {
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final calls = <String>[];
        messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), (c) async {
          calls.add(c.method);
          if (state == 'failed' && c.method == 'classify') throw PlatformException(code: 'X', message: 'model not loaded');
          return switch (c.method) {
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
          };
        });
        messenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), (_) async => true);
        addTearDown(() {
          messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), null);
          messenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), null);
        });
        addTearDown(() => t.pumpWidget(const SizedBox())); // registered after the mocks: runs before they go away
        await _show(t, e.value, const TryApiScreen());
        expect(find.byKey(const Key('try_empty')), findsOneWidget);
        expect(t.takeException(), isNull);
        if (state == 'empty') {
          // Empty input: a visible Hindi inline error, and no channel call.
          await t.tap(find.byType(FilledButton));
          await t.pumpAndSettle();
          expect(find.text('पहले मैसेज डालें'), findsOneWidget);
          expect(calls, isEmpty);
        }
        if (state == 'failed') {
          // Native failure: friendly bilingual retry state, never the raw exception text.
          await t.enterText(find.byType(TextField), 'hello');
          await t.tap(find.byType(FilledButton));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('try_failed')), findsOneWidget);
          expect(find.text('जाँच नहीं हो पाई, फिर कोशिश करें'), findsOneWidget);
          expect(find.textContaining('PlatformException'), findsNothing);
          expect(find.textContaining('model not loaded'), findsNothing);
        }
        if (state == 'result') {
          await t.enterText(find.byType(TextField), 'SBI se bol raha hoon, aapka KYC update pending hai');
          await t.tap(find.byType(FilledButton));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('try_empty')), findsNothing);
          await _toBottom(t);
          expect(find.byType(VerdictCard), findsOneWidget);
          expect(find.byKey(const Key('helpline_1930')), findsOneWidget);
        } else if (state == 'upi_mismatch') {
          await t.ensureVisible(find.byKey(const Key('upi_section')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('upi_section')));
          await t.pumpAndSettle();
          await t.enterText(find.byKey(const Key('upi_link_field')), 'upi://pay?pa=ravi.k@oksbi&pn=Ravi%20Kumar&am=500');
          await t.enterText(find.byKey(const Key('upi_name_field')), 'Sunita Devi');
          await t.ensureVisible(find.byKey(const Key('btn_upi_check')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('btn_upi_check')));
          await t.pumpAndSettle();
          await _toBottom(t);
          expect(find.byKey(const Key('upi_mismatch')), findsOneWidget);
          expect(find.textContaining('Sunita Devi'), findsWidgets);
        }
        expect(t.getSize(find.byType(FilledButton)).height, greaterThanOrEqualTo(56));
        expect(t.takeException(), isNull);
      });
    }

    for (final state in ['empty', 'downloading', 'transcribing', 'results']) {
      testWidgets('recording_screen_${state}_noOverflow_${e.key}_scale2', (t) async {
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const ch = MethodChannel('scamshield/recording');
        final events = StreamController<Object?>.broadcast();
        messenger.setMockMethodCallHandler(ch, (c) async => switch (c.method) {
              'recording.status' => {'modelReady': state != 'downloading', 'busy': false},
              'recording.pending' || 'recording.pick' => false,
              _ => true,
            });
        addTearDown(() {
          messenger.setMockMethodCallHandler(ch, null);
          events.close();
        });
        addTearDown(() => t.pumpWidget(const SizedBox())); // registered after the mocks: runs before they go away
        await _show(t, e.value, RecordingScreen(initialLang: 'hi', api: RecordingApi(events: events.stream)));
        expect(find.byKey(Key(state == 'downloading' ? 'btn_download' : 'btn_pick')), findsOneWidget);
        expect(t.getSize(find.byKey(Key(state == 'downloading' ? 'btn_download' : 'btn_pick'))).height,
            greaterThanOrEqualTo(56));
        expect(t.takeException(), isNull);
        if (state == 'downloading') {
          await t.tap(find.byKey(const Key('btn_download')));
          await t.pump();
          events.add({'stage': 'download', 'pct': 40});
          await t.pumpAndSettle();
          expect(find.byKey(const Key('progress_bar')), findsOneWidget);
        } else if (state != 'empty') {
          events.add({'stage': 'shared', 'pct': 0});
          await t.pump();
          await t.pump();
          events.add({
            'stage': 'stt',
            'pct': 40,
            'segment': {'startMs': 0, 'text': 'नमस्ते, मैं आपके बैंक से बोल रहा हूँ'},
          });
          await t.pumpAndSettle();
          expect(find.byKey(const Key('progress_hint')), findsOneWidget);
        }
        if (state == 'results') {
          final stmts = [
            {'startMs': 0, 'text': 'नमस्ते, मैं आपके बैंक से बोल रहा हूँ', 'label': 'SAFE', 'triggers': <String>[]},
            {'startMs': 12000, 'text': 'आपका खाता बंद हो जाएगा, ओटीपी बताइए', 'label': 'SUSPICIOUS', 'triggers': ['ओटीपी']},
            {'startMs': 65000, 'text': 'अभी पैसे भेजें वरना गिरफ़्तारी होगी', 'label': 'SCAM', 'triggers': ['गिरफ़्तारी', 'पैसे भेजें']},
          ];
          events.add({
            'stage': 'done',
            'pct': 100,
            'report': {'overall': 'SCAM', 'risk': 0.87, 'statements': stmts, 'topTriggers': ['गिरफ़्तारी', 'ओटीपी']},
          });
          await t.pumpAndSettle();
          expect(find.byKey(const Key('risk_card')), findsOneWidget);
          await t.drag(find.byType(SingleChildScrollView), const Offset(0, -6000)); // reach the last rows
          await t.pumpAndSettle();
          expect(find.byKey(const Key('row_2')), findsOneWidget);
        }
        expect(t.takeException(), isNull);
      });
    }

    for (final state in ['idle', 'midrun', 'results_one_fail']) {
      testWidgets('demo_lab_${state}_noOverflow_${e.key}_scale2', (t) async {
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const ch = MethodChannel('scamshield/demo');
        messenger.setMockMethodCallHandler(ch, (c) => _demoCall(c, slow: state == 'midrun'));
        addTearDown(() => messenger.setMockMethodCallHandler(ch, null));
        addTearDown(() => t.pumpWidget(const SizedBox())); // registered after the mocks: runs before they go away
        await _show(t, e.value, const DemoLabScreen());
        await t.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const Key('demo_card_s3')), findsOneWidget);
        expect(t.getSize(find.byKey(const Key('demo_run_all'))).height, greaterThanOrEqualTo(56));
        expect(t.takeException(), isNull);
        if (state == 'midrun') {
          await t.tap(find.byKey(const Key('demo_run_all')));
          await t.pump(const Duration(milliseconds: 100)); // s1 event 1 shown, event 2 waits on its gap
          expect(find.byKey(const Key('demo_progress')), findsOneWidget);
          expect(find.byKey(const Key('demo_step_1')), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox()); // unmount while the timer is pending
        } else if (state == 'results_one_fail') {
          await t.tap(find.byKey(const Key('demo_run_all')));
          await t.pump(const Duration(milliseconds: 100));
          await t.pumpAndSettle();
          expect(find.descendant(of: find.byKey(const Key('demo_badge_s2')), matching: find.text('FAIL')), findsOneWidget);
          expect(find.descendant(of: find.byKey(const Key('demo_sum_fail')), matching: find.text('1')), findsOneWidget);
          expect(find.byKey(const Key('demo_step_1')), findsWidgets); // the failed card opens itself
          await t.drag(find.byType(SingleChildScrollView).first, const Offset(0, -6000));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('demo_reset')), findsOneWidget);
          expect(t.takeException(), isNull);
        }
      });
    }
  }
}
