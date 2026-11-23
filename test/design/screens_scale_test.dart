// Restyled screens must not overflow at text scale 2.0 on a 360x800 phone, light or dark.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/lessons/lesson_model.dart';
import 'package:scamshield/lessons/quiz_engine.dart';
import 'package:scamshield/screens/lessons_screen.dart';
import 'package:scamshield/screens/live_feed_screen.dart';
import 'package:scamshield/screens/quiz_screen.dart';
import 'package:scamshield/screens/report_screen.dart';
import 'package:scamshield/screens/setup_screen.dart';
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

void _emit(Map<String, Object?> m) => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .handlePlatformMessage(_events, const StandardMethodCodec().encodeSuccessEnvelope(m), (_) {});

void main() {
  final themes = {'light': AppTheme.light(), 'dark': AppTheme.dark()};

  for (final e in themes.entries) {
    testWidgets('lessons_screen_noOverflow_${e.key}_scale2', (t) async {
      await _show(t, e.value, LessonsScreen(store: InMemoryQuizStore(), bundle: _DiskBundle()));
      expect(find.byKey(const Key('score_value')), findsOneWidget);
      expect(t.takeException(), isNull);
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
        await _show(t, e.value, const SetupScreen());
        await t.pump(const Duration(milliseconds: 100)); // let the mocked channel replies land
        await t.pumpAndSettle();
        expect(find.byKey(const Key('setup_firstrun_card')), firstRun ? findsOneWidget : findsNothing);
        expect(find.text('0 / 4 ज़रूरी कदम पूरे'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(find.byKey(const Key('setup_prepermission_card')), 200);
        expect(find.byKey(const Key('setup_prepermission_card')), findsOneWidget);
        await t.scrollUntilVisible(find.text('सेटअप'), -500, maxScrolls: 100); // back to the top
        if (firstRun) {
          await t.ensureVisible(find.byKey(const Key('lang_hne')));
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
  }
}
