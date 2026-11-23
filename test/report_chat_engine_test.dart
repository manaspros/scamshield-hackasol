import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/api/llm_api.dart';
import 'package:scamshield/l10n/strings_report_chat.dart';
import 'package:scamshield/profile/user_profile.dart';
import 'package:scamshield/report/report_chat_engine.dart';

final _now = DateTime(2026, 11, 23);

Persona _p({int? age, Gender? g, String? job, TechComfort? tech}) => Persona.of(
    UserProfile(dob: age == null ? null : DateTime(_now.year - age, 1, 1), gender: g, occupation: job, techComfort: tech),
    _now);

/// Walks the interview, answering each slot with [pick] (or the first choice), and returns the slots asked.
List<Slot> _walk(ReportInterview r, String lang, {Map<Slot, String> pick = const {}}) {
  final asked = <Slot>[];
  for (var guard = 0; guard < 30; guard++) {
    final s = r.nextSlot();
    if (s == null) break;
    asked.add(s);
    final t = r.turn(s, lang);
    final v = pick[s] ?? (t.choices.isEmpty ? '1000' : t.choices.first.value);
    r.answer(s, v, label: pick.containsKey(s) ? null : (t.choices.isEmpty ? null : t.choices.first.label));
  }
  return asked;
}

class _Llm implements LlmClient {
  _Llm(this.reply, {this.isReady = true});
  final String? reply;
  final bool isReady;
  String? lastPrompt;
  @override
  Future<bool> ready() async => isReady;
  @override
  Future<String?> generate(String prompt, {double temperature = 0.8}) async {
    lastPrompt = prompt;
    return reply;
  }
}

class _Slow implements LlmClient {
  @override
  Future<bool> ready() async => true;
  @override
  Future<String?> generate(String prompt, {double temperature = 0.8}) =>
      Future.delayed(const Duration(seconds: 5), () => '{}');
}

