import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/lessons/lesson_model.dart';
import 'package:scamshield/lessons/quiz_engine.dart';
import 'package:scamshield/screens/lessons_screen.dart';

/// Reads assets from disk so loading completes under the test's fake clock.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final b = File(key).readAsBytesSync();
    return ByteData.sublistView(Uint8List.fromList(b));
  }
}

List<Lesson> _hi() =>
    loadLessonsFromJson(File('assets/lessons/hi.json').readAsStringSync());

Future<void> _phone(WidgetTester t) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1.0;
  t.platformDispatcher.textScaleFactorTestValue = 2.0;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
}

Future<void> _pump(WidgetTester t, QuizStore store) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LessonsScreen(store: store, bundle: _DiskBundle()),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  setUp(() => AppLanguage.debugSet('hi')); // these tests read the default Hindi from the app-wide language
  testWidgets('T3_5_hindiCardsRender', (t) async {
    await _phone(t);
    await _pump(t, InMemoryQuizStore());
    final otp = _hi().first;
    expect(find.byKey(const Key('score_value')), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('lesson_otp')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text(otp.title), findsWidgets); // carousel card + list row
    await t.scrollUntilVisible(find.byKey(const Key('lesson_loan_app')), 200, scrollable: find.byType(Scrollable).first);
    await t.drag(find.byType(ListView), const Offset(0, 3000));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('lesson_otp')), 200, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(find.byKey(const Key('lesson_otp')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('lesson_otp')));
    await t.pumpAndSettle();
    expect(find.text(otp.cards[0].title), findsOneWidget);
    await t.drag(find.byKey(const Key('card_pages')), const Offset(-300, 0));
    await t.pumpAndSettle();
    expect(find.text(otp.cards[1].title), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('T3_5_quizUpdatesScore', (t) async {
    await _phone(t);
    final store = InMemoryQuizStore();
    await _pump(t, store);
    final otp = _hi().first;

    await t.scrollUntilVisible(find.byKey(const Key('lesson_otp')), 200, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(find.byKey(const Key('lesson_otp')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('lesson_otp')));
    await t.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byKey(const Key('cards_next')));
      await t.pumpAndSettle();
    }
    for (var q = 0; q < 3; q++) {
      await t.ensureVisible(
        find.byKey(Key('option_${otp.questions[q].correctIndex}')),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(Key('option_${otp.questions[q].correctIndex}')));
      await t.pumpAndSettle();
      expect(find.text('सही!'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsWidgets);
      await t.scrollUntilVisible(find.byKey(const Key('quiz_next')), 200);
      await t.ensureVisible(find.byKey(const Key('quiz_next')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('quiz_next')));
      await t.pumpAndSettle();
    }
    // 1 of 17 lessons at 100 -> score round(5.88) = 6
    expect(t.widget<Text>(find.byKey(const Key('result_score'))).data, '6');
    expect((await store.loadBest())['otp'], 100);
    await t.scrollUntilVisible(find.byKey(const Key('result_back')), 200);
    await t.ensureVisible(find.byKey(const Key('result_back')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('result_back')));
    await t.pumpAndSettle();
    await t.drag(find.byType(ListView), const Offset(0, 3000));
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('score_value'))).data, '6');
    expect(t.takeException(), isNull);
  });

  testWidgets('T3_5_wrongAnswerShowsTextAndIcon', (t) async {
    await _phone(t);
    await _pump(t, InMemoryQuizStore());
    final otp = _hi().first;
    await t.scrollUntilVisible(find.byKey(const Key('lesson_otp')), 200, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(find.byKey(const Key('lesson_otp')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('lesson_otp')));
    await t.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byKey(const Key('cards_next')));
      await t.pumpAndSettle();
    }
    final wrong =
        (otp.questions[0].correctIndex + 1) % otp.questions[0].options.length;
    await t.ensureVisible(find.byKey(Key('option_$wrong')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('option_$wrong')));
    await t.pumpAndSettle();
    expect(find.text('ध्यान दें'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget); // feedback header
    // The options sit below the feedback and may not be built yet: bring each into view.
    final right = Key('option_${otp.questions[0].correctIndex}');
    for (final (k, icon) in [(Key('option_$wrong'), Icons.cancel), (right, Icons.check_circle)]) {
      await t.scrollUntilVisible(find.byKey(k), -150, scrollable: find.byType(Scrollable).first);
      expect(find.descendant(of: find.byKey(k), matching: find.byIcon(icon)), findsOneWidget);
    }
    expect(t.takeException(), isNull);
  });
}
