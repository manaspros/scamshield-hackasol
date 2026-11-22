import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/lessons/lesson_model.dart';
import 'package:scamshield/lessons/quiz_engine.dart';

// Every question's correct option is index 0.
Lesson _lesson(String id, {int questions = 3}) => Lesson(
      id: id,
      title: id,
      cards: const [],
      questions: List.generate(
        questions,
        (i) => QuizQuestion(
          question: 'q$i',
          options: const ['right', 'wrong', 'wrong2'],
          correctIndex: 0,
          explanation: '',
        ),
      ),
    );

QuizEngine _engine([QuizStore? store]) => QuizEngine(
      [_lesson('a'), _lesson('b'), _lesson('c'), _lesson('d')],
      store ?? InMemoryQuizStore(),
    );

void main() {
  test('T3_4_scoreBounds', () async {
    final engine = _engine();
    expect(engine.score, 0); // untouched topics count 0
    for (final id in ['a', 'b', 'c', 'd']) {
      await engine.record(id, [0, 0, 0]);
    }
    expect(engine.score, 100);
    // junk answers: null, out of range, missing
    expect(engine.grade('a', [null, 99, -1]).percent, 0);
    expect(engine.grade('a', []).percent, 0);
    expect(engine.grade('a', [0, 0, 0, 0, 0]).percent, 100);
    expect(QuizEngine([], InMemoryQuizStore()).score, 0);
  });

  test('T3_4_retryKeepsBest', () async {
    final store = InMemoryQuizStore();
    final engine = _engine(store);
    await engine.record('a', [0, 0, 1]); // 67
    expect(engine.bestFor('a'), 67);
    final worse = await engine.record('a', [1, 1, 1]);
    expect(worse.percent, 0);
    expect(engine.bestFor('a'), 67);
    await engine.record('a', [0, 0, 0]);
    expect(engine.bestFor('a'), 100);
    // persisted and restored; foreign ids dropped
    await store.saveBest({'a': 100, 'zzz': 50});
    final reloaded = _engine(store);
    await reloaded.load();
    expect(reloaded.bestFor('a'), 100);
    expect(reloaded.score, 25);
  });

  test('T3_4_perTopic', () async {
    final engine = _engine();
    await engine.record('a', [0, 1, 1]); // 33
    await engine.record('b', [0, 0, 1]); // 67
    expect(engine.bestFor('a'), 33);
    expect(engine.bestFor('b'), 67);
    expect(engine.bestFor('c'), 0);
    expect(engine.score, 25); // (33+67+0+0)/4
    final result = engine.grade('b', [0, 0, 1]);
    expect([result.correct, result.total], [2, 3]);
    expect(() => engine.grade('nope', []), throwsStateError);
  });
}
