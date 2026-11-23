import 'dart:async';
import 'dart:convert';

import '../api/llm_api.dart';
import '../l10n/strings_report_chat.dart';
import '../profile/user_profile.dart';

/// What the interview asks, in order. Each slot is asked at most once.
enum Slot { confirm, scamType, channel, scammerId, payApp, amount, sharedOtp, utr, proof, harass, family, extra }

/// What tapping a quick reply does besides answering.
enum ChoiceAction { none, attach, call181, callFamily, finish }

class ChatChoice {
  const ChatChoice(this.value, this.label, {this.action = ChoiceAction.none});
  final String value, label;
  final ChoiceAction action;
}

/// One bot question: the text (maybe rephrased by Gemma), quick replies, and what keyboard fits.
class BotTurn {
  const BotTurn({required this.slot, required this.text, this.choices = const [], this.numeric = false, this.lead});
  final Slot slot;
  final String text;
  final List<ChatChoice> choices;
  final bool numeric;

  /// An extra bot line shown just before the question (reassurance, a hint about the scam type).
  final String? lead;

  BotTurn withText(String t) => BotTurn(slot: slot, text: t, choices: choices, numeric: numeric, lead: lead);
}

/// Who the bot is talking to, from the on-phone profile. Shapes the questions, never the layout.
class Persona {
  const Persona({this.senior = false, this.young = false, this.woman = false, this.lowTech = false});
  final bool senior, young, woman, lowTech;

  static const general = Persona();

  factory Persona.of(UserProfile p, [DateTime? now]) {
    final age = p.ageOn(now);
    final job = (p.occupation ?? '').toLowerCase();
    final student = job.contains('student') || job.contains('छात्र') || job.contains('college') || job.contains('कॉलेज');
    final senior = age != null && age >= 60;
    return Persona(
      senior: senior,
      young: !senior && (student || (age != null && age <= 25)),
      woman: p.gender == Gender.female,
      lowTech: senior || p.techComfort == TechComfort.low,
    );
  }

  /// The string-table variant suffix for this person.
  String? get variant => senior ? 'senior' : (young ? 'young' : null);
}

/// A file the user attached (copied into the app cache by the native picker).
class ChatAttachment {
  const ChatAttachment({required this.path, required this.name, required this.mime, this.size = 0});
  final String path, name, mime;
  final int size;
  bool get isImage => mime.startsWith('image/');

  static ChatAttachment? fromMap(Map<Object?, Object?> m) {
    final path = m['path'], name = m['name'];
    if (path is! String || name is! String) return null;
    return ChatAttachment(path: path, name: name, mime: '${m['mime'] ?? ''}', size: (m['size'] as num?)?.toInt() ?? 0);
  }
}

/// The scripted interview: which slot comes next, how it is worded for this persona, and what the answers fill in.
/// Pure Dart (no widgets, no channels) so every branch is unit-tested; [ReportChatLlm] may reword the questions.
class ReportInterview {
  ReportInterview({
    required this.lost,
    this.persona = Persona.general,
    List<Map<Object?, Object?>> evidence = const [],
    this.familyName,
    this.familyPhone,
  }) : evidence = List.unmodifiable(evidence);

  final bool lost;
  final Persona persona;
  final List<Map<Object?, Object?>> evidence;
  final String? familyName, familyPhone;

  final Map<Slot, String> answers = {};

  /// Display labels for choice answers (value -> label), kept for the summary in the language they were picked.
  final Map<Slot, String> labels = {};
  final List<ChatAttachment> attachments = [];
  String? scamType; // a ScamType name (KYC, DIGITAL_ARREST…) or PENSION / LOTTERY

  bool finished = false;

  Map<Object?, Object?>? get latestEvidence => evidence.isEmpty ? null : evidence.first;

  bool _wanted(Slot s) => switch (s) {
        Slot.confirm => evidence.isNotEmpty,
        Slot.scamType => scamType == null,
        Slot.channel => answers[Slot.confirm] != 'yes',
        Slot.payApp || Slot.amount || Slot.sharedOtp || Slot.utr => lost,
        Slot.harass => persona.woman,
        Slot.family => persona.senior && lost && (familyPhone ?? '').isNotEmpty,
        _ => true,
      };

  /// The next unanswered slot, or null when the interview is done.
  Slot? nextSlot() {
    if (finished) return null;
    for (final s in Slot.values) {
      if (!answers.containsKey(s) && _wanted(s)) return s;
    }
    return null;
  }

