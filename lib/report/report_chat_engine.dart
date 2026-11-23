import 'dart:async';
import 'dart:convert';

import '../api/llm_api.dart';
import '../l10n/strings_report_chat.dart';
import '../profile/user_profile.dart';

/// What the interview collects / asks. Each slot is asked at most once.
enum Slot { confirm, scamType, channel, when, scammerId, payApp, amount, sharedOtp, utr, proof, harass, family, extra }

/// The facts the police complaint needs. With a model loaded, Gemma writes the questions for these itself;
/// the other slots (confirm, proof, helplines, extra) trigger app actions and stay scripted.
const dataSlots = {Slot.scamType, Slot.channel, Slot.when, Slot.scammerId, Slot.payApp, Slot.amount, Slot.sharedOtp, Slot.utr};

/// Field names and plain descriptions handed to the model.
const _llmFields = <Slot, (String, String)>{
  Slot.scamType: ('scam_type', 'what kind of scam (fake police/CBI "digital arrest", bank or KYC, OTP, task or part-time job, loan app, investment, courier/customs, fake QR/UPI, prize/lottery, pension/insurance, other)'),
  Slot.channel: ('channel', 'how the scammer contacted them (phone call, video call, SMS, WhatsApp, Telegram, app or website)'),
  Slot.when: ('when', 'when it happened (day and rough time)'),
  Slot.scammerId: ('scammer_id', 'the scammer\'s phone number, UPI ID, account number or username ("unknown" if they do not know)'),
  Slot.payApp: ('payment_app', 'which app or bank the money went from'),
  Slot.amount: ('amount', 'total rupees lost, digits only'),
  Slot.sharedOtp: ('otp_shared', 'whether they told anyone an OTP or PIN: yes, no or unsure (never ask for the code itself)'),
  Slot.utr: ('utr', 'the 12-digit transaction reference (UTR) in the bank SMS ("unknown" if not found)'),
};

Slot? _slotOfField(String name) {
  for (final e in _llmFields.entries) {
    if (e.value.$1 == name) return e.key;
  }
  return null;
}

/// What tapping a quick reply does besides answering.
enum ChoiceAction { none, attach, call181, callFamily, finish }

class ChatChoice {
  const ChatChoice(this.value, this.label, {this.action = ChoiceAction.none});
  final String value, label;
  final ChoiceAction action;
}

/// One bot question: the text (scripted or written by Gemma), quick replies, and what keyboard fits.
class BotTurn {
  const BotTurn({required this.slot, required this.text, this.choices = const [], this.numeric = false, this.byLlm = false});
  final Slot slot;
  final String text;
  final List<ChatChoice> choices;
  final bool numeric;
  final bool byLlm;
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

  /// Tone instructions for the model.
  String get style => [
        if (senior) 'They are a senior citizen: use very simple, short, kind words and reassure them.',
        if (young) 'They are young or a student: be direct; task-job, loan-app and investment scams are common for them.',
        if (lowTech) 'They are not comfortable with phones: always give tap-able options.',
      ].join(' ');
}

/// A file the user attached (copied into app storage by the native picker).
class ChatAttachment {
  const ChatAttachment({required this.path, required this.name, required this.mime, this.size = 0});
  final String path, name, mime;
  final int size;
  bool get isImage => mime.startsWith('image/');

  Map<String, Object?> toJson() => {'path': path, 'name': name, 'mime': mime, 'size': size};

  static ChatAttachment? fromMap(Map<Object?, Object?> m) {
    final path = m['path'], name = m['name'];
    if (path is! String || name is! String) return null;
    return ChatAttachment(path: path, name: name, mime: '${m['mime'] ?? ''}', size: (m['size'] as num?)?.toInt() ?? 0);
  }
}

