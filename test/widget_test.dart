import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/models/verdict.dart';

void main() {
  test('Verdict.fromMap parses native map', () {
    final v = Verdict.fromMap({
      'text': 'OTP bata dijiye',
      'label': 'SCAM',
      'confidence': 0.874,
      'reason': 'Asks you to share an OTP/code',
      'triggers': ['OTP bata dijiye'],
      'engine': 'gemma+rules',
      'latencyMs': 1420,
      'source': 'caption',
      'preliminary': false,
    });
    expect(v.label, RiskLabel.scam);
    expect(v.percent, 87);
    expect(v.headline, 'This statement is SCAM · 87%');
    expect(v.triggers, ['OTP bata dijiye']);
    expect(v.latencyMs, 1420);
  });

  test('Verdict.fromMap tolerates missing fields and bad values', () {
    final v = Verdict.fromMap({'label': 'weird', 'confidence': 3});
    expect(v.label, RiskLabel.safe);
    expect(v.confidence, 1.0);
    expect(v.engine, 'unknown');
    expect(v.triggers, isEmpty);
  });

  test('parseLabel', () {
    expect(parseLabel('suspicious'), RiskLabel.suspicious);
    expect(parseLabel(null), RiskLabel.safe);
  });
}