  bool get done => nextSlot() == null;

  int get answeredCount => answers.length;

  /// The scripted question for [s] in [lang], worded for this persona.
  BotTurn turn(Slot s, String lang) {
    final v = persona.variant;
    String q(String k, [Map<String, Object> a = const {}]) => rcFor(lang, k, v, a);
    ChatChoice c(String value, String key, [ChoiceAction act = ChoiceAction.none, Map<String, Object> a = const {}]) =>
        ChatChoice(value, rc(lang, key, a), action: act);
    final yesNo = [c('yes', 'c_yes'), c('no', 'c_no'), c('unsure', 'c_not_sure')];
    return switch (s) {
      Slot.confirm => BotTurn(slot: s, text: q('q_confirm'), choices: [c('yes', 'c_yes_this'), c('no', 'c_no_else')]),
      Slot.scamType => BotTurn(slot: s, text: q('q_scamType'), choices: [for (final t in _typeChoices) c(t, 'st_$t')]),
      Slot.channel => BotTurn(slot: s, text: q('q_channel'), choices: [
          for (final ch in _channelChoices) c(ch, 'ch_$ch'),
        ]),
      Slot.scammerId => BotTurn(slot: s, text: q('q_scammerId'), choices: [c('unknown', 'c_dont_know')]),
      Slot.payApp => BotTurn(slot: s, text: q('q_payApp'), choices: [
          for (final p in const ['gpay', 'phonepe', 'paytm', 'bank', 'card', 'other']) c(p, 'pay_$p'),
        ]),
      Slot.amount => BotTurn(slot: s, text: q('q_amount'), numeric: true),
      Slot.sharedOtp => BotTurn(slot: s, text: q('q_sharedOtp'), choices: yesNo),
      Slot.utr => BotTurn(slot: s, text: q('q_utr'), choices: [c('none', 'c_cant_find')]),
      Slot.proof => BotTurn(slot: s, text: q('q_proof'), choices: [
          c('attach', 'c_add_photo', ChoiceAction.attach),
          c('skip', 'c_skip'),
        ]),
      Slot.harass => BotTurn(slot: s, text: q('q_harass'), choices: [
          c('call181', 'c_call181', ChoiceAction.call181),
          c('no', 'c_not_needed'),
        ]),
      Slot.family => BotTurn(slot: s, text: q('q_family', {'name': familyName ?? ''}), choices: [
          c('call', 'c_call_family', ChoiceAction.callFamily, {'name': familyName ?? ''}),
          c('no', 'c_not_now'),
        ]),
      Slot.extra => BotTurn(slot: s, text: q('q_extra'), choices: [c('done', 'c_finish', ChoiceAction.finish)]),
    };
  }

  List<String> get _typeChoices {
    if (persona.senior) return const ['DIGITAL_ARREST', 'KYC', 'OTP', 'PENSION', 'LOTTERY', 'OTHER'];
    if (persona.young) return const ['JOB', 'LOAN_APP', 'INVESTMENT', 'FAKE_QR', 'OTHER'];
    return const ['KYC', 'OTP', 'DIGITAL_ARREST', 'COURIER_CUSTOMS', 'INVESTMENT', 'JOB', 'FAKE_QR', 'OTHER'];
  }

  List<String> get _channelChoices => persona.young
      ? const ['telegram', 'whatsapp', 'app', 'call', 'sms', 'other']
      : const ['call', 'video', 'whatsapp', 'sms', 'app', 'other'];

  /// Records an answer to [s]: [value] is a choice value or the user's own words; [label] is what the chat showed.
  void answer(Slot s, String value, {String? label}) {
    final v = value.trim();
    answers[s] = v;
    if (label != null) labels[s] = label;
    switch (s) {
      case Slot.confirm:
        if (v == 'yes') scamType = latestEvidence?['scamType'] as String? ?? scamType;
      case Slot.scamType:
        scamType = _typeChoices.contains(v) ? v : 'OTHER';
      case Slot.scammerId:
        final id = findScammerId(v);
        if (id != null) answers[s] = id;
      case Slot.amount:
        final n = parseAmount(v);
        if (n != null) answers[s] = '$n';
      case Slot.extra:
        if (v == 'done') answers[s] = '';
        finished = true;
      default:
        break;
    }
    // Free words often carry more than was asked: pick up a number/UPI id and an amount on the way.
    if (label == null) _harvest(v);
  }

