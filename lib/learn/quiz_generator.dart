import 'dart:convert';
import 'dart:math';

import '../api/llm_api.dart';
import '../lessons/lesson_model.dart';
import '../profile/user_profile.dart';
import 'learn_plan.dart';

/// The first balanced `{...}` in [raw] decoded as a JSON object; tolerates ``` fences and chatter around it.
Map<String, Object?>? extractJson(String? raw) {
  if (raw == null) return null;
  final start = raw.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var inStr = false;
  var esc = false;
  for (var i = start; i < raw.length; i++) {
    final ch = raw[i];
    if (inStr) {
      if (esc) {
        esc = false;
      } else if (ch == r'\') {
        esc = true;
      } else if (ch == '"') {
        inStr = false;
      }
      continue;
    }
    if (ch == '"') {
      inStr = true;
    } else if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) {
        try {
          final v = jsonDecode(raw.substring(start, i + 1));
          return v is Map ? v.cast<String, Object?>() : null;
        } on FormatException {
          return null;
        }
      }
    }
  }
  return null;
}

String _s(Object? v) => v is String ? v.trim() : '';

/// A model answer turned into a checked question with its options shuffled; null when anything is off
/// (not 4 distinct non-empty options, answer out of range, empty question or explanation).
QuizQuestion? parseQuestion(String? raw, {Random? rng}) {
  final m = extractJson(raw);
  if (m == null) return null;
  final q = _s(m['q'] ?? m['question']);
  final explain = _s(m['explain'] ?? m['explanation']);
  final opts = m['options'];
  final ans = m['answer'] ?? m['correctIndex'];
  if (q.isEmpty || explain.isEmpty || opts is! List || opts.length != 4) return null;
  final options = [for (final o in opts) _s(o)];
  if (options.any((o) => o.isEmpty) || options.map((o) => o.toLowerCase()).toSet().length != 4) return null;
  final a = ans is num ? ans.toInt() : int.tryParse('$ans');
  if (a == null || a < 0 || a > 3) return null;
  final order = [0, 1, 2, 3]..shuffle(rng ?? Random());
  return QuizQuestion(
    question: q,
    options: [for (final i in order) options[i]],
    correctIndex: order.indexOf(a),
    explanation: explain,
  );
}

String languageRule(String lang) => switch (lang) {
      'en' => 'Write everything in simple English.',
      'hne' => 'Write everything in simple Chhattisgarhi using Devanagari script (use simple Hindi words when unsure).',
      _ => 'Write everything in simple Hindi using Devanagari script.',
    };

/// Prompt for one multiple-choice question about [lesson], grounded in its cards and tailored to the user.
String questionPrompt({
  required Lesson lesson,
  required UserProfile profile,
  required String lang,
  List<String> weak = const [],
  List<String> avoid = const [],
  DateTime? now,
}) {
  final facts = [for (final c in lesson.cards) '- ${c.title}: ${c.body}'].join('\n');
  final avoidLine = avoid.isEmpty ? '' : '\nDo NOT repeat these questions:\n${avoid.map((a) => '- $a').join('\n')}\n';
  final weakLine = weak.contains(lesson.id) ? '\nThe learner got this topic wrong before, so test the most common trap.\n' : '';
  return '''You write quiz questions that teach people in India to avoid phone and payment scams.
Topic: ${lesson.title}
Facts to use:
$facts
Learner: ${profile.promptContext(now)}.
Make ONE realistic situation this learner could really face (a call, SMS, WhatsApp message or QR code), then ask what they should do.$weakLine$avoidLine
Give 4 short options. Exactly one is safe and correct. The wrong ones must sound tempting.
${languageRule(lang)} Keep the question under 40 words and each option under 12 words.
Answer with ONLY one line of JSON:
{"q":"question","options":["a","b","c","d"],"answer":0,"explain":"one sentence why"}''';
}

/// What the model said after a quiz: weak topics, new flashcards and a one-line plan.
class Review {
  const Review({required this.weak, required this.cards, this.plan});
  final List<String> weak;
  final List<StudyCard> cards;
  final String? plan;
}

/// One wrong answer, for the review prompt.
class Miss {
  const Miss({required this.question, required this.picked, required this.right});
  final String question, picked, right;
}

String reviewPrompt({
  required String topicId,
  required String topicTitle,
  required List<Miss> misses,
  required int correct,
  required int total,
  required UserProfile profile,
  required String lang,
  DateTime? now,
}) {
  final wrong = misses.isEmpty
      ? 'None.'
      : misses.map((m) => '- Q: ${m.question}\n  They chose: ${m.picked}\n  Right answer: ${m.right}').join('\n');
  return '''You are a friendly safety coach helping someone in India avoid scams.
Learner: ${profile.promptContext(now)}.
They took a quiz on "$topicTitle" (topic id $topicId) and got $correct of $total right.
Questions they got wrong:
$wrong
Write 2 to 4 flashcards that fix exactly these mistakes, using situations that fit this learner's age and life.
Each card: "front" is a short situation or question (max 25 words), "back" is the safe action and why (max 35 words).
Also write "plan": one encouraging sentence (max 30 words) on what to practise this week.
${languageRule(lang)}
Answer with ONLY one line of JSON:
{"weak":["$topicId"],"cards":[{"front":"...","back":"..."}],"plan":"..."}''';
}

Review? parseReview(String? raw, {required String topicId, required Set<String> validTopics}) {
  final m = extractJson(raw);
  if (m == null) return null;
  final cards = <StudyCard>[];
  for (final c in (m['cards'] is List ? m['cards'] as List : const [])) {
    if (c is! Map) continue;
    final f = _s(c['front']), b = _s(c['back']);
    final t = _s(c['topic']);
    if (f.isEmpty || b.isEmpty) continue;
    cards.add(StudyCard(front: f, back: b, topic: validTopics.contains(t) ? t : topicId, ai: true));
    if (cards.length == 4) break;
  }
  if (cards.isEmpty) return null;
  final weak = [for (final w in (m['weak'] is List ? m['weak'] as List : const [])) if (validTopics.contains('$w')) '$w'];
  final plan = _s(m['plan']);
  return Review(weak: weak, cards: cards, plan: plan.isEmpty ? null : plan);
}

/// Thin wrapper that asks the model and validates what comes back (one retry per question).
class QuizGenerator {
  QuizGenerator(this.llm, {Random? rng}) : _rng = rng ?? Random();
  final LlmClient llm;
  final Random _rng;

  Future<QuizQuestion?> question({
    required Lesson lesson,
    required UserProfile profile,
    required String lang,
    List<String> weak = const [],
    List<String> avoid = const [],
  }) async {
    final p = questionPrompt(lesson: lesson, profile: profile, lang: lang, weak: weak, avoid: avoid);
    for (var attempt = 0; attempt < 2; attempt++) {
      final q = parseQuestion(await llm.generate(p, temperature: attempt == 0 ? 0.8 : 0.5), rng: _rng);
      if (q != null && !avoid.any((a) => a.toLowerCase() == q.question.toLowerCase())) return q;
    }
    return null;
  }

  Future<Review?> review({
    required Lesson lesson,
    required List<Miss> misses,
    required int correct,
    required int total,
    required UserProfile profile,
    required String lang,
    required Set<String> validTopics,
  }) async {
    final p = reviewPrompt(
      topicId: lesson.id,
      topicTitle: lesson.title,
      misses: misses,
      correct: correct,
      total: total,
      profile: profile,
      lang: lang,
    );
    return parseReview(await llm.generate(p, temperature: 0.6), topicId: lesson.id, validTopics: validTopics);
  }
}
