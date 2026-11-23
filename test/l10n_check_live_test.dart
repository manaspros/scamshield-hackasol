import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/screens/live_feed_screen.dart';
import 'package:scamshield/screens/try_api_screen.dart';
import 'package:scamshield/theme/app_theme.dart';

import 'qa/qa_harness.dart';

const _scam = <Object?, Object?>{
  'text': 'OTP bata dijiye',
  'label': 'SCAM',
  'confidence': 0.9,
  'reason': 'OTP maanga ja raha hai',
  'triggers': ['OTP bata'],
  'engine': 'rules-only',
  'latencyMs': 5,
  'source': 'paste',
  'scamType': 'OTP',
};

Future<void> _pump(WidgetTester t, Widget home, {double scale = 1.0, double height = 3000}) async {
  t.view.physicalSize = Size(360, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(size: Size(360, height), textScaler: TextScaler.linear(scale)),
      child: Scaffold(body: home),
    ),
  ));
}

void _mockApi(WidgetTester t) {
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), (_) async => _scam);
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), null));
}

Future<void> _check(WidgetTester t) async {
  await t.enterText(find.byType(TextField), 'OTP bata dijiye');
  await t.ensureVisible(find.byType(FilledButton));
  await t.tap(find.byType(FilledButton));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AppLanguage.debugSet('hi'));

  testWidgets('L10N_check_en', (t) async {
    AppLanguage.debugSet('en');
    _mockApi(t);
    await _pump(t, const TryApiScreen());
    expect(find.text('Paste a suspicious message here and we will tell you if it is a scam'), findsOneWidget);
    expect(find.text('Check message'), findsOneWidget);
    expect(find.text('Paste UPI link'), findsOneWidget);
    expect(find.text('Scan QR'), findsOneWidget);
    expect(find.text('मैसेज जाँचें'), findsNothing);
    // Empty input: English inline error
    await t.tap(find.byType(FilledButton));
    await t.pumpAndSettle();
    expect(find.text('Enter a message first'), findsOneWidget);

    await _check(t);
    expect(find.text('Scam!'), findsOneWidget);
    expect(find.text('This may be a scam'), findsOneWidget);
    expect(find.text('OTP theft'), findsOneWidget);
    expect(find.text('Stay calm. Do this now:'), findsOneWidget);
    expect(find.text('Do not send money, hang up'), findsOneWidget);
    expect(find.text('Call 1930'), findsOneWidget);
    expect(find.text('Why?'), findsOneWidget);
    expect(find.text('धोखाधड़ी!'), findsNothing);
    expect(find.text('पैसे न भेजें, कॉल काट दें'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('L10N_check_hi', (t) async {
    AppLanguage.debugSet('hi');
    _mockApi(t);
    await _pump(t, const TryApiScreen());
    expect(find.text('कोई संदिग्ध मैसेज यहाँ चिपकाएँ, हम बताएँगे कि ठगी तो नहीं'), findsOneWidget);
    expect(find.text('मैसेज जाँचें'), findsOneWidget);
    await _check(t);
    expect(find.text('धोखाधड़ी!'), findsOneWidget);
    expect(find.text('पैसे न भेजें, कॉल काट दें'), findsOneWidget);
    expect(find.text('1930 पर कॉल करें'), findsOneWidget);
    expect(find.text('क्यों?'), findsOneWidget);
    expect(find.text('ओटीपी माँगना · OTP theft'), findsOneWidget);
    expect(find.text('Scam!'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('L10N_check_en_scale2_360dp_noOverflow', (t) async {
    AppLanguage.debugSet('en');
    _mockApi(t);
    await _pump(t, const TryApiScreen(), scale: 2.0, height: 800);
    expect(t.takeException(), isNull);
    await _check(t);
    await t.tap(find.byKey(const Key('upi_section')));
    await t.pumpAndSettle();
    expect(find.text('Check link'), findsOneWidget);
    await t.dragUntilVisible(find.byKey(const Key('verdict_why')), find.byType(ListView), const Offset(0, -100));
    await t.tap(find.byKey(const Key('verdict_why')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  Future<void> feed(WidgetTester t) async {
    final emit = fakeEvents();
    await _pump(t, const LiveFeedScreen());
    emit({'type': 'call', 'active': true});
    emit({'type': 'signal', 'kind': 'link', 'trigger': 'link'});
    emit({'type': 'signal', 'kind': 'otp', 'trigger': 'otp'});
    emit({'type': 'service', 'connected': false});
    emit({'type': 'mic_probe', 'status': 'SILENT', 'source': 'VOICE_CALL', 'dbfs': -90.0, 'peak': 0, 'path': '/x.wav'});
    emit({..._scam.cast<String, Object?>(), 'type': 'verdict', 'callRisk': 0.9, 'callLevel': 'SCAM'});
    await t.pumpAndSettle();
  }

  testWidgets('L10N_live_en', (t) async {
    AppLanguage.debugSet('en');
    await feed(t);
    expect(find.text('Scam!'), findsOneWidget);
    expect(find.text('Do not send money, hang up'), findsOneWidget);
    expect(find.text('Call 1930'), findsOneWidget);
    expect(find.text('Free cyber-fraud helpline'), findsOneWidget);
    expect(find.text('Call started'), findsOneWidget);
    expect(find.text('In-call signal: link (link)'), findsOneWidget);
    expect(find.text('An OTP arrived during the call. Do not share it with anyone.'), findsOneWidget);
    expect(find.text('Protection service stopped'), findsOneWidget);
    expect(find.text('Mic test (VOICE_CALL): no audio detected'), findsOneWidget);
    expect(find.text('Earlier checks'), findsOneWidget);
    expect(find.text('Call in progress'), findsOneWidget);
    expect(find.text('कॉल शुरू हुई'), findsNothing);
    expect(find.text('Call ended'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('L10N_live_hi', (t) async {
    AppLanguage.debugSet('hi');
    await feed(t);
    expect(find.text('धोखाधड़ी!'), findsOneWidget);
    expect(find.text('कॉल शुरू हुई'), findsOneWidget);
    expect(find.text('Call started'), findsOneWidget); // small English second line stays
    expect(find.text('कॉल के दौरान OTP आया। किसी को न बताएँ।'), findsOneWidget);
    expect(find.text('सुरक्षा सेवा बंद हो गई'), findsOneWidget);
    expect(find.text('1930 पर कॉल करें'), findsOneWidget);
    expect(find.text('पिछली जाँच'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('L10N_live_en_scale2_360dp_noOverflow', (t) async {
    AppLanguage.debugSet('en');
    final emit = fakeEvents();
    await _pump(t, const LiveFeedScreen(), scale: 2.0, height: 800);
    expect(t.takeException(), isNull); // empty state
    emit({'type': 'call', 'active': true});
    emit({'type': 'signal', 'kind': 'otp', 'trigger': 'otp'});
    emit({'type': 'mic_probe', 'status': 'SILENT', 'source': 'VOICE_CALL', 'dbfs': -90.0, 'peak': 0, 'path': '/x.wav'});
    emit({..._scam.cast<String, Object?>(), 'type': 'verdict', 'callRisk': 0.9, 'callLevel': 'SCAM'});
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
