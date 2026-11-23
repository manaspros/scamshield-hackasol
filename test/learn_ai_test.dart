import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/api/llm_api.dart';
import 'package:scamshield/api/model_api.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/learn/learn_plan.dart';
import 'package:scamshield/learn/quiz_generator.dart';
import 'package:scamshield/learn/quiz_session.dart';
import 'package:scamshield/lessons/lesson_model.dart';
import 'package:scamshield/lessons/quiz_engine.dart';
import 'package:scamshield/profile/user_profile.dart';
import 'package:scamshield/screens/flashcards_screen.dart';
import 'package:scamshield/screens/quiz_screen.dart';
import 'package:scamshield/theme/app_theme.dart';

List<Lesson> _en() => loadLessonsFromJson(File('assets/lessons/en.json').readAsStringSync());

/// Scripted model: answers come from [answers] in order; [ready] is fixed.
class _FakeLlm implements LlmClient {
  _FakeLlm(this.answers);
  final List<String?> answers;
  final prompts = <String>[];

  @override
  Future<bool> ready() async => true;

  @override
  Future<String?> generate(String prompt, {double temperature = 0.8}) async {
    prompts.add(prompt);
    return answers.isEmpty ? null : answers.removeAt(0);
  }
}

String _q(String q, {int answer = 2}) => jsonEncode({
      'q': q,
      'options': ['Pay the fee', 'Share Aadhaar', 'Hang up and call 1930', 'Send the letter'],
      'answer': answer,
      'explain': 'Police never arrest on a video call.',
    });

