import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/lessons/lesson_model.dart';
import 'package:scamshield/lessons/prefs_store.dart';
import 'package:scamshield/lessons/quiz_engine.dart';
import 'package:scamshield/models/verdict.dart';
import 'package:scamshield/screens/family_screen.dart';
import 'package:scamshield/screens/lessons_screen.dart';
import 'package:scamshield/screens/live_feed_screen.dart';
import 'package:scamshield/screens/try_api_screen.dart';
import 'package:scamshield/widgets/verdict_card.dart';

import 'qa_harness.dart';

Map<String, Object?> _v(String label, {String text = 'x', double conf = 0.9}) => {
      'text': text, 'label': label, 'confidence': conf, 'reason': 'r', 'triggers': <String>[],
      'engine': 'rules', 'latencyMs': 1, 'source': 'manual',
    };

Lesson _lesson(String id) => Lesson(id: id, title: id, cards: const [], questions: [
      for (var i = 0; i < 4; i++)
        QuizQuestion(question: 'q$i', options: const ['a', 'b', 'c'], correctIndex: 1, explanation: ''),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('literacy score', () {
    test('QA_score_roundsMeanOfBest_notOfLastAttempt', () async {
      final eng = QuizEngine([_lesson('a'), _lesson('b'), _lesson('c')], InMemoryQuizStore());
      await eng.record('a', [1, 1, 1, 0]); // 75
      await eng.record('b', [1, 0, 0, 0]); // 25
      await eng.record('a', [0, 0, 0, 0]); // worse retry must not lower best
      expect(eng.bestFor('a'), 75);
      expect(eng.score, 33); // (75+25+0)/3 = 33.3
      expect(eng.grade('a', [1, 1, 1, 1]).percent, 100);
    });

    test('QA_score_loadDropsForeignIdsAndClampsCorruptValues', () async {
      final store = InMemoryQuizStore();
      await store.saveBest({'a': 250, 'b': -40, 'gone': 90});
      final eng = QuizEngine([_lesson('a'), _lesson('b')], store);
      await eng.load();
      expect(eng.bestFor('a'), 100);
      expect(eng.bestFor('b'), 0);
      expect(eng.score, 50);
    });

    test('QA_prefsStore_missingNativeHandler_keepsScoresInMemory', () async {
      final s = PrefsQuizStore(channel: const MethodChannel('qa/none'));
      expect(await s.loadBest(), isEmpty);
      await s.saveBest({'a': 80});
      expect(await s.loadBest(), {'a': 80});
    });

    test('QA_prefsStore_corruptJson_isIgnored_and_roundTrips', () async {
      String? stored = '{not json';
      final ch = const MethodChannel('qa/prefs');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (c) async {
        if (c.method == 'getString') return stored;
        stored = (c.arguments as Map)['value'] as String;
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null));
      final s = PrefsQuizStore(channel: ch);
      expect(await s.loadBest(), isEmpty);
      await s.saveBest({'otp': 67});
      expect(jsonDecode(stored!), {'otp': 67});
      expect(await PrefsQuizStore(channel: ch).loadBest(), {'otp': 67});
    });

    test('QA_lessonAssets_threeLanguagesGradeFullMarks', () async {
      for (final lang in ['hi', 'hne', 'en']) {
        final lessons = await loadLessonsFromAssets(lang, bundle: DiskBundle());
        final eng = QuizEngine(lessons, InMemoryQuizStore());
        for (final l in lessons) {
          await eng.record(l.id, [for (final q in l.questions) q.correctIndex]);
        }
        expect(eng.score, 100, reason: lang);
      }
    });

    testWidgets('QA_lessonsScreen_scoreShownFromStore_andLangSwitchReloads', (t) async {
      final store = InMemoryQuizStore();
      await store.saveBest({'otp': 100, 'kyc': 50});
      await show(t, themes['light']!(), LessonsScreen(store: store, bundle: DiskBundle(), initialLang: 'en'), scale: 1.0);
      expect(t.widget<Text>(find.byKey(const Key('score_value'))).data, '19'); // (100+50)/8 = 18.75
      expect(find.text('Best: 100%'), findsOneWidget);
      await tapVisible(t, find.byKey(const Key('lang_hi')));
      await t.pumpAndSettle();
      expect(find.textContaining('सर्वश्रेष्ठ: 100%'), findsOneWidget);
      expect(find.text('Best: 100%'), findsNothing);
    });
  });

  group('try API (paste) flow', () {
    Future<FakeChannel> pump(WidgetTester t, Future<Object?> Function(MethodCall) h) async {
      final api = FakeChannel('scamshield/api', h)..install();
      await show(t, themes['light']!(), const TryApiScreen(), scale: 1.0);
      return api;
    }

    testWidgets('QA_tryApi_emptyAndWhitespaceInput_doesNotCallNative', (t) async {
      final api = await pump(t, (c) async => _v('SAFE'));
      await tapVisible(t, find.byType(FilledButton));
      await t.enterText(find.byType(TextField), '   \n  ');
      await tapVisible(t, find.byType(FilledButton));
      await t.pumpAndSettle();
      expect(api.named('classify'), isEmpty);
      expect(find.byType(VerdictCard), findsNothing);
      expect(t.takeException(), isNull);
    });

    for (final (name, text, label) in [
      ('hindiDevanagari', 'मैं सीबीआई से बोल रहा हूं, आप डिजिटल अरेस्ट में हैं', 'SCAM'),
      ('hinglish', 'Sir aapke phone pe OTP aaya hoga, woh bata dijiye', 'SUSPICIOUS'),
    ]) {
      testWidgets('QA_tryApi_${name}_textReachesNativeUnmangled_andVerdictShown', (t) async {
        final api = await pump(t, (c) async => _v(label, text: text, conf: 0.77));
        await t.enterText(find.byType(TextField), '  $text  ');
        await tapVisible(t, find.byType(FilledButton));
        await t.pumpAndSettle();
        final args = api.named('classify').single.arguments as Map;
        expect(args['text'], text); // trimmed, no mojibake
        expect(args['source'], 'manual');
        expect(find.text(const {'SCAM': 'धोखाधड़ी!', 'SUSPICIOUS': 'सावधान', 'SAFE': 'सुरक्षित'}[label]!), findsOneWidget);
      });
    }

    testWidgets('QA_tryApi_veryLongInput_noCrash_fullTextSent', (t) async {
      final long = 'OTP बताइए ' * 3000; // ~30k chars, mixed script
      final api = await pump(t, (c) async => _v('SCAM', text: long));
      await t.enterText(find.byType(TextField), long);
      await tapVisible(t, find.byType(FilledButton));
      await t.pumpAndSettle();
      expect((api.named('classify').single.arguments as Map)['text'], long.trim());
      expect(find.byType(VerdictCard), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('QA_tryApi_busyState_disablesButton_thenRecovers', (t) async {
      final gate = Completer<Object?>();
      final api = await pump(t, (c) => gate.future);
      await t.enterText(find.byType(TextField), 'hello');
      await tapVisible(t, find.byType(FilledButton));
      expect(find.descendant(of: find.byType(FilledButton), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await t.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(api.named('classify'), hasLength(1)); // double tap ignored
      gate.complete(_v('SAFE'));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byType(FilledButton), matching: find.byType(CircularProgressIndicator)), findsNothing);
      expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    });

    testWidgets('QA_tryApi_nativeError_showsMessage_andButtonReenabled', (t) async {
      await pump(t, (c) async => throw PlatformException(code: 'MODEL', message: 'model not loaded'));
      await t.enterText(find.byType(TextField), 'hello');
      await tapVisible(t, find.byType(FilledButton));
      await t.pumpAndSettle();
      expect(find.textContaining('model not loaded'), findsOneWidget);
      expect(find.byType(VerdictCard), findsNothing);
      expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    });

    testWidgets('QA_tryApi_history_newestFirst', (t) async {
      var n = 0;
      await pump(t, (c) async => _v(++n == 1 ? 'SCAM' : 'SAFE'));
      for (var i = 0; i < 2; i++) {
        await t.enterText(find.byType(TextField), 'msg $i');
        FocusManager.instance.primaryFocus?.unfocus();
        await t.pump();
        await tapVisible(t, find.byType(FilledButton));
        await t.pumpAndSettle();
      }
      // newest (2nd call, SAFE) must sit above the older SCAM check, whether that one is a card or a history row
      final newest = find.text('सुरक्षित');
      final older = find.textContaining('धोखाधड़ी');
      await reveal(t, older);
      expect(newest, findsOneWidget);
      expect(t.getTopLeft(newest).dy, lessThan(t.getTopLeft(older).dy));
    });

    testWidgets('QA_tryApi_oneTapExample_fillsField', (t) async {
      await pump(t, (c) async => _v('SAFE'));
      final example = find.byKey(const Key('try_example'));
      await tapVisible(t, example);
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, isNotEmpty);
    });
  });

  group('verdict model', () {
    test('QA_verdict_fromMap_clampsAndDefaults', () {
      final v = Verdict.fromMap({'label': 'weird', 'confidence': 7});
      expect(v.label, RiskLabel.safe);
      expect(v.confidence, 1.0);
      expect(Verdict.fromMap({'label': 'scam', 'confidence': -3}).confidence, 0.0);
      expect(Verdict.fromMap(const {}).engine, 'unknown');
      expect(Verdict.fromMap({'label': 'Suspicious', 'confidence': 0.456}).headline, 'This statement is SUSPICIOUS · 46%');
    });
  });

  group('family code TOTP', () {
    testWidgets('QA_family_totp_countdownThenRefetchRotatesCode_andClearsMatchAnswer', (t) async {
      var fetches = 0;
      final fam = FakeChannel('scamshield/family', (c) async {
        if (c.method == 'family.status') return {'paired': true};
        if (c.method == 'family.code') {
          fetches++;
          return fetches == 1 ? {'code': '111222', 'remainingSec': 3} : {'code': '333444', 'remainingSec': 30};
        }
        return null;
      })..install();
      await show(t, themes['light']!(), const FamilyScreen(initialLang: 'en'), scale: 1.0, settle: false);
      await t.pump(const Duration(milliseconds: 10));
      String code() => t.widget<Text>(find.byKey(const Key('family_code'))).data!;
      String rem() => t.widget<Text>(find.byKey(const Key('family_remaining'))).data!;
      await reveal(t, find.byKey(const Key('family_code')));
      expect(code(), '111 222');
      expect(rem(), '3 sec');
      await tapVisible(t, find.byKey(const Key('family_yes')));
      expect(find.byKey(const Key('family_yes_msg')), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      expect(rem(), '2 sec');
      expect(find.byKey(const Key('family_yes_msg')), findsOneWidget); // same code, answer kept
      await t.pump(const Duration(seconds: 1)); // remaining 2 -> 1
      await t.pump(const Duration(seconds: 1)); // 1 -> refetch
      await t.pump(const Duration(milliseconds: 10));
      expect(fam.named('family.code'), hasLength(2));
      await reveal(t, find.byKey(const Key('family_code')));
      expect(code(), '333 444');
      expect(rem(), '30 sec');
      expect(find.byKey(const Key('family_yes_msg')), findsNothing); // new code, old answer dropped
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('QA_family_noMatch_showsHangUpWarning_inEveryLanguage', (t) async {
      FakeChannel('scamshield/family', (c) async => switch (c.method) {
            'family.status' => {'paired': true},
            'family.code' => {'code': '123456', 'remainingSec': 20},
            _ => null,
          }).install();
      await show(t, themes['dark']!(), const FamilyScreen(initialLang: 'en'), scale: 1.0, settle: false);
      await t.pump(const Duration(milliseconds: 10));
      for (final (lang, snippet) in [('en', 'Hang up'), ('hi', 'फ़ोन काट दें'), ('hne', 'फ़ोन काट देव')]) {
        await tapVisible(t, find.byKey(Key('lang_$lang')));
        await tapVisible(t, find.byKey(const Key('family_no')));
        await reveal(t, find.byKey(const Key('family_no_warning')));
        expect(find.descendant(of: find.byKey(const Key('family_no_warning')), matching: find.textContaining(snippet)), findsOneWidget, reason: lang);
      }
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('QA_family_nativeCodeFailure_showsErrorAndUnpairEscape', (t) async {
      FakeChannel('scamshield/family', (c) async {
        if (c.method == 'family.status') return {'paired': true};
        if (c.method == 'family.code') throw PlatformException(code: 'X');
        return null;
      }).install();
      await show(t, themes['light']!(), const FamilyScreen(initialLang: 'en'), scale: 1.0, settle: false);
      await t.pump(const Duration(milliseconds: 10));
      expect(find.text('Could not get the code. Try again.'), findsOneWidget);
      expect(find.byKey(const Key('family_code')), findsNothing);
      await tapVisible(t, find.byKey(const Key('family_unpair')));
      await tapVisible(t, find.byKey(const Key('family_unpair_confirm')));
      await t.pumpAndSettle();
      await reveal(t, find.byKey(const Key('family_show')));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('QA_family_enterSecret_rejectsNonBase32_doesNotCallNative', (t) async {
      final fam = FakeChannel('scamshield/family', (c) async => c.method == 'family.status' ? {'paired': false} : null)..install();
      await show(t, themes['light']!(), const FamilyScreen(initialLang: 'en'), scale: 1.0);
      await tapVisible(t, find.byKey(const Key('family_enter')));
      await t.pumpAndSettle();
      for (final bad in ['', 'ABCD', 'ABCDEFGHIJKLMNO1', 'ABCDEFGHIJKLMNO!']) {
        await t.enterText(find.byKey(const Key('family_field')), bad);
        await tapVisible(t, find.byKey(const Key('family_save')));
        expect(find.textContaining('Code is not valid'), findsOneWidget, reason: '"$bad"');
      }
      expect(fam.named('family.setSecret'), isEmpty);
    });
  });

  group('live feed', () {
    testWidgets('QA_liveFeed_callRisk_preliminaryVerdictDoesNotMoveGauge_callStartResets', (t) async {
      final emit = fakeEvents();
      await show(t, themes['light']!(), const LiveFeedScreen(), scale: 1.0);
      expect(find.text('अभी कोई कॉल नहीं'), findsOneWidget);
      emit({'type': 'call', 'active': true});
      emit({..._v('SCAM'), 'type': 'verdict', 'callRisk': 0.8, 'callLevel': 'SCAM'});
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('कॉल चल रही है'), 200); // verdict card now leads; status card sits below it
      expect(find.text('कॉल चल रही है'), findsOneWidget);
      expect(find.text('धोखाधड़ी हो सकती है · 80%'), findsOneWidget);
      emit({..._v('SAFE'), 'type': 'verdict', 'preliminary': true, 'callRisk': 0.0, 'callLevel': 'SAFE'});
      await t.pumpAndSettle();
      expect(find.text('धोखाधड़ी हो सकती है · 80%'), findsOneWidget);
      emit({'type': 'call', 'active': false});
      emit({'type': 'call', 'active': true}); // new call resets the gauge
      await t.pumpAndSettle();
      expect(find.text('सामान्य बातचीत · 0%'), findsOneWidget);
    });

    testWidgets('QA_liveFeed_scamVerdict_showsAdviceAnd1930_tappingNeverPlacesCall', (t) async {
      final emit = fakeEvents();
      final api = FakeChannel('scamshield/api', (c) async => null)..install();
      await show(t, themes['light']!(), const LiveFeedScreen(), scale: 1.0);
      expect(find.text('1930 पर कॉल करें'), findsNothing); // nothing before a verdict
      emit({..._v('SCAM'), 'type': 'verdict', 'callRisk': 0.9, 'callLevel': 'SCAM'});
      await t.pumpAndSettle();
      await reveal(t, find.text('1930 पर कॉल करें'));
      expect(find.text('पैसे न भेजें, कॉल काट दें'), findsOneWidget);
      await t.tap(find.text('1930 पर कॉल करें'), warnIfMissed: false);
      await t.pump();
      expect(api.calls, isEmpty); // 1930 is informational: no dial/call method is ever invoked
      emit({..._v('SAFE'), 'type': 'verdict', 'callRisk': 0.0, 'callLevel': 'SAFE'});
      await t.pumpAndSettle();
      expect(find.text('1930 पर कॉल करें'), findsNothing); // safe verdict: no helpline nag
    });

    testWidgets('QA_liveFeed_emptyState_hasCaptionSettingsAction', (t) async {
      fakeEvents();
      final api = FakeChannel('scamshield/api', (c) async => null)..install();
      await show(t, themes['dark']!(), const LiveFeedScreen(), scale: 1.0);
      expect(find.text('अभी कोई कॉल नहीं जाँची गई'), findsOneWidget);
      await tapVisible(t, find.text('लाइव कैप्शन चालू करें'));
      expect(api.named('openCaptionSettings'), hasLength(1));
    });

    testWidgets('QA_liveFeed_hindiCaptionAndStatement_render_noCrash', (t) async {
      final emit = fakeEvents();
      await show(t, themes['dark']!(), const LiveFeedScreen(), scale: 1.0);
      emit({'type': 'caption', 'text': 'आपका खाता बंद हो जाएगा', 'via': 'a11y'});
      emit({'type': 'statement', 'text': 'ओटीपी बताइए'});
      emit({'type': 'unknown_future_event'});
      await t.pumpAndSettle();
      expect(find.textContaining('आपका खाता बंद हो जाएगा  [a11y]'), findsOneWidget);
      expect(find.text('ओटीपी बताइए'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