  void _harvest(String text) {
    if (!answers.containsKey(Slot.scammerId)) {
      final id = findScammerId(text);
      if (id != null) answers[Slot.scammerId] = id;
    }
    if (lost && !answers.containsKey(Slot.amount) && RegExp(r'(₹|rs\.?|inr|rupees?|रुपये|रुपए|रुपया)', caseSensitive: false).hasMatch(text)) {
      final n = parseAmount(text);
      if (n != null) answers[Slot.amount] = '$n';
    }
  }

  void addAttachments(Iterable<ChatAttachment> files) {
    attachments.addAll(files);
    if (attachments.isNotEmpty) answers[Slot.proof] = '${attachments.length}';
  }

  /// Fields for the native evidence ZIP (same keys as ReportPack.userFields).
  Map<String, String> fields(String lang) {
    String a(Slot s) {
      final v = answers[s] ?? '';
      return const {'unknown', 'none', 'skip', 'no', 'done'}.contains(v) ? '' : v;
    }

    final notes = [
      if (scamType != null) '${rc('en', 'k_type')}: ${_typeLabel('en')}',
      if (labels[Slot.channel] != null) '${rc('en', 'k_channel')}: ${rc('en', 'ch_${answers[Slot.channel]}')}',
      if (labels[Slot.payApp] != null) 'App: ${rc('en', 'pay_${answers[Slot.payApp]}')}',
      if (answers[Slot.sharedOtp] != null) '${rc('en', 'k_otp')}: ${answers[Slot.sharedOtp]}',
      if (a(Slot.extra).isNotEmpty) a(Slot.extra),
    ].join('; ');
    return {
      'scammer_number': a(Slot.scammerId),
      'amount': a(Slot.amount),
      'utr': a(Slot.utr),
      'screenshots': attachments.map((f) => f.name).join(', '),
      'notes': notes,
    };
  }

  /// Applies values edited by hand in the summary sheet.
  void applyEdits(Map<String, String> edited) {
    void put(Slot s, String? v) {
      if (v == null) return;
      if (v.trim().isEmpty) {
        answers.remove(s);
        if (s == Slot.scammerId || s == Slot.amount || s == Slot.utr) answers[s] = 'none';
      } else {
        answers[s] = v.trim();
      }
    }

    put(Slot.scammerId, edited['scammer_number']);
    put(Slot.amount, edited['amount']);
    put(Slot.utr, edited['utr']);
  }

  String _typeLabel(String lang) {
    final t = scamType;
    if (t == null) return '';
    final k = 'st_$t';
    final v = rc(lang, k);
    return v == k ? rc(lang, 'st_OTHER') : v;
  }

  /// Rows for the "Your report is ready" card.
  List<(String, String)> summary(String lang) {
    String val(Slot s) {
      final v = answers[s];
      if (v == null || const {'unknown', 'none', 'skip', 'unsure'}.contains(v) || v.isEmpty) return rc(lang, 'v_none');
      return v;
    }

    String choice(Slot s, String prefix) {
      final v = answers[s];
      if (v == null) return rc(lang, 'v_none');
      final k = '$prefix$v';
      final l = rc(lang, k);
      return l == k ? v : l;
    }

    final amount = val(Slot.amount);
    final rupees = amount == rc(lang, 'v_none') ? amount : '₹${formatInr(int.tryParse(amount) ?? 0, amount)}';
    return [
      (rc(lang, 'k_type'), _typeLabel(lang).isEmpty ? rc(lang, 'v_none') : _typeLabel(lang)),
      if (answers[Slot.channel] != null) (rc(lang, 'k_channel'), choice(Slot.channel, 'ch_')),
      (rc(lang, 'k_scammer'), val(Slot.scammerId)),
      if (lost)
        (
          rc(lang, 'k_amount'),
          answers[Slot.payApp] == null || rupees == rc(lang, 'v_none')
              ? rupees
              : rc(lang, 'v_via', {'amount': rupees, 'app': choice(Slot.payApp, 'pay_')}),
        ),
      if (lost)
        (
          rc(lang, 'k_otp'),
          switch (answers[Slot.sharedOtp]) {
            'yes' => rc(lang, 'c_yes'),
            'no' => rc(lang, 'c_no'),
            'unsure' => rc(lang, 'c_not_sure'),
            _ => rc(lang, 'v_none'),
          },
        ),
      if (lost) (rc(lang, 'k_utr'), val(Slot.utr)),
      (rc(lang, 'k_files'), attachments.isEmpty ? rc(lang, 'v_none') : rc(lang, 'v_files', {'n': attachments.length})),
    ];
  }
}

