import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/api/family_share.dart';
import 'package:scamshield/api/home_api.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/models/verdict.dart';
import 'package:scamshield/screens/past_alerts_screen.dart';
import 'package:scamshield/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ts = DateTime(2026, 11, 23, 14, 5).millisecondsSinceEpoch;

  test('R3_COV_share_noRawTextNoLongDigits', () {
    const raw = 'Your KYC expires today, share OTP 482913 now';
    for (final lang in ['en', 'hi', 'hne']) {
      final s = familyShareText(lang, 'KYC', ts);
      expect(s, contains('KYC'), reason: lang);
      expect(s, contains('23/11 14:05'), reason: lang);
      expect(s, isNot(contains(raw)), reason: lang);
      expect(RegExp(r'\d{6,}').hasMatch(s), isFalse, reason: lang);
    }
    expect(RegExp(r'\d{6,}').hasMatch(familyShareText('en', null, ts)), isFalse);
  });

  testWidgets('R3_COV_share_tellFamilyButtonInvokesShareChannel', (t) async {
    AppLanguage.debugSet('en');
    t.view.physicalSize = const Size(400, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final calls = <MethodCall>[];
    const ch = MethodChannel('scamshield/share');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, (c) async { calls.add(c); return null; });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, null));

    final alert = PastAlert(id: 1, tsMs: ts, source: 'sms', label: RiskLabel.scam, confidence: 0.9, triggers: const ['otp'], scamType: 'KYC');
    await t.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: AlertDetail(alert: alert))));
    expect(find.text('Tell my family'), findsOneWidget);
    await t.tap(find.byKey(const Key('alert_tell_family')));
    await t.pump();
    expect(calls.single.method, 'share.text');
    expect((calls.single.arguments as Map)['text'], contains('23/11 14:05'));
  });
}
