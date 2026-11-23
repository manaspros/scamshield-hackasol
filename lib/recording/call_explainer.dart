import 'dart:convert';

import '../api/llm_api.dart';
import '../learn/quiz_generator.dart' show languageRule;
import '../models/verdict.dart';

/// One red flag the AI found: the exact words from the call and why they are dangerous.
class RedFlag {
  const RedFlag({required this.quote, required this.why, this.startMs});
  final String quote, why;

  /// Where the quote was said, when it could be matched to a transcript line.
  final int? startMs;
  Map<String, Object?> toJson() => {'quote': quote, 'why': why, if (startMs != null) 'startMs': startMs};
}

/// The AI's explanation of a whole call.
class CallExplanation {
  const CallExplanation({
    required this.verdict,
    required this.risk,
    required this.summary,
    this.steps = const [],
    this.flags = const [],
    this.todo = const [],
  });
  final RiskLabel verdict;

  /// 0..100.
  final int risk;
  final String summary;
  final List<String> steps, todo;
  final List<RedFlag> flags;

  Map<String, Object?> toJson() => {
        'verdict': verdict.name,
        'risk': risk,
        'summary': summary,
        'whatHappened': steps,
        'redFlags': [for (final f in flags) f.toJson()],
        'whatToDo': todo,
      };
}

/// One transcript line with its time, as heard.
class Line {
  const Line(this.startMs, this.text);
  final int startMs;
  final String text;
}

/// The model's whole budget is 2048 tokens (prompt + answer); Devanagari costs ~1 token per 2-3 characters.
const kMaxTranscriptChars = 1800;

/// What the AI reads: the whole call when it fits; otherwise its start plus every line the rules flagged.
String transcriptForPrompt(List<Line> lines, {Set<int> flagged = const {}}) {
  String clock(int ms) => '${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';
  final all = [for (final l in lines) '[${clock(l.startMs)}] ${l.text.trim()}'];
  final whole = all.join('\n');
  if (whole.length <= kMaxTranscriptChars) return whole;
  final keep = <int>{};
  var used = 0;
  for (var i = 0; i < all.length && used < kMaxTranscriptChars * 0.35; i++) {
    keep.add(i);
    used += all[i].length + 1;
  }
  for (final i in flagged) {
    if (i < all.length && used + all[i].length < kMaxTranscriptChars) {
      keep.add(i);
      used += all[i].length + 1;
    }
  }
  final out = <String>[];
  int? prev;
  for (final i in keep.toList()..sort()) {
    if (prev != null && i != prev + 1) out.add('[…]');
    out.add(all[i]);
    prev = i;
  }
  return out.join('\n');
}

String explainPrompt({required String transcript, required String lang, List<String> hints = const [], double? ruleRisk}) {
  final hintLine = hints.isEmpty ? '' : '\nA keyword filter noticed: ${hints.take(6).join(', ')}. Use it only as a hint.';
  return '''You help people in India understand if a phone call was a scam. Read the WHOLE call below together, then explain it to an ordinary person.
Call transcript (speech-to-text, may have small mistakes):
"""
$transcript
"""$hintLine
Decide: "scam" (they want money, OTP, PIN, app install, personal details, or threaten), "suspicious" (pressure or odd requests, not certain), or "safe" (normal call).
${languageRule(lang)}
Answer with ONLY one line of JSON with these keys:
"verdict": "scam" | "suspicious" | "safe",
"risk": number 0-100,
"summary": 2 short sentences: what the caller wanted and what the person must do,
"steps": up to 4 very short lines telling what happened in order,
"flags": up to 3 objects {"quote": exact words copied from the transcript, "why": one short reason},
"todo": up to 3 short actions.''';
}

/// Parses the model's answer; null when it is not usable. Tolerates code fences and text around the JSON.
CallExplanation? parseExplanation(String? raw, {List<Line> lines = const []}) {
  if (raw == null) return null;
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  Object? j;
  try {
    j = jsonDecode(raw.substring(start, end + 1));
  } on FormatException {
    return null;
  }
  if (j is! Map) return null;
  final verdict = switch ('${j['verdict']}'.toLowerCase().trim()) {
    'scam' => RiskLabel.scam,
    'suspicious' => RiskLabel.suspicious,
    'safe' => RiskLabel.safe,
    _ => null,
  };
  final summary = '${j['summary'] ?? ''}'.trim();
  if (verdict == null || summary.isEmpty) return null;
  final risk = ((j['risk'] as num?)?.round() ?? (verdict == RiskLabel.scam ? 90 : verdict == RiskLabel.suspicious ? 55 : 10)).clamp(0, 100);
  List<String> strs(Object? v, int max) =>
      [for (final e in (v is List ? v : const [])) if ('$e'.trim().isNotEmpty) '$e'.trim()].take(max).toList();
  int? whereSaid(String quote) {
    final q = quote.toLowerCase();
    if (q.length < 4) return null;
    for (final l in lines) {
      final t = l.text.toLowerCase();
      if (t.contains(q) || q.contains(t) && t.length > 8) return l.startMs;
    }
    final words = q.split(RegExp(r'\s+')).where((w) => w.length > 3).toSet();
    Line? best;
    var score = 1;
    for (final l in lines) {
      final s = l.text.toLowerCase().split(RegExp(r'\s+')).where(words.contains).length;
      if (s > score) {
        score = s;
        best = l;
      }
    }
    return best?.startMs;
  }

  final flags = <RedFlag>[
    for (final f in (j['flags'] is List ? j['flags'] as List : const []))
      if (f is Map && '${f['quote'] ?? ''}'.trim().isNotEmpty)
        RedFlag(quote: '${f['quote']}'.trim(), why: '${f['why'] ?? ''}'.trim(), startMs: whereSaid('${f['quote']}')),
  ].take(3).toList();
  return CallExplanation(
    verdict: verdict,
    risk: risk,
    summary: summary,
    steps: strs(j['steps'], 4),
    flags: flags,
    todo: strs(j['todo'], 3),
  );
}

/// Sends the whole transcript to the on-device model in one go. Null when no model is loaded or the answer is unusable;
/// the screen then shows the keyword report instead.
class CallExplainer {
  const CallExplainer({this.llm = const LlmApi()});
  final LlmClient llm;

  Future<CallExplanation?> explain({
    required List<Line> lines,
    required String lang,
    Set<int> flagged = const {},
    List<String> hints = const [],
    double? ruleRisk,
  }) async {
    if (lines.isEmpty || !await llm.ready()) return null;
    final prompt = explainPrompt(transcript: transcriptForPrompt(lines, flagged: flagged), lang: lang, hints: hints, ruleRisk: ruleRisk);
    // Low temperature: the same call should get the same verdict. One retry for a malformed answer.
    for (var i = 0; i < 2; i++) {
      final r = parseExplanation(await llm.generate(prompt, temperature: 0.2), lines: lines);
      if (r != null) return r;
    }
    return null;
  }
}
