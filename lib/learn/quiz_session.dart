import 'dart:async';
import 'dart:math';

import '../api/llm_api.dart';
import '../lessons/lesson_model.dart';
import '../profile/user_profile.dart';
import 'quiz_generator.dart';

/// The questions of one quiz. With a model loaded, each one is written by the AI for this user
/// (the next is prepared while the current is answered); any that fails falls back to a built-in question.
class QuizSession {
  QuizSession({
    required this.lesson,
    required this.llm,
    required this.profile,
    required this.lang,
    this.weak = const [],
    this.aiLength = 5,
    QuizGenerator? generator,
  }) : _gen = generator ?? QuizGenerator(llm);

  final Lesson lesson;
  final LlmClient llm;
  final UserProfile profile;
  final String lang;
  final List<String> weak;
  final int aiLength;
  final QuizGenerator _gen;

  bool _ai = false;
  final _futures = <int, Future<QuizQuestion>>{};
  final _done = <int, QuizQuestion>{};
  final _aiMade = <int>{};
  final _usedStatic = <int>{};

  /// True once [start] found a ready model.
  bool get ai => _ai;

  int get length {
    if (!_ai) return lesson.questions.length;
    if (!_stopped) return aiLength;
    // After "use ready questions": what is already shown, padded up to the built-in set.
    return max(lesson.questions.length, _done.keys.fold<int>(0, (m, k) => max(m, k + 1)));
  }

  /// Whether question [i] was written by the AI (for the "Made by AI for you" chip).
  bool aiMade(int i) => _aiMade.contains(i);

  QuizQuestion? ready(int i) => _done[i];

  /// Checks the model once. Without one this is the classic built-in quiz.
  Future<void> start() async {
    final ready = await llm.ready();
    if (llm is LlmApi) LlmStatus.ready.value = ready;
    _ai = lesson.questions.isNotEmpty && ready;
    if (_ai) unawaited(at(0));
  }

  Future<QuizQuestion> at(int i) => _futures.putIfAbsent(i, () => _make(i));

  /// Starts preparing question [i] in the background, if it exists.
  void prefetch(int i) {
    if (i < length) unawaited(at(i));
  }

  /// Stop asking the model; question [i] (and any not ready yet) comes from the built-in set right away.
  QuizQuestion useReady(int i) {
    _stopped = true;
    return _done[i] ??= _fallback(i);
  }

  bool _stopped = false;

  Future<QuizQuestion> _make(int i) async {
    if (!_ai) return _done[i] = lesson.questions[i];
    if (_stopped) return _done[i] ??= _fallback(i);
    // Earlier questions first, so the "do not repeat" list is complete.
    final prev = [for (var k = 0; k < i; k++) await at(k)];
    final q = await _gen.question(
      lesson: lesson,
      profile: profile,
      lang: lang,
      weak: weak,
      avoid: [for (final p in prev) p.question],
    );
    if (_done[i] != null) return _done[i]!; // "use ready questions" was tapped meanwhile
    if (q != null && !_stopped) {
      _aiMade.add(i);
      return _done[i] = q;
    }
    return _done[i] = _fallback(i);
  }

  QuizQuestion _fallback(int i) {
    final qs = lesson.questions;
    final idx = [for (var k = 0; k < qs.length; k++) k].firstWhere((k) => !_usedStatic.contains(k), orElse: () => i % qs.length);
    _usedStatic.add(idx);
    return qs[idx];
  }
}
