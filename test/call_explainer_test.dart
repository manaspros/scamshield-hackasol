import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/api/llm_api.dart';
import 'package:scamshield/api/report_upload.dart';
import 'package:scamshield/api/speech_models.dart';
import 'package:scamshield/api/model_api.dart';
import 'package:scamshield/models/verdict.dart';
import 'package:scamshield/recording/call_explainer.dart';

class _Llm implements LlmClient {
  _Llm(this.answers, {this.isReady = true});
  final List<String?> answers;
  final bool isReady;
  final prompts = <String>[];
  @override
  Future<bool> ready() async => isReady;
  @override
  Future<String?> generate(String prompt, {double temperature = 0.8}) async {
    prompts.add(prompt);
    return answers.isEmpty ? null : answers.removeAt(0);
  }
}

const _lines = [
  Line(0, 'Hello I am calling from SBI head office'),
  Line(12000, 'Your KYC is pending and the account will be blocked today'),
  Line(41000, 'Please read the six digit code to me quickly'),
];

void main() {
  group('parseExplanation', () {
    test('plain JSON', () {
      final e = parseExplanation(
          '{"verdict":"scam","risk":92,"summary":"Fake bank call.","steps":["a","b"],"flags":[{"quote":"read the six digit code","why":"OTP"}],"todo":["Hang up"]}',
          lines: _lines)!;
      expect(e.verdict, RiskLabel.scam);
      expect(e.risk, 92);
      expect(e.steps, ['a', 'b']);
      expect(e.flags.single.startMs, 41000); // matched to the line that says it
      expect(e.todo, ['Hang up']);
    });

    test('JSON inside a code fence with text around it', () {
      final e = parseExplanation('Sure!\n```json\n{"verdict":"Suspicious","summary":"Odd call."}\n```\nHope this helps');
      expect(e!.verdict, RiskLabel.suspicious);
      expect(e.risk, 55); // default for suspicious when no risk is given
    });

    test('garbage, unknown verdict or missing summary is rejected', () {
      expect(parseExplanation('I think it is a scam'), isNull);
      expect(parseExplanation('{"verdict":"maybe","summary":"x"}'), isNull);
      expect(parseExplanation('{"verdict":"scam"}'), isNull);
      expect(parseExplanation(null), isNull);
    });

    test('risk is clamped and lists are capped', () {
      final e = parseExplanation('{"verdict":"scam","risk":180,"summary":"s","steps":["1","2","3","4","5","6"]}')!;
      expect(e.risk, 100);
      expect(e.steps, hasLength(4));
    });
  });

  group('CallExplainer', () {
    test('whole transcript goes in one prompt, in the asked language', () async {
      final llm = _Llm(['{"verdict":"scam","risk":90,"summary":"x"}']);
      final e = await CallExplainer(llm: llm).explain(lines: _lines, lang: 'hi');
      expect(e!.verdict, RiskLabel.scam);
      expect(llm.prompts, hasLength(1));
      for (final l in _lines) {
        expect(llm.prompts.single, contains(l.text));
      }
      expect(llm.prompts.single, contains('Hindi'));
    });

    test('one retry after a malformed answer, then gives up', () async {
      final llm = _Llm(['oops', 'still oops']);
      expect(await CallExplainer(llm: llm).explain(lines: _lines, lang: 'en'), isNull);
      expect(llm.prompts, hasLength(2));
    });

    test('no model loaded: no prompt at all', () async {
      final llm = _Llm(const [], isReady: false);
      expect(await CallExplainer(llm: llm).explain(lines: _lines, lang: 'en'), isNull);
      expect(llm.prompts, isEmpty);
    });

    test('a long call is trimmed to its start plus the flagged lines', () {
      final lines = [for (var i = 0; i < 200; i++) Line(i * 1000, 'line number $i says nothing special at all')];
      final out = transcriptForPrompt(lines, flagged: {150});
      expect(out.length, lessThanOrEqualTo(kMaxTranscriptChars + 20));
      expect(out, contains('line number 0 '));
      expect(out, contains('line number 150 '));
      expect(out, contains('[…]'));
    });
  });

  group('scrubTranscript', () {
    test('masks phone numbers, account numbers, OTPs and UPI IDs', () {
      final s = scrubTranscript('call 98271 23456 or +91-9827123456, OTP 482913, pay ravi.k@oksbi, amount 500');
      expect(s, isNot(contains('98271')));
      expect(s, isNot(contains('482913')));
      expect(s, isNot(contains('ravi.k@oksbi')));
      expect(s, contains('amount 500')); // short numbers stay readable
      expect(RegExp(r'\d{6,}').hasMatch(s), isFalse);
    });
  });

  group('speech models', () {
    test('small model in the app language is recommended; large one blocked on low RAM', () {
      expect(recommendSttId('en'), 'vosk-small-en-in');
      expect(recommendSttId('hne'), 'vosk-small-hi');
      expect(sttBlockFor(sttById('vosk-hi'), const DeviceInfo(totalRamMb: 6000, freeStorageMb: 50000)), SttBlock.lowRam);
      expect(sttBlockFor(sttById('vosk-hi'), const DeviceInfo(totalRamMb: 12000, freeStorageMb: 2000)), SttBlock.lowStorage);
      expect(sttBlockFor(sttById('vosk-small-hi'), const DeviceInfo(totalRamMb: 3000, freeStorageMb: 2000)), isNull);
    });
  });
}