void main() {
  group('persona', () {
    test('senior, student, woman and low tech are read from the profile', () {
      final s = _p(age: 67, g: Gender.female);
      expect([s.senior, s.young, s.woman, s.lowTech], [true, false, true, true]);
      final y = _p(age: 30, job: 'College student');
      expect([y.senior, y.young], [false, true]);
      expect(_p(age: 22).young, isTrue);
      expect(_p(tech: TechComfort.low).lowTech, isTrue);
      expect(Persona.of(UserProfile.empty).variant, isNull);
    });
  });

  group('interview', () {
    test('senior who lost money: plain OTP question, senior scam types, family call offered', () {
      final r = ReportInterview(lost: true, persona: _p(age: 67), familyName: 'Ramesh', familyPhone: '9876543210');
      final asked = _walk(r, 'en');
      expect(asked, containsAllInOrder([Slot.scamType, Slot.amount, Slot.sharedOtp, Slot.family, Slot.extra]));
      expect(r.turn(Slot.sharedOtp, 'en').text, contains('code (OTP) that came by SMS'));
      expect(r.turn(Slot.sharedOtp, 'en').choices.map((c) => c.value), ['yes', 'no', 'unsure']);
      expect(r.turn(Slot.scamType, 'en').choices.map((c) => c.value), contains('PENSION'));
      final fam = r.turn(Slot.family, 'en');
      expect(fam.text, contains('Ramesh'));
      expect(fam.choices.first.action, ChoiceAction.callFamily);
      expect(asked, isNot(contains(Slot.harass)));
    });

    test('student goes straight to task-job / loan / investment scams', () {
      final r = ReportInterview(lost: true, persona: _p(age: 22, job: 'student'));
      final t = r.turn(Slot.scamType, 'en');
      expect(t.text, contains('task job'));
      expect(t.choices.map((c) => c.value).take(3), ['JOB', 'LOAN_APP', 'INVESTMENT']);
      expect(r.turn(Slot.channel, 'en').choices.first.value, 'telegram');
    });

    test('a woman is offered the 181 helpline; nobody else is', () {
      final w = ReportInterview(lost: false, persona: _p(age: 35, g: Gender.female));
      final asked = _walk(w, 'en');
      expect(asked, contains(Slot.harass));
      expect(w.turn(Slot.harass, 'en').text, contains('181'));
      expect(w.turn(Slot.harass, 'en').choices.first.action, ChoiceAction.call181);
      expect(_walk(ReportInterview(lost: false, persona: _p(age: 35, g: Gender.male)), 'en'), isNot(contains(Slot.harass)));
    });

    test('no money lost: no amount, app, OTP or UTR questions', () {
      final asked = _walk(ReportInterview(lost: false), 'en');
      for (final s in [Slot.payApp, Slot.amount, Slot.sharedOtp, Slot.utr, Slot.family]) {
        expect(asked, isNot(contains(s)));
      }
      expect(asked.last, Slot.extra);
    });

    test('confirming the detected warning takes its scam type and skips type + channel', () {
      final r = ReportInterview(lost: true, evidence: const [
        {'scamType': 'DIGITAL_ARREST', 'source': 'caption', 'time': '10:42', 'triggers': ['CBI']},
      ]);
      expect(r.nextSlot(), Slot.confirm);
      r.answer(Slot.confirm, 'yes', label: 'Yes, this one');
      expect(r.scamType, 'DIGITAL_ARREST');
      expect(r.nextSlot(), Slot.when);
    });

    test('free words fill the number and amount on the way, so those questions are skipped', () {
      final r = ReportInterview(lost: true);
      r.answer(Slot.scamType, 'JOB', label: 'Task job');
      r.answer(Slot.channel, 'paid Rs 8,500 to earnfast@ybl on telegram');
      expect(r.answers[Slot.scammerId], 'earnfast@ybl');
      expect(r.answers[Slot.amount], '8500');
      expect(r.nextSlot(), Slot.when);
    });

    test('attachments answer the proof question; fields feed the evidence ZIP', () {
      final r = ReportInterview(lost: true);
      r.answer(Slot.scammerId, '98765 43210');
      r.answer(Slot.amount, '₹15,000');
      r.addAttachments(const [ChatAttachment(path: '/c/a.png', name: 'a.png', mime: 'image/png')]);
      expect(r.answers[Slot.proof], '1');
      final f = r.fields('hi');
      expect(f['scammer_number'], '9876543210');
      expect(f['amount'], '15000');
      expect(f['screenshots'], 'a.png');
      expect(f.keys, containsAll(['scammer_number', 'amount', 'utr', 'screenshots', 'notes']));
    });

    test('the finish choice ends the interview and the summary lists what was given', () {
      final r = ReportInterview(lost: true);
      _walk(r, 'hi', pick: {Slot.amount: '15000', Slot.extra: 'done'});
      expect(r.done, isTrue);
      final rows = Map.fromEntries(r.summary('en').map((e) => MapEntry(e.$1, e.$2)));
      expect(rows['Amount lost'], contains('₹15,000'));
    });

    test('Hindi questions are in Devanagari; hne falls back to Hindi', () {
      final r = ReportInterview(lost: true, persona: _p(age: 67));
      expect(r.turn(Slot.sharedOtp, 'hi').text, contains('OTP'));
      expect(RegExp(r'[ऀ-ॿ]').hasMatch(r.turn(Slot.utr, 'hne').text), isTrue);
    });
  });

  group('parsing', () {
    test('amounts', () {
      expect(parseAmount('₹15,000'), 15000);
      expect(parseAmount('१५०००'), 15000);
      expect(parseAmount('15 हज़ार'), 15000);
      expect(parseAmount('2 lakh'), 200000);
      expect(parseAmount('nothing'), isNull);
      expect(formatInr(1500000), '15,00,000');
      expect(formatInr(8500), '8,500');
    });

    test('scammer ids', () {
      expect(findScammerId('UPI was earn.fast-1@okaxis'), 'earn.fast-1@okaxis');
      expect(findScammerId('called from +91 98765-43210'), '+919876543210');
      expect(findScammerId('no clue'), isNull);
    });
  });

  group('gemma drives the interview', () {
    test('the prompt lists the missing facts, what is known, the chat and the person (no name)', () async {
      final r = ReportInterview(lost: true, persona: _p(age: 67));
      r.answer(Slot.scamType, 'KYC', label: 'Bank / KYC');
      final llm = _Llm('{"ask": "channel", "question": "How did they reach you?", "options": ["Call", "SMS"]}');
      await ReportChatLlm(client: llm).next(r, 'en', 'age 67 (senior citizen), female', [(false, 'Hi'), (true, 'bank call')]);
      final p = llm.lastPrompt!;
      expect(p, contains('- amount:'));
      expect(p, contains('- utr:'));
      expect(p, isNot(contains('- scam_type:'))); // already known
      expect(p, contains('scam_type: Bank / KYC'));
      expect(p, contains('Person: bank call'));
      expect(p, contains('senior citizen'));
      expect(p, contains('simple English'));
      expect(p, contains('Never ask for an OTP, PIN'));
    });

    test('a good reply gives its own question + options and the facts it read', () async {
      final r = ReportInterview(lost: true);
      final llm = _Llm('Sure! {"extracted": {"amount": "8500", "scammer_id": "earnfast@ybl"}, '
          '"ask": "payment_app", "question": "Which app did you pay with?", "options": ["Google Pay", "PhonePe"]}');
      final t = await ReportChatLlm(client: llm).next(r, 'en', 'x', const []);
      expect(t!.ask, Slot.payApp);
      expect(t.question, 'Which app did you pay with?');
      expect(t.options, ['Google Pay', 'PhonePe']);
      r.applyExtracted(t.extracted);
      expect(r.answers[Slot.amount], '8500');
      expect(r.answers[Slot.scammerId], 'earnfast@ybl');
      expect(r.missingData, isNot(contains(Slot.amount)));
    });

    test('a question for a known fact, in the wrong script, or asking for the OTP itself is dropped; facts are kept', () {
      final missing = {Slot.amount, Slot.utr};
      expect(ReportChatLlm.parseTurn('{"ask": "scam_type", "question": "What scam?"}', 'en', missing)!.hasQuestion, isFalse);
      expect(ReportChatLlm.parseTurn('{"ask": "amount", "question": "कितने रुपये?"}', 'en', missing)!.hasQuestion, isFalse);
      expect(ReportChatLlm.parseTurn('{"ask": "amount", "question": "How much?"}', 'hi', missing)!.hasQuestion, isFalse);
      expect(ReportChatLlm.parseTurn('{"ask": "utr", "question": "Please tell me the OTP you got"}', 'en', missing)!.hasQuestion,
          isFalse);
      final keep = ReportChatLlm.parseTurn('{"extracted": {"amount": "500"}, "ask": "nope", "question": "?"}', 'en', missing)!;
      expect(keep.hasQuestion, isFalse);
      expect(keep.extracted, {Slot.amount: '500'});
      expect(ReportChatLlm.parseTurn('not json', 'en', missing), isNull);
    });

    test('extracted facts never overwrite an answer and "unknown" only settles optional ids', () {
      final r = ReportInterview(lost: true);
      r.answer(Slot.amount, '1000');
      r.applyExtracted({Slot.amount: '9999', Slot.utr: 'unknown', Slot.payApp: 'unknown', Slot.sharedOtp: 'haan'});
      expect(r.answers[Slot.amount], '1000');
      expect(r.answers[Slot.utr], 'none');
      expect(r.answers.containsKey(Slot.payApp), isFalse);
      expect(r.answers[Slot.sharedOtp], 'yes');
    });

    test('tapped model options are normalised (scam type, yes/no, amount)', () {
      final r = ReportInterview(lost: true);
      r.answer(Slot.scamType, 'Fake police / CBI call', label: 'Fake police / CBI call');
      r.answer(Slot.sharedOtp, 'नहीं', label: 'नहीं');
      r.answer(Slot.amount, '15 हज़ार', label: '15 हज़ार');
      expect(r.scamType, 'DIGITAL_ARREST');
      expect(r.answers[Slot.sharedOtp], 'no');
      expect(r.answers[Slot.amount], '15000');
    });

    test('no model, not ready, or a timeout -> null (the script asks)', () async {
      final r = ReportInterview(lost: true);
      expect(await const ReportChatLlm(client: NoLlm()).next(r, 'en', 'x', const []), isNull);
      expect(await ReportChatLlm(client: _Llm('{}', isReady: false)).next(r, 'en', 'x', const []), isNull);
      expect(await ReportChatLlm(client: _Slow(), timeout: const Duration(milliseconds: 10)).next(r, 'en', 'x', const []),
          isNull);
    });
  });

  group('classify', () {
    test('scam type from own words', () {
      expect(classifyScamType('they said CBI will arrest me'), 'DIGITAL_ARREST');
      expect(classifyScamType('टेलीग्राम पर टास्क जॉब'), 'JOB');
      expect(classifyScamType('loan app harassment'), 'LOAN_APP');
      expect(classifyScamType('bank KYC update'), 'KYC');
      expect(classifyScamType('something weird'), 'OTHER');
      expect(normalizeYesNo('Haan bataya'), 'yes');
      expect(normalizeYesNo('nahi'), 'no');
      expect(normalizeYesNo('maybe'), 'unsure');
    });

    test('own words for an unlisted scam show in the summary', () {
      final r = ReportInterview(lost: false);
      r.answer(Slot.scamType, 'fake army officer selling a car');
      expect(r.scamType, 'OTHER');
      expect(r.summary('en').first.$2, 'fake army officer selling a car');
    });
  });

  test('an interview survives a save / load round trip', () {
    final r = ReportInterview(lost: true);
    r.answer(Slot.scamType, 'JOB', label: 'Task job');
    r.answer(Slot.amount, '₹8,500');
    r.addAttachments(const [ChatAttachment(path: '/f/a.png', name: 'a.png', mime: 'image/png')]);
    final back = ReportInterview.fromJson(r.toJson());
    expect(back.lost, isTrue);
    expect(back.scamType, 'JOB');
    expect(back.answers[Slot.amount], '8500');
    expect(back.labels[Slot.scamType], 'Task job');
    expect(back.attachments.single.name, 'a.png');
    expect(back.nextSlot(), r.nextSlot());
  });

  test('every Hindi chat string has an English one without Devanagari', () {
    final dev = RegExp(r'[ऀ-ॿ]');
    for (final k in reportChatStrings.hi.keys) {
      expect(reportChatStrings.en.containsKey(k), isTrue, reason: 'en missing $k');
      expect(dev.hasMatch(reportChatStrings.en[k]!), isFalse, reason: 'en[$k] has Hindi');
    }
    for (final k in reportChatStrings.hne.keys) {
      expect(reportChatStrings.hi.containsKey(k), isTrue, reason: 'hne-only key $k');
    }
  });
}
