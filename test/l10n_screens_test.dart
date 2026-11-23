import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/lessons/quiz_engine.dart';
import 'package:scamshield/screens/demo_lab_screen.dart';
import 'package:scamshield/screens/family_screen.dart';
import 'package:scamshield/screens/lessons_screen.dart';
import 'package:scamshield/screens/quiz_screen.dart';
import 'package:scamshield/screens/recording_screen.dart';
import 'package:scamshield/screens/report_screen.dart';
import 'package:scamshield/theme/app_theme.dart';

import 'qa/qa_harness.dart' show DiskBundle;

final _devanagari = RegExp(r'[ऀ-ॿ]');

Widget _app(Widget screen, {bool scoped = false}) {
  final app = MaterialApp(theme: AppTheme.light(), home: Scaffold(body: screen));
  return scoped ? LangScope(notifier: AppLanguage.current, child: app) : app;
}

Widget _recording() => RecordingScreen(api: RecordingApi(events: const Stream<Object?>.empty()));
Widget _lessons() => LessonsScreen(store: InMemoryQuizStore(), bundle: DiskBundle());

/// Native sides answer "not paired" / "no demos"; an unanswered channel would leave the spinners running.
void _fakeNative() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(const MethodChannel('scamshield/family'), (c) async => {'paired': false});
  m.setMockMethodCallHandler(const MethodChannel('scamshield/demo'), (c) async => c.method == 'demo.scenarios' ? <Object?>[] : false);
  addTearDown(() {
    m.setMockMethodCallHandler(const MethodChannel('scamshield/family'), null);
    m.setMockMethodCallHandler(const MethodChannel('scamshield/demo'), null);
  });
}

void main() {
  setUp(_fakeNative);
  tearDown(() => AppLanguage.debugSet('hi'));

  group('L10N_start_in_global_language', () {
    final cases = <String, (Widget Function(), String, String)>{
      'report': (() => const ReportScreen(), 'Report a scam', 'I lost money'),
      'family': (() => const FamilyScreen(), 'Show my code', 'Enter family code'),
      'recording': (_recording, 'Pick a recording', 'Open a call recording saved on this phone.'),
      'demo': (() => const DemoLabScreen(), 'No demos yet', 'No demo stories were found in this build'),
      'lessons': (_lessons, 'Start', 'Take a quiz to find your weak spots'),
    };
    for (final e in cases.entries) {
      testWidgets('L10N_${e.key}_starts_in_english', (t) async {
        AppLanguage.debugSet('en');
        await t.pumpWidget(_app(e.value.$1()));
        await t.pumpAndSettle();
        expect(find.textContaining(e.value.$2), findsWidgets);
        expect(find.textContaining(e.value.$3), findsWidgets);
        // the demo's empty state has no chips; Learn follows the top-bar language only
        if (e.key != 'demo' && e.key != 'lessons') expect(find.byWidgetPredicate((w) => w is ChoiceChip && w.key == const Key('lang_en') && w.selected), findsOneWidget);
      });
    }
  });

  test('L10N_tri_hne_falls_back_to_hi_and_en_never_to_hindi', () {
    const tri = Tri(hi: {'a': 'हिंदी', 'b': 'दो'}, hne: {'b': 'दू'}, en: {'b': 'two'});
    expect(tri('hne', 'a'), 'हिंदी'); // hne missing -> hi
    expect(tri('hne', 'b'), 'दू');
    expect(tri('en', 'a'), 'a'); // en missing -> the key, never the Hindi text
    expect(tri('en', 'b'), 'two');
    expect(tri('hi', 'zzz'), 'zzz');
  });

  test('L10N_every_hi_key_has_an_english_value_without_devanagari', () {
    final tables = <String, (Map<String, String>, Map<String, String>)>{
      'report': (ReportStrings.hi.m, ReportStrings.en.m),
      'family': (familyStrings['hi']!, familyStrings['en']!),
      'recording': (RecordingStrings.hi.m, RecordingStrings.en.m),
      'demo': (DemoStrings.hi.m, DemoStrings.en.m),
      'lessons': (LessonStrings.hi.m, LessonStrings.en.m),
    };
    for (final e in tables.entries) {
      final (hi, en) = e.value;
      for (final k in hi.keys) {
        expect(en.containsKey(k), isTrue, reason: '${e.key}: en is missing "$k"');
        expect(_devanagari.hasMatch(en[k] ?? ''), isFalse, reason: '${e.key}.en["$k"] contains Hindi');
      }
    }
    for (final k in LessonStrings.hi.m.keys) {
      expect(LessonStrings.hne.m.containsKey(k), isTrue, reason: 'lessons: hne is missing "$k"');
    }
  });

  group('L10N_live_switch', () {
    testWidgets('L10N_family_switches_live', (t) async {
      AppLanguage.debugSet('hi');
      await t.pumpWidget(_app(const FamilyScreen(), scoped: true));
      await t.pumpAndSettle();
      expect(find.text('मेरा कोड दिखाएँ'), findsOneWidget);
      AppLanguage.debugSet('en');
      await t.pump();
      expect(find.text('Show my code'), findsOneWidget);
      expect(find.text('मेरा कोड दिखाएँ'), findsNothing);
      AppLanguage.debugSet('hne');
      await t.pump();
      expect(find.text('मोर कोड देखाव'), findsOneWidget);
    });

    testWidgets('L10N_report_switches_live', (t) async {
      AppLanguage.debugSet('hi');
      await t.pumpWidget(_app(const ReportScreen(), scoped: true));
      await t.pumpAndSettle();
      expect(find.text('मेरे पैसे कट गए'), findsOneWidget);
      AppLanguage.debugSet('en');
      await t.pump();
      expect(find.text('I lost money'), findsOneWidget);
    });

    testWidgets('L10N_lessons_switch_live', (t) async {
      AppLanguage.debugSet('hi');
      await t.pumpWidget(_app(_lessons(), scoped: true));
      await t.pumpAndSettle();
      expect(find.text('कमज़ोर हिस्से जानने के लिए एक क्विज़ दें'), findsOneWidget);
      AppLanguage.debugSet('en');
      await t.pumpAndSettle();
      expect(find.text('Take a quiz to find your weak spots'), findsOneWidget);
    });

    testWidgets('L10N_chip_override_is_temporary', (t) async {
      AppLanguage.debugSet('hi');
      await t.pumpWidget(_app(const FamilyScreen(), scoped: true));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('lang_en')));
      await t.pump();
      expect(find.text('Show my code'), findsOneWidget);
      AppLanguage.debugSet('hne'); // a global change wins over the chip
      await t.pump();
      expect(find.text('मोर कोड देखाव'), findsOneWidget);
    });
  });
}