void main() {
  group('extractJson / parseQuestion', () {
    test('finds the first JSON object inside chatter and code fences', () {
      expect(extractJson('Sure! ```json\n{"a": {"b": "}"}}\n``` hope it helps'), {
        'a': {'b': '}'}
      });
      expect(extractJson('no json here'), isNull);
      expect(extractJson('{broken'), isNull);
    });

    test('accepts a valid question and shuffles options keeping the right answer', () {
      final q = parseQuestion('Here: ${_q('A caller says CBI. What do you do?')}', rng: Random(1))!;
      expect(q.question, 'A caller says CBI. What do you do?');
      expect(q.options, hasLength(4));
      expect(q.options[q.correctIndex], 'Hang up and call 1930');
      expect(q.explanation, isNotEmpty);
    });

    test('rejects bad shapes', () {
      expect(parseQuestion('{"q":"x","options":["a","b","c"],"answer":0,"explain":"e"}'), isNull); // 3 options
      expect(parseQuestion('{"q":"x","options":["a","a","b","c"],"answer":0,"explain":"e"}'), isNull); // duplicate
      expect(parseQuestion('{"q":"x","options":["a","b","c","d"],"answer":4,"explain":"e"}'), isNull); // out of range
      expect(parseQuestion('{"q":"","options":["a","b","c","d"],"answer":0,"explain":"e"}'), isNull); // empty question
      expect(parseQuestion('{"q":"x","options":["a","b","c","d"],"answer":"1","explain":""}'), isNull); // no explanation
      expect(parseQuestion(null), isNull);
    });

    String qj(List<String> options, {String q = 'A caller says your account is blocked. What do you do?', String e = 'Banks never call for this.'}) =>
        jsonEncode({'q': q, 'options': options, 'answer': 1, 'explain': e});

    test('rejects dead questions: letter / "Option 2" placeholders, templates, copied example', () {
      expect(parseQuestion(qj(['a', 'b', 'c', 'd'])), isNull);
      expect(parseQuestion(qj(['A)', 'B)', 'C)', 'D)'])), isNull);
      expect(parseQuestion(qj(['Option 1', 'Option 2', 'Option 3', 'Option 4'])), isNull);
      expect(parseQuestion(qj(['<safe action>', '<wrong 1>', '<wrong 2>', '<wrong 3>'])), isNull);
      expect(parseQuestion(qj(['Hang up', 'Call 1930', '...', 'Pay the fee'])), isNull);
      expect(parseQuestion(qj(['Hang up', 'Call 1930', 'Pay the fee', 'Share OTP'], q: 'question')), isNull);
      expect(parseQuestion(qj(['Hang up', 'Call 1930', 'Pay the fee', 'Share OTP'], e: 'one sentence why')), isNull);
      expect(parseQuestion(qj(exampleOptions, q: exampleQuestion)), isNull); // the prompt's example copied back
      expect(parseQuestion(qj(['Hang up', 'Call 1930', 'Pay the fee', 'Share OTP'])), isNotNull);
      expect(isPlaceholder('b'), isTrue);
      expect(isPlaceholder('विकल्प 2'), isTrue);
      expect(isPlaceholder('Hang up'), isFalse);
    });

    test('rejects a question in the wrong script for the app language', () {
      final en = qj(['Hang up', 'Call 1930', 'Pay the fee', 'Share OTP']);
      final hi = jsonEncode({
        'q': 'कॉल करने वाला कहता है कि खाता बंद होगा। आप क्या करेंगे?',
        'options': ['फ़ोन काट दें', '1930 पर कॉल करें', 'फ़ीस भर दें', 'OTP बता दें'],
        'answer': 1,
        'explain': 'बैंक ऐसे कॉल नहीं करते।',
      });
      expect(parseQuestion(en, lang: 'en'), isNotNull);
      expect(parseQuestion(en, lang: 'hi'), isNull);
      expect(parseQuestion(hi, lang: 'hi'), isNotNull);
      expect(parseQuestion(hi, lang: 'en'), isNull);
    });

    test('the prompt no longer shows a copyable "a, b, c, d" template', () {
      final l = _en().first;
      final p = questionPrompt(lesson: l, profile: UserProfile.empty, lang: 'en');
      expect(p, isNot(contains('["a","b","c","d"]')));
      expect(p, contains('never just a letter'));
    });

    test('three tries per AI question before falling back', () async {
      final l = _en().first;
      final llm = _FakeLlm(['{"q":"x","options":["a","b","c","d"],"answer":0,"explain":"e"}', 'junk', 'junk']);
      final q = await QuizGenerator(llm).question(lesson: l, profile: UserProfile.empty, lang: 'en');
      expect(q, isNull);
      expect(llm.prompts, hasLength(3));
    });

    test('question prompt is grounded in the lesson, tailored to the learner, never leaks name or phone', () {
      final l = _en().firstWhere((l) => l.id == 'digital_arrest');
      final p = questionPrompt(
        lesson: l,
        profile: UserProfile(name: 'Ramesh Sahu', phone: '9876543210', dob: DateTime(1964, 3, 14), gender: Gender.male, district: 'Raipur'),
        lang: 'hi',
        weak: const ['digital_arrest'],
        avoid: const ['Old question?'],
        now: DateTime(2026, 11, 23),
      );
      expect(p, contains(l.cards.first.title));
      expect(p, contains('age 62 (senior citizen)'));
      expect(p, contains('Raipur'));
      expect(p, contains('Devanagari'));
      expect(p, contains('Old question?'));
      expect(p, contains('got this topic wrong before'));
      expect(p, isNot(contains('Ramesh')));
      expect(p, isNot(contains('9876543210')));
    });

    test('review: keeps up to 4 valid cards, maps unknown topics to the quiz topic', () {
      final r = parseReview(
        '{"weak":["digital_arrest","bogus"],"cards":[{"front":"A QR to receive money","back":"Scanning a QR only sends money","topic":"qr"},{"front":"A caller says CBI","back":"Hang up and call 1930","topic":"nope"},{"front":"...","back":"Placeholder card"},{"front":"","back":"x"}],"plan":"Practise daily."}',
        topicId: 'digital_arrest',
        validTopics: {'digital_arrest', 'qr'},
      )!;
      expect(r.weak, ['digital_arrest']);
      expect([for (final c in r.cards) c.topic], ['qr', 'digital_arrest']);
      expect(r.cards.every((c) => c.ai), isTrue);
      expect(r.plan, 'Practise daily.');
      expect(parseReview('{"cards":[]}', topicId: 'x', validTopics: {'x'}), isNull);
    });
  });

  group('learn plan', () {
    test('weak topics are those under 67%, weakest first', () {
      var p = LearnPlan.empty.withAnswers('otp', [true, true, true]);
      p = p.withAnswers('qr', [true, false, false]);
      p = p.withAnswers('kyc', [false, false, false]);
      expect(p.weak, ['kyc', 'qr']);
      p = p.withAnswers('qr', [true, true, true, true]); // 5/7 = 71%
      expect(p.weak, ['kyc']);
    });

    test('mergeDeck: new first, case-insensitive dedupe, capped', () {
      const a = StudyCard(front: 'Same', back: '1', topic: 't');
      const b = StudyCard(front: 'same ', back: '2', topic: 't');
      const c = StudyCard(front: 'Other', back: '3', topic: 't');
      final m = mergeDeck([a, c], [b]);
      expect([for (final x in m) x.back], ['2', '3']);
      expect(mergeDeck(List.generate(40, (i) => StudyCard(front: 'f$i', back: '', topic: 't')), const []), hasLength(30));
    });

    test('json round trip', () {
      final p = LearnPlan.empty.withAnswers('otp', [true, false]).copyWith(
            deck: const [StudyCard(front: 'F', back: 'B', topic: 'otp', ai: true)],
            note: 'n',
            newCards: 1,
          );
      final back = LearnPlan.fromJson((jsonDecode(jsonEncode(p.toJson())) as Map).cast<String, Object?>());
      expect(back.stats['otp']!.seen, 2);
      expect(back.weak, ['otp']);
      expect(back.deck.single.ai, isTrue);
      expect(back.note, 'n');
      expect(back.newCards, 1);
    });

    test('fallback cards are the lesson cards of the weak topics', () {
      final cards = fallbackCards(_en(), ['qr']);
      expect(cards, isNotEmpty);
      expect(cards.every((c) => c.topic == 'qr' && !c.ai), isTrue);
    });
  });

  group('user profile', () {
    test('age, first name, initials, missing fields, completeness', () {
      final p = UserProfile(name: ' Ramesh  Kumar Sahu ', dob: DateTime(1964, 11, 24));
      expect(p.ageOn(DateTime(2026, 11, 23)), 61); // birthday tomorrow
      expect(p.ageOn(DateTime(2026, 11, 24)), 62);
      expect(p.firstName, 'Ramesh');
      expect(p.initials, 'RS');
      expect(p.missingForQuiz, ['gender']);
      expect(p.completeness, closeTo(2 / 6, 1e-9));
      expect(UserProfile.empty.missingForQuiz, ['name', 'dob', 'gender']);
      expect(UserProfile.empty.promptContext(), 'an adult smartphone user in India');
    });

    test('json round trip keeps every field; district comes from its own key', () {
      final p = UserProfile(
          name: 'A', dob: DateTime(1990, 1, 2), gender: Gender.female, phone: '1', occupation: 'teacher', techComfort: TechComfort.low);
      final back = UserProfile.fromJson((jsonDecode(jsonEncode(p.toJson())) as Map).cast<String, Object?>(), district: 'Durg');
      expect(back.name, 'A');
      expect(back.dob, DateTime(1990, 1, 2));
      expect(back.gender, Gender.female);
      expect(back.occupation, 'teacher');
      expect(back.techComfort, TechComfort.low);
      expect(back.district, 'Durg');
      expect(p.toJson().containsKey('district'), isFalse);
    });
  });

  group('model recommendation', () {
    const dev6 = DeviceInfo(totalRamMb: 5800, freeStorageMb: 20000);
    test('largest hosted model that fits; unhosted ones are never recommended', () {
      expect(recommendModelId(kFallbackCatalog, dev6), 'gemma3-1b-int4');
      expect(recommendModelId(kFallbackCatalog, const DeviceInfo(totalRamMb: 12000, freeStorageMb: 50000)), 'gemma3-1b-int4');
      expect(recommendModelId(kFallbackCatalog, const DeviceInfo(totalRamMb: 3500, freeStorageMb: 50000)), 'gemma3-270m');
      final hosted = [for (final m in kFallbackCatalog) ModelSpec(id: m.id, name: m.name, file: m.file, sizeMb: m.sizeMb, minRamMb: m.minRamMb, tier: m.tier, url: 'u')];
      expect(recommendModelId(hosted, const DeviceInfo(totalRamMb: 12000, freeStorageMb: 50000)), 'gemma3n-e2b');
      expect(recommendModelId(hosted, dev6), 'gemma3-1b-int4');
      expect(recommendModelId(hosted, const DeviceInfo(totalRamMb: 3500, freeStorageMb: 50000)), 'gemma3-270m');
    });

    test('blocks explain why', () {
      final e2b = kFallbackCatalog.last;
      final oneB = kFallbackCatalog[1];
      expect(blockFor(e2b, dev6), ModelBlock.notHosted);
      expect(blockFor(oneB, const DeviceInfo(totalRamMb: 3000, freeStorageMb: 9000)), ModelBlock.lowRam);
      expect(blockFor(oneB, const DeviceInfo(totalRamMb: 8000, freeStorageMb: 600)), ModelBlock.lowStorage);
      expect(blockFor(oneB, const DeviceInfo()), isNull); // unknown device: never block
      expect(const DeviceInfo(totalRamMb: 5734).ramLabel, '6 GB');
    });
  });

  group('quiz session', () {
    test('no model: the lesson\'s own three questions', () async {
      final l = _en().first;
      final s = QuizSession(lesson: l, llm: const NoLlm(), profile: UserProfile.empty, lang: 'en');
      await s.start();
      expect(s.ai, isFalse);
      expect(s.length, l.questions.length);
      expect((await s.at(1)).question, l.questions[1].question);
    });

    test('model: five AI questions; a bad answer falls back to a built-in one', () async {
      final l = _en().first;
      final llm = _FakeLlm([_q('Q1 a caller wants the OTP?'), 'garbage', 'still garbage', 'more garbage', _q('Q3 a caller wants the OTP?'), _q('Q4 a caller wants the OTP?'), _q('Q5 a caller wants the OTP?')]);
      final s = QuizSession(lesson: l, llm: llm, profile: UserProfile.empty, lang: 'en');
      await s.start();
      expect(s.length, 5);
      final qs = [for (var i = 0; i < 5; i++) await s.at(i)];
      expect(qs[0].question, 'Q1 a caller wants the OTP?');
      expect(s.aiMade(0), isTrue);
      expect(s.aiMade(1), isFalse);
      expect(qs[1].question, l.questions.first.question);
      expect(qs[2].question, 'Q3 a caller wants the OTP?');
      // later prompts list earlier questions so the model does not repeat them
      expect(llm.prompts.last, contains('Q1'));
    });

    test('use ready questions: stops the model and shrinks to the built-in set', () async {
      final l = _en().first;
      final s = QuizSession(lesson: l, llm: _FakeLlm([_q('Q1 a caller wants the OTP?')]), profile: UserProfile.empty, lang: 'en');
      await s.start();
      await s.at(0);
      final q = s.useReady(1);
      expect(q.question, l.questions.first.question);
      expect(s.length, l.questions.length);
    });
  });

  group('AI quiz screen', () {
    setUp(() => AppLanguage.debugSet('en'));

    testWidgets('AI questions show the chip; wrong answers produce new flashcards and a plan', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      ProfileStore.debugSet(UserProfile(name: 'Ramesh', dob: DateTime(1960), gender: Gender.male));
      final lessons = _en();
      final engine = QuizEngine(lessons, InMemoryQuizStore());
      await engine.load();
      final review = jsonEncode({
        'weak': ['otp'],
        'cards': [
          {'front': 'A caller asks for the OTP to stop a debit', 'back': 'Hang up. Banks never ask for an OTP.'},
          {'front': 'Your "grandson" needs an OTP', 'back': 'Call him back on his own number.'},
        ],
        'plan': 'Practise OTP calls for 5 minutes a day.',
      });
      final llm = _FakeLlm([for (var i = 0; i < 5; i++) _q('AI question ${i + 1}: what do you do?'), review]);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        builder: (c, w) => LangScope(notifier: AppLanguage.current, child: w!),
        home: QuizScreen(lesson: lessons.first, engine: engine, lang: 'en', llm: llm, startWithQuiz: true),
      ));
      await t.pumpAndSettle();
      expect(find.text('AI question 1: what do you do?'), findsOneWidget);
      expect(find.byKey(const Key('quiz_ai_chip')), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        // always pick a wrong option (the options are shuffled)
        final wrong = [0, 1, 2, 3].firstWhere((k) =>
            find.descendant(of: find.byKey(Key('option_$k')), matching: find.text('Hang up and call 1930')).evaluate().isEmpty);
        await t.tap(find.byKey(Key('option_$wrong')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('feedback')), findsOneWidget);
        await t.tap(find.byKey(const Key('quiz_next')));
        await t.pumpAndSettle();
      }
      expect(find.byKey(const Key('result_score')), findsOneWidget);
      final plan = LearnStore.plan.value;
      expect(plan.stats['otp']!.seen, 5);
      expect(plan.stats['otp']!.correct, 0);
      expect(plan.weak, contains('otp'));
      {
        expect(plan.deck.where((c) => c.ai), hasLength(2));
        expect(plan.note, 'Practise OTP calls for 5 minutes a day.');
        await t.scrollUntilVisible(find.byKey(const Key('result_practise')), 200);
        await t.tap(find.byKey(const Key('result_practise')));
        await t.pumpAndSettle();
        expect(find.byType(FlashcardsScreen), findsOneWidget);
        expect(find.text('A caller asks for the OTP to stop a debit'), findsOneWidget);
        await t.tap(find.byKey(const Key('fc_card')));
        await t.pumpAndSettle();
        expect(find.text('Hang up. Banks never ask for an OTP.'), findsOneWidget);
        await t.tap(find.byKey(const Key('fc_knew')));
        await t.pumpAndSettle();
        expect(LearnStore.plan.value.deck.first.known, isTrue);
        expect(LearnStore.plan.value.newCards, 0);
      }
      expect(t.takeException(), isNull);
    });
  });
}