/// The interview: which facts are still missing, the scripted fallback questions (worded for this persona), and
/// what the answers fill in. Pure Dart (no widgets, no channels) so every branch is unit-tested.
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

  /// What the chat showed for an answer (a tapped label or the user's own words), for the summary.
  final Map<Slot, String> labels = {};
  final List<ChatAttachment> attachments = [];
  String? scamType; // a ScamType name (KYC, DIGITAL_ARREST…) or PENSION / LOTTERY / OTHER

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

  /// The next unanswered slot in script order, or null when the interview is done.
  Slot? nextSlot() {
    if (finished) return null;
    for (final s in Slot.values) {
      if (!answers.containsKey(s) && _wanted(s)) return s;
    }
    return null;
  }

  /// Facts still to collect (the model may ask them in any order).
  Set<Slot> get missingData => {for (final s in dataSlots) if (!answers.containsKey(s) && _wanted(s)) s};

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
      Slot.channel => BotTurn(slot: s, text: q('q_channel'), choices: [for (final ch in _channelChoices) c(ch, 'ch_$ch')]),
      Slot.when => BotTurn(slot: s, text: q('q_when'), choices: [
          for (final w in const ['today', 'yesterday', 'week', 'earlier']) c(w, 'w_$w'),
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

  /// Records an answer to [s]: [value] is a choice value or the user's own words; [label] is what the chat showed
  /// for a tapped choice (null for typed / spoken words).
  void answer(Slot s, String value, {String? label}) {
    final v = value.trim();
    answers[s] = v;
    labels[s] = label ?? v;
    switch (s) {
      case Slot.confirm:
        if (v == 'yes') scamType = latestEvidence?['scamType'] as String? ?? scamType;
      case Slot.scamType:
        scamType = kScamTypes.contains(v) ? v : classifyScamType(v);
      case Slot.scammerId:
        final id = findScammerId(v);
        if (id != null) answers[s] = id;
        if (_isUnknown(v)) answers[s] = 'unknown';
      case Slot.amount:
        final n = parseAmount(v);
        if (n != null) answers[s] = '$n';
      case Slot.sharedOtp:
        answers[s] = normalizeYesNo(v);
      case Slot.utr:
        if (_isUnknown(v)) answers[s] = 'none';
      case Slot.extra:
        if (v == 'done') answers[s] = '';
        finished = true;
      default:
        break;
    }
    // Free words often carry more than was asked: pick up a number/UPI id and an amount on the way.
    if (label == null) _harvest(v);
  }

  /// Facts the model pulled out of the user's words. Only fills missing facts; never overwrites an answer.
  void applyExtracted(Map<Slot, String> found) {
    for (final e in found.entries) {
      final s = e.key, v = e.value.trim();
      if (!dataSlots.contains(s) || answers.containsKey(s) || !_wanted(s) || v.isEmpty) continue;
      if (_isUnknown(v) && s != Slot.scammerId && s != Slot.utr) continue; // "unknown" only settles optional ids
      answer(s, v, label: v);
    }
  }

  void _harvest(String text) {
    if (!answers.containsKey(Slot.scammerId)) {
      final id = findScammerId(text);
      if (id != null) {
        answers[Slot.scammerId] = id;
        labels[Slot.scammerId] = id;
      }
    }
    if (lost && !answers.containsKey(Slot.amount) && RegExp(r'(₹|rs\.?|inr|rupees?|रुपये|रुपए|रुपया)', caseSensitive: false).hasMatch(text)) {
      final n = parseAmount(text);
      if (n != null) {
        answers[Slot.amount] = '$n';
        labels[Slot.amount] = '$n';
      }
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
      if (answers[Slot.channel] != null) '${rc('en', 'k_channel')}: ${_choiceLabel(Slot.channel, 'ch_', 'en')}',
      if (answers[Slot.when] != null) '${rc('en', 'k_when')}: ${_choiceLabel(Slot.when, 'w_', 'en')}',
      if (answers[Slot.payApp] != null) 'App: ${_choiceLabel(Slot.payApp, 'pay_', 'en')}',
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
      answers[s] = v.trim().isEmpty ? 'none' : v.trim();
      labels[s] = answers[s]!;
    }

    put(Slot.scammerId, edited['scammer_number']);
    put(Slot.amount, edited['amount']);
    put(Slot.utr, edited['utr']);
  }

  /// A choice code shown in [lang] ("ch_call" -> "Phone call"); the user's own words as they were.
  String _choiceLabel(Slot s, String prefix, String lang) {
    final v = answers[s];
    if (v == null) return rc(lang, 'v_none');
    final k = '$prefix$v';
    final l = rc(lang, k);
    return l != k ? l : (labels[s] ?? v);
  }

  String _typeLabel(String lang) {
    final t = scamType;
    if (t == null) return '';
    final k = 'st_$t';
    final v = rc(lang, k);
    // A type in the user's own words ("fake army officer"): show their words, not "Something else".
    if (t == 'OTHER' && (labels[Slot.scamType] ?? '').isNotEmpty && !kScamTypes.contains(labels[Slot.scamType])) {
      return labels[Slot.scamType]!;
    }
    return v == k ? rc(lang, 'st_OTHER') : v;
  }

  /// Rows for the "Your report is ready" card.
  List<(String, String)> summary(String lang) {
    final none = rc(lang, 'v_none');
    String val(Slot s) {
      final v = answers[s];
      if (v == null || const {'unknown', 'none', 'skip', 'unsure'}.contains(v) || v.isEmpty) return none;
      return v;
    }

    final amount = val(Slot.amount);
    final rupees = amount == none ? amount : '₹${formatInr(int.tryParse(amount) ?? 0, amount)}';
    return [
      (rc(lang, 'k_type'), _typeLabel(lang).isEmpty ? none : _typeLabel(lang)),
      if (answers[Slot.channel] != null) (rc(lang, 'k_channel'), _choiceLabel(Slot.channel, 'ch_', lang)),
      if (answers[Slot.when] != null) (rc(lang, 'k_when'), _choiceLabel(Slot.when, 'w_', lang)),
      (rc(lang, 'k_scammer'), val(Slot.scammerId)),
      if (lost)
        (
          rc(lang, 'k_amount'),
          answers[Slot.payApp] == null || rupees == none
              ? rupees
              : rc(lang, 'v_via', {'amount': rupees, 'app': _choiceLabel(Slot.payApp, 'pay_', lang)}),
        ),
      if (lost)
        (
          rc(lang, 'k_otp'),
          switch (answers[Slot.sharedOtp]) {
            'yes' => rc(lang, 'c_yes'),
            'no' => rc(lang, 'c_no'),
            'unsure' => rc(lang, 'c_not_sure'),
            _ => none,
          },
        ),
      if (lost) (rc(lang, 'k_utr'), val(Slot.utr)),
      (rc(lang, 'k_files'), attachments.isEmpty ? none : rc(lang, 'v_files', {'n': attachments.length})),
    ];
  }

  // ---- history ----------------------------------------------------------------------------------------------

  Map<String, Object?> toJson() => {
        'lost': lost,
        'answers': {for (final e in answers.entries) e.key.name: e.value},
        'labels': {for (final e in labels.entries) e.key.name: e.value},
        'scamType': scamType,
        'finished': finished,
        'files': [for (final f in attachments) f.toJson()],
      };

  /// Rebuilds a saved interview. The persona and family contact come from today's profile.
  factory ReportInterview.fromJson(Map<String, Object?> m, {Persona persona = Persona.general, String? familyName, String? familyPhone}) {
    Slot? slot(String n) => Slot.values.where((s) => s.name == n).firstOrNull;
    final iv = ReportInterview(lost: m['lost'] == true, persona: persona, familyName: familyName, familyPhone: familyPhone);
    for (final e in ((m['answers'] as Map?) ?? const {}).entries) {
      final s = slot('${e.key}');
      if (s != null) iv.answers[s] = '${e.value}';
    }
    for (final e in ((m['labels'] as Map?) ?? const {}).entries) {
      final s = slot('${e.key}');
      if (s != null) iv.labels[s] = '${e.value}';
    }
    iv.scamType = m['scamType'] as String?;
    iv.finished = m['finished'] == true;
    for (final f in (m['files'] as List?) ?? const []) {
      final a = f is Map ? ChatAttachment.fromMap(f.cast<Object?, Object?>()) : null;
      if (a != null) iv.attachments.add(a);
    }
    return iv;
  }
}

const kScamTypes = {
  'DIGITAL_ARREST', 'KYC', 'OTP', 'PENSION', 'LOTTERY', 'JOB', 'LOAN_APP', 'INVESTMENT', 'FAKE_QR', 'COURIER_CUSTOMS',
  'MISTAKEN_TRANSFER', 'OTHER',
};

/// Words (English / Hindi) -> a scam type code. "OTHER" when nothing matches.
String classifyScamType(String text) {
  final t = text.toLowerCase();
  bool any(List<String> w) => w.any(t.contains);
  if (any(['arrest', 'police', 'cbi', 'customs officer', 'पुलिस', 'अरेस्ट', 'गिरफ़्तार', 'गिरफ्तार'])) return 'DIGITAL_ARREST';
  if (any(['task', 'part-time', 'part time', 'job', 'youtube like', 'नौकरी', 'जॉब', 'टास्क'])) return 'JOB';
  if (any(['loan', 'लोन', 'कर्ज'])) return 'LOAN_APP';
  if (any(['invest', 'stock', 'share market', 'trading', 'crypto', 'निवेश', 'शेयर'])) return 'INVESTMENT';
  if (any(['courier', 'parcel', 'customs', 'fedex', 'कूरियर', 'पार्सल'])) return 'COURIER_CUSTOMS';
  if (any(['qr', 'collect request', 'स्कैन'])) return 'FAKE_QR';
  if (any(['lottery', 'prize', 'lucky draw', 'kbc', 'इनाम', 'लॉटरी'])) return 'LOTTERY';
  if (any(['pension', 'insurance', 'पेंशन', 'बीमा'])) return 'PENSION';
  if (any(['otp', 'ओटीपी'])) return 'OTP';
  if (any(['kyc', 'bank', 'account block', 'केवाईसी', 'बैंक'])) return 'KYC';
  if (any(['wrong transfer', 'mistake', 'galti', 'गलती'])) return 'MISTAKEN_TRANSFER';
  return 'OTHER';
}

/// "haan" / "हाँ" / "yes" -> yes; "nahi" / "नहीं" / "no" -> no; else unsure.
String normalizeYesNo(String text) {
  final t = text.toLowerCase().trim();
  if (const {'yes', 'no', 'unsure'}.contains(t)) return t;
  if (RegExp(r'^(yes|yeah|haan|han|ha|हाँ|हां|हा|हव|जी)\b').hasMatch(t) || t.startsWith('हाँ') || t.startsWith('हां')) return 'yes';
  if (RegExp(r'^(no|nahi|nahin|nope|नहीं|नही|ना|नइ)\b').hasMatch(t) || t.startsWith('नहीं') || t.startsWith('नही')) return 'no';
  return 'unsure';
}

bool _isUnknown(String v) {
  final t = v.toLowerCase().trim();
  return const {'unknown', 'none', 'null', 'n/a', "don't know", 'dont know', 'not sure', 'पता नहीं', 'नहीं पता', 'नहीं मिला'}
      .contains(t);
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

/// What Gemma decided for the next step: facts it read from the last answer, and its own question for a missing fact.
class LlmTurn {
  const LlmTurn({this.extracted = const {}, this.ask, this.question, this.options = const []});
  final Map<Slot, String> extracted;
  final Slot? ask;
  final String? question;
  final List<String> options;

  bool get hasQuestion => ask != null && question != null;
}

/// On-device Gemma drives the interview: it is given the facts still missing (with what each one means), what is
/// already known, the recent chat, the person and the language, and it writes the next question itself.
/// The app keeps the guard rails: the question must target a missing fact and be in the right script, or the
/// scripted question is used; a tapped/typed answer always fills the asked fact, so the chat cannot loop.
class ReportChatLlm {
  const ReportChatLlm({this.client = const LlmApi(), this.timeout = const Duration(seconds: 25)});
  final LlmClient client;
  final Duration timeout;

  static const _langName = {'hi': 'Hindi (Devanagari script)', 'hne': 'Chhattisgarhi (Devanagari script)', 'en': 'simple English'};

  String prompt(ReportInterview iv, String lang, String who, List<(bool, String)> transcript) {
    final missing = [for (final s in dataSlots) if (iv.missingData.contains(s)) s];
    final known = [
      for (final s in dataSlots)
        if (iv.answers.containsKey(s)) '${_llmFields[s]!.$1}: ${iv.labels[s] ?? iv.answers[s]}',
    ];
    final chat = transcript.length > 8 ? transcript.sublist(transcript.length - 8) : transcript;
    final lines = [
      for (final (user, text) in chat) '${user ? 'Person' : 'You'}: ${text.length > 200 ? text.substring(0, 200) : text}',
    ];
    return 'You are ScamShield, a calm helper who interviews a scam victim in India to file a police cyber-crime '
        'complaint (helpline 1930). The person is $who. ${iv.persona.style} '
        '${iv.lost ? 'They lost money.' : 'They have not lost money yet.'}\n'
        'Facts still needed:\n${[for (final s in missing) '- ${_llmFields[s]!.$1}: ${_llmFields[s]!.$2}'].join('\n')}\n'
        'Already known: ${known.isEmpty ? 'nothing' : known.join('; ')}\n'
        'Conversation so far:\n${lines.isEmpty ? '(none)' : lines.join('\n')}\n\n'
        'Step 1: from the person\'s LAST message, copy any of the needed facts into "extracted" (only facts they really said).\n'
        'Step 2: ask ONE short question (max 25 words) for the most important fact still needed, in '
        '${_langName[lang] ?? 'Hindi'} only. Never ask for an OTP, PIN, password or CVV itself. Give 2 to 5 short '
        'answer options the person can tap, in the same language.\n'
        'Reply with JSON only, like: {"extracted": {"amount": "15000"}, "ask": "${missing.isEmpty ? 'when' : _llmFields[missing.first]!.$1}", '
        '"question": "...", "options": ["...", "..."]}';
  }

  /// Gemma's next step, or null (no model, timeout, unusable reply) so the script takes over.
  Future<LlmTurn?> next(ReportInterview iv, String lang, String who, List<(bool, String)> transcript) async {
    if (iv.missingData.isEmpty) return null;
    try {
      if (!await client.ready()) return null;
      final raw = await client.generate(prompt(iv, lang, who, transcript), temperature: 0.4).timeout(timeout);
      return parseTurn(raw, lang, iv.missingData);
    } on TimeoutException {
      return null;
    } on Exception {
      return null;
    }
  }

  static final _secret = RegExp(r'\b(otp|pin|password|cvv)\b.*\b(tell|share|send|type|enter|बताएँ|बताइए|भेजें|लिखें)\b|'
      r'\b(tell|share|send|type|enter)\b.*\b(otp|pin|password|cvv)\b', caseSensitive: false);

  /// Parses `{"extracted":{...},"ask":"...","question":"...","options":[...]}`. Facts are kept even when the
  /// question is rejected (wrong script, not a missing fact, asks for a secret, too long).
  static LlmTurn? parseTurn(String? raw, String lang, Set<Slot> missing) {
    if (raw == null) return null;
    final m = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
    if (m == null) return null;
    Object? j;
    try {
      j = jsonDecode(m.group(0)!);
    } on FormatException {
      return null;
    }
    if (j is! Map) return null;
    final extracted = <Slot, String>{};
    final ex = j['extracted'];
    if (ex is Map) {
      for (final e in ex.entries) {
        final s = _slotOfField('${e.key}');
        final v = e.value;
        if (s != null && v != null && '$v'.trim().isNotEmpty && '$v'.length <= 120) extracted[s] = '$v'.trim();
      }
    }
    final dev = RegExp(r'[ऀ-ॿ]');
    bool rightScript(String s) => lang == 'en' ? !dev.hasMatch(s) : dev.hasMatch(s);
    final ask = _slotOfField('${j['ask'] ?? ''}');
    final q = j['question'] is String ? (j['question'] as String).trim() : '';
    final okQuestion = ask != null &&
        missing.contains(ask) &&
        !extracted.containsKey(ask) &&
        q.isNotEmpty &&
        q.length <= 300 &&
        rightScript(q) &&
        !_secret.hasMatch(q);
    final opts = <String>[
      if (okQuestion && j['options'] is List)
        for (final o in (j['options'] as List).take(5))
          if (o is String && o.trim().isNotEmpty && o.trim().length <= 40) o.trim(),
    ];
    return LlmTurn(extracted: extracted, ask: okQuestion ? ask : null, question: okQuestion ? q : null, options: opts);
  }
}