/// "₹15,000", "15000", "Rs 8,500", "१५०००" -> the whole rupees, or null.
int? parseAmount(String text) {
  final ascii = _asciiDigits(text);
  final m = RegExp(r'(\d[\d,]*)(?:\.\d+)?\s*(k|हज़ार|हजार|thousand|lakh|लाख)?', caseSensitive: false).firstMatch(ascii);
  if (m == null) return null;
  var n = int.tryParse(m.group(1)!.replaceAll(',', ''));
  if (n == null) return null;
  final unit = (m.group(2) ?? '').toLowerCase();
  if (unit == 'k' || unit == 'हज़ार' || unit == 'हजार' || unit == 'thousand') n *= 1000;
  if (unit == 'lakh' || unit == 'लाख') n *= 100000;
  return n > 0 && n < 1000000000 ? n : null;
}

/// A UPI id (name@bank) or an Indian mobile number found in [text].
String? findScammerId(String text) {
  final ascii = _asciiDigits(text);
  final upi = RegExp(r'[A-Za-z0-9._-]{2,}@[A-Za-z]{2,}').firstMatch(ascii);
  if (upi != null) return upi.group(0);
  final phone = RegExp(r'(?:\+?91[\s-]?)?[6-9]\d{4}[\s-]?\d{5}').firstMatch(ascii);
  return phone?.group(0)?.replaceAll(RegExp(r'[\s-]'), '');
}

String _asciiDigits(String s) {
  const dev = '०१२३४५६७८९';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = dev.indexOf(ch);
    b.write(i >= 0 ? '$i' : ch);
  }
  return b.toString();
}

/// Indian digit grouping: 1500000 -> 15,00,000.
String formatInr(int n, [String fallback = '']) {
  if (n <= 0) return fallback;
  final s = '$n';
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// Optional on-device Gemma layer: rewords a scripted question for this person and language.
/// Never adds questions or choices, so a bad answer can only cost wording; any failure keeps the script.
class ReportChatLlm {
  const ReportChatLlm({this.client = const LlmApi(), this.timeout = const Duration(seconds: 15)});
  final LlmClient client;
  final Duration timeout;

  static const _langName = {'hi': 'Hindi (Devanagari script)', 'hne': 'Chhattisgarhi (Devanagari script)', 'en': 'English'};

  String prompt(BotTurn t, String lang, String who, Map<Slot, String> answers) {
    final known = answers.entries
        .where((e) => e.value.isNotEmpty && e.key != Slot.proof)
        .map((e) => '${e.key.name}=${e.value}')
        .join(', ');
    return 'You help a scam victim in India report the fraud. The person is $who. '
        'Rewrite the question below so it is warm, simple and short (at most 25 words) for this person, '
        'written only in ${_langName[lang] ?? 'Hindi'}. Keep the meaning exactly; do not add new questions, '
        'advice, names or numbers. Already known: ${known.isEmpty ? 'nothing' : known}.\n'
        'Reply with JSON only: {"question": "..."}\n'
        'Question: ${t.text}';
  }

  /// The reworded question, or null to keep the scripted one.
  Future<String?> rephrase(BotTurn t, String lang, String who, Map<Slot, String> answers) async {
    try {
      if (!await client.ready()) return null;
      final raw = await client.generate(prompt(t, lang, who, answers), temperature: 0.4).timeout(timeout);
      return parseQuestion(raw, lang);
    } on TimeoutException {
      return null;
    } on Exception {
      return null;
    }
  }

  /// Pulls `question` out of the model's JSON; rejects empty, overlong or wrong-script answers.
  static String? parseQuestion(String? raw, String lang) {
    if (raw == null) return null;
    final m = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
    if (m == null) return null;
    Object? j;
    try {
      j = jsonDecode(m.group(0)!);
    } on FormatException {
      return null;
    }
    final q = j is Map ? j['question'] : null;
    if (q is! String) return null;
    final s = q.trim();
    if (s.isEmpty || s.length > 300) return null;
    final dev = RegExp(r'[ऀ-ॿ]').hasMatch(s);
    if (lang == 'en' ? dev : !dev) return null;
    return s;
  }
}
