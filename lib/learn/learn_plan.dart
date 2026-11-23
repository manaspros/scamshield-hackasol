import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../lessons/lesson_model.dart';
import '../lessons/prefs_store.dart';

/// Answers seen / right for one lesson topic, across every quiz the user took.
@immutable
class TopicStat {
  const TopicStat({this.seen = 0, this.correct = 0});
  final int seen, correct;
  double get accuracy => seen == 0 ? 0 : correct / seen;

  Map<String, int> toJson() => {'seen': seen, 'correct': correct};
  factory TopicStat.fromJson(Map<String, Object?> m) =>
      TopicStat(seen: (m['seen'] as num?)?.toInt() ?? 0, correct: (m['correct'] as num?)?.toInt() ?? 0);
}

/// One flashcard: question-style front, answer-style back. [ai] = written by the model for this user.
@immutable
class StudyCard {
  const StudyCard({required this.front, required this.back, required this.topic, this.ai = false, this.known = false});
  final String front, back, topic;
  final bool ai, known;

  StudyCard withKnown(bool k) => StudyCard(front: front, back: back, topic: topic, ai: ai, known: k);

  Map<String, Object?> toJson() => {'front': front, 'back': back, 'topic': topic, 'ai': ai, 'known': known};
  factory StudyCard.fromJson(Map<String, Object?> m) => StudyCard(
        front: '${m['front'] ?? ''}',
        back: '${m['back'] ?? ''}',
        topic: '${m['topic'] ?? ''}',
        ai: m['ai'] == true,
        known: m['known'] == true,
      );
}

/// Accuracy under this is a topic to practise.
const kWeakBelow = 0.67;

/// The user's personal learning plan (pref `learn_v2`): per-topic stats, weak topics, flashcard deck, a plan line.
@immutable
class LearnPlan {
  const LearnPlan({this.stats = const {}, this.weak = const [], this.deck = const [], this.note, this.newCards = 0});
  final Map<String, TopicStat> stats;
  final List<String> weak;
  final List<StudyCard> deck;

  /// One line from the AI (or a template) on what to practise this week.
  final String? note;

  /// Cards added by the last quiz review (the "4 new" badge).
  final int newCards;

  static const empty = LearnPlan();

  /// Adds one quiz's answers for [topic] (true = right).
  LearnPlan withAnswers(String topic, List<bool> right) {
    final s = stats[topic] ?? const TopicStat();
    final next = Map.of(stats)
      ..[topic] = TopicStat(seen: s.seen + right.length, correct: s.correct + right.where((r) => r).length);
    return LearnPlan(stats: next, weak: weakTopics(next), deck: deck, note: note, newCards: newCards);
  }

  LearnPlan copyWith({List<String>? weak, List<StudyCard>? deck, String? note, int? newCards}) => LearnPlan(
        stats: stats,
        weak: weak ?? this.weak,
        deck: deck ?? this.deck,
        note: note ?? this.note,
        newCards: newCards ?? this.newCards,
      );

  Map<String, Object?> toJson() => {
        'stats': stats.map((k, v) => MapEntry(k, v.toJson())),
        'weak': weak,
        'deck': [for (final c in deck) c.toJson()],
        if (note != null) 'note': note,
        'newCards': newCards,
      };

  factory LearnPlan.fromJson(Map<String, Object?> m) => LearnPlan(
        stats: ((m['stats'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', TopicStat.fromJson((v as Map).cast<String, Object?>()))),
        weak: [for (final w in (m['weak'] as List?) ?? const []) '$w'],
        deck: [for (final c in (m['deck'] as List?) ?? const []) StudyCard.fromJson((c as Map).cast<String, Object?>())],
        note: m['note'] as String?,
        newCards: (m['newCards'] as num?)?.toInt() ?? 0,
      );
}

/// Topics answered at least once with accuracy under [kWeakBelow], weakest first.
List<String> weakTopics(Map<String, TopicStat> stats) {
  final w = stats.entries.where((e) => e.value.seen > 0 && e.value.accuracy < kWeakBelow).toList()
    ..sort((a, b) => a.value.accuracy.compareTo(b.value.accuracy));
  return [for (final e in w) e.key];
}

/// Without a model: the lesson's own cards for each weak topic become flashcards.
List<StudyCard> fallbackCards(List<Lesson> lessons, List<String> topics) => [
      for (final t in topics)
        for (final l in lessons.where((l) => l.id == t))
          for (final c in l.cards) StudyCard(front: c.title, back: c.body, topic: l.id),
    ];

/// Every lesson card, for the deck before any quiz has been taken.
List<StudyCard> allLessonCards(List<Lesson> lessons) => [
      for (final l in lessons)
        for (final c in l.cards) StudyCard(front: c.title, back: c.body, topic: l.id),
    ];

/// New cards first, duplicates (same front, any case) dropped, at most [cap] kept.
List<StudyCard> mergeDeck(List<StudyCard> existing, List<StudyCard> add, {int cap = 30}) {
  final seen = <String>{};
  final out = <StudyCard>[];
  for (final c in [...add, ...existing]) {
    final k = c.front.trim().toLowerCase();
    if (k.isEmpty || !seen.add(k)) continue;
    out.add(c);
    if (out.length == cap) break;
  }
  return out;
}

/// Loads and saves the plan; [plan] notifies Learn, the result screen and flashcards.
class LearnStore {
  LearnStore._();
  static const key = 'learn_v2';
  static var _prefs = PrefsStrings();
  static final ValueNotifier<LearnPlan> plan = ValueNotifier(LearnPlan.empty);
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _prefs.get(key);
      if (raw != null) plan.value = LearnPlan.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } on FormatException {
      plan.value = LearnPlan.empty;
    } on TypeError {
      plan.value = LearnPlan.empty;
    }
  }

  static Future<void> save(LearnPlan p) async {
    plan.value = p;
    await _prefs.set(key, jsonEncode(p.toJson()));
  }

  @visibleForTesting
  static void debugReset([LearnPlan p = LearnPlan.empty]) {
    _prefs = PrefsStrings();
    _loaded = true;
    plan.value = p;
  }
}
