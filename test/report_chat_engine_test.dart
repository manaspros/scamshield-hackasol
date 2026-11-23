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
      expect(r.nextSlot(), Slot.scammerId);
    });

    test('free words fill the number and amount on the way, so those questions are skipped', () {
      final r = ReportInterview(lost: true);
      r.answer(Slot.scamType, 'JOB', label: 'Task job');
      r.answer(Slot.channel, 'paid Rs 8,500 to earnfast@ybl on telegram');
      expect(r.answers[Slot.scammerId], 'earnfast@ybl');
      expect(r.answers[Slot.amount], '8500');
      expect(r.nextSlot(), Slot.payApp);
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

  group('gemma', () {
    const t = BotTurn(slot: Slot.amount, text: 'How much money was lost in total?');

    test('a good JSON reply replaces the wording; the prompt carries persona but no name', () async {
      final llm = _Llm('Sure! {"question": "Roughly how many rupees did you lose?"}');
      final out = await ReportChatLlm(client: llm).rephrase(t, 'en', 'age 67 (senior citizen), female', const {});
      expect(out, 'Roughly how many rupees did you lose?');
      expect(llm.lastPrompt, contains('senior citizen'));
      expect(llm.lastPrompt, contains('English'));
    });

    test('bad JSON, wrong script, no model or a timeout all keep the scripted question', () async {
      expect(await ReportChatLlm(client: _Llm('not json')).rephrase(t, 'en', 'x', const {}), isNull);
      expect(await ReportChatLlm(client: _Llm('{"question": "कितने रुपये?"}')).rephrase(t, 'en', 'x', const {}), isNull);
      expect(await ReportChatLlm(client: _Llm('{"question": "How much?"}')).rephrase(t, 'hi', 'x', const {}), isNull);
      expect(await ReportChatLlm(client: _Llm('{"question": "x"}', isReady: false)).rephrase(t, 'en', 'x', const {}), isNull);
      expect(await const ReportChatLlm(client: NoLlm()).rephrase(t, 'en', 'x', const {}), isNull);
    });
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
