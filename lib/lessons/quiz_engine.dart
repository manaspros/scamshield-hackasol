import 'lesson_model.dart';

/// Persists the best attempt percentage (0-100) per lesson id.
abstract class QuizStore {
  Future<Map<String, int>> loadBest();
  Future<void> saveBest(Map<String, int> best);
}

class InMemoryQuizStore implements QuizStore {
  Map<String, int> _best = {};

  @override
  Future<Map<String, int>> loadBest() async => Map.of(_best);

  @override
  Future<void> saveBest(Map<String, int> best) async => _best = Map.of(best);
}

class QuizResult {
  final String topicId;
  final int correct;
  final int total;

  /// Rounded integer 0-100.
  final int percent;

  const QuizResult(this.topicId, this.correct, this.total, this.percent);
}

class QuizEngine {
  final List<Lesson> lessons;
  final QuizStore _store;
  final Map<String, int> _best = {};

  QuizEngine(this.lessons, this._store);

  /// Restores saved bests; call once before use. Unknown ids are dropped, values clamped.
  Future<void> load() async {
    final ids = lessons.map((l) => l.id).toSet();
    _best
      ..clear()
      ..addEntries((await _store.loadBest())
          .entries
          .where((e) => ids.contains(e.key))
          .map((e) => MapEntry(e.key, e.value.clamp(0, 100))));
  }

  /// Pure grading. `answers[i]` is the chosen option index for question i;
  /// null, out-of-range or missing answers count as wrong.
  QuizResult grade(String topicId, List<int?> answers) {
    final questions = lessons.firstWhere((l) => l.id == topicId).questions;
    var correct = 0;
    for (var i = 0; i < questions.length; i++) {
      if (i < answers.length && answers[i] == questions[i].correctIndex) correct++;
    }
    final total = questions.length;
    final percent = total == 0 ? 0 : (correct * 100 / total).round();
    return QuizResult(topicId, correct, total, percent);
  }

  /// Grades, keeps the best percent for the topic, persists, returns this attempt.
  Future<QuizResult> record(String topicId, List<int?> answers) async {
    final result = grade(topicId, answers);
    if (result.percent > (_best[topicId] ?? 0)) {
      _best[topicId] = result.percent;
      await _store.saveBest(Map.of(_best));
    }
    return result;
  }

  int bestFor(String topicId) => _best[topicId] ?? 0;

  /// Digital Financial Literacy Score: mean best percent over all lessons, 0-100.
  int get score => lessons.isEmpty
      ? 0
      : (lessons.fold<int>(0, (sum, l) => sum + bestFor(l.id)) / lessons.length)
          .round();
}
