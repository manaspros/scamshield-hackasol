import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/l10n/strings_shell.dart';
import 'package:scamshield/main.dart';
import 'package:scamshield/widgets/floating_nav.dart';
import 'package:scamshield/models/verdict.dart';
import 'package:scamshield/widgets/verdict_card.dart';

/// 360dp phone at system text scale 2.0 with a fake native prefs store.
Map<String, String> _phone(WidgetTester tester, {Map<String, String>? stored}) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = 2.0;
  final prefs = {...?stored};
  const prefsCh = MethodChannel('scamshield/prefs');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(prefsCh, (call) async {
    final a = call.arguments as Map;
    if (call.method == 'setString') prefs['${a['key']}'] = '${a['value']}';
    return call.method == 'getString' ? prefs['${a['key']}'] : null;
  });
  const apiCh = MethodChannel('scamshield/api');
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(apiCh, (call) async => call.method == 'getSettings' ? <String, Object?>{} : null);
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(apiCh, null);
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(prefsCh, null);
  });
  return prefs;
}

const _scam = Verdict(
  text: 'OTP bata dijiye',
  label: RiskLabel.scam,
  confidence: 0.9,
  reason: 'Asks you to share an OTP/code',
  triggers: ['OTP'],
  engine: 'rules',
  latencyMs: 5,
  source: 'manual',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(AppLanguage.debugReset);

  testWidgets('L10N_firstLaunch_showsPickerWithNoSelection', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const ScamShieldApp());
    await tester.pump();

    expect(find.byKey(const Key('lang_prompt')), findsOneWidget);
    expect(find.text('Choose your language / अपनी भाषा चुनें'), findsOneWidget);
    for (final c in ['en', 'hi', 'hne']) {
      expect(find.byKey(Key('lang_$c')), findsOneWidget);
    }
    expect(find.byIcon(Icons.check_circle), findsNothing); // nothing pre-selected
    expect(find.byKey(const Key('btn_report_1930')), findsNothing); // app not shown yet
  });

  testWidgets('L10N_storedLanguage_skipsPicker', (tester) async {
    _phone(tester, stored: {'lang_v1': 'en'});
    await tester.pumpWidget(const ScamShieldApp());
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('lang_prompt')), findsNothing);
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('L10N_chooseEnglish_tabsAndVerdictCardAreEnglish_persisted', (tester) async {
    final prefs = _phone(tester);
    await tester.pumpWidget(const ScamShieldApp());
    await tester.pump();
    await tester.tap(find.byKey(const Key('lang_en')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(prefs['lang_v1'], 'en');
    for (final (key, label) in [('nav_home', 'Home'), ('nav_learn', 'Learn'), ('nav_profile', 'Profile')]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.descendant(of: find.byType(FloatingNav), matching: find.text(label)), findsOneWidget);
    }
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('होम'), findsNothing);

    await tester.pumpWidget(MaterialApp(
      builder: (c, child) => LangScope(notifier: AppLanguage.current, child: child!),
      home: const Scaffold(body: SingleChildScrollView(child: VerdictCard(verdict: _scam, showDebug: false, initiallyExpanded: true))),
    ));
    expect(find.text('Scam!'), findsOneWidget);
    expect(find.text('This may be a scam'), findsOneWidget);
    expect(find.text('Why?'), findsOneWidget);
    expect(find.text('धोखाधड़ी!'), findsNothing);
  });

  testWidgets('L10N_settingsLanguageRow_switchesWholeAppLive_andPersists', (tester) async {
    final prefs = _phone(tester, stored: {'lang_v1': 'hi'});
    await tester.pumpWidget(const ScamShieldApp());
    await tester.pump();
    await tester.pump();
    expect(find.descendant(of: find.byType(FloatingNav), matching: find.text('होम')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_profile')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(find.byKey(const Key('profile_settings')), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const Key('profile_settings')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('profile_settings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('settings_language_row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('lang_en')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(prefs['lang_v1'], 'en');
    expect(AppLanguage.code, 'en');
    expect(find.descendant(of: find.byType(FloatingNav, skipOffstage: false), matching: find.text('Profile', skipOffstage: false), skipOffstage: false), findsOneWidget);
    expect(find.text('Settings'), findsWidgets); // pushed screen title followed the change
    expect(find.text('सेटिंग'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('L10N_english_scale2_at360dp_mainScreensDoNotOverflow', (tester) async {
    _phone(tester, stored: {'lang_v1': 'en'});
    await tester.pumpWidget(const ScamShieldApp());
    await tester.pump();
    await tester.pump();
    for (final tip in ['nav_home', 'nav_learn', 'nav_profile']) {
      await tester.tap(find.byKey(Key(tip)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: tip);
    }
  });

  test('L10N_hneFallsBackToHi_enNeverFallsBackToHindi', () {
    const t = Tri(hi: {'a': 'हिंदी', 'b': 'दो'}, hne: {'a': 'छत्तीसगढ़ी'}, en: {'a': 'one'});
    expect(t('hne', 'a'), 'छत्तीसगढ़ी');
    expect(t('hne', 'b'), 'दो');
    expect(t('en', 'b'), 'b');
    expect(t('xx', 'a'), 'हिंदी');
  });

  test('L10N_shell_englishHasNoHindi_helpCaptionsIncluded', () {
    final hindi = RegExp('[\u0900-\u097F]');
    final bad = shellStrings.en.entries.where((e) => hindi.hasMatch(e.value)).map((e) => e.key).toList();
    expect(bad, isEmpty);
    for (final k in ['report_cap', 'family_cap', 'settings_cap', 'recording_cap', 'demo_cap', 'help_sub']) {
      expect(shellStrings.en[k], isNotNull, reason: k);
    }
  });
}
