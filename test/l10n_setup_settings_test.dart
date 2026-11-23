import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/screens/settings_screen.dart';
import 'package:scamshield/screens/setup_screen.dart';

import 'qa/qa_harness.dart';

final _devanagari = RegExp('[ऀ-ॿ]');

/// Like `show`, but with the LangScope the app installs, so the screens rebuild on a language change.
Future<void> _pump(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(360, 740);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: themes['light']!(),
    builder: (c, w) => LangScope(
      notifier: AppLanguage.current,
      child: MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)), child: w!),
    ),
    home: Scaffold(body: home),
  ));
  await t.pump(const Duration(milliseconds: 100));
  await t.pumpAndSettle();
}

void _fakeNative() {
  fakeEvents();
  FakeChannel('scamshield/prefs', (c) async => null).install();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppLanguage.debugSet('en'));
  tearDown(() => AppLanguage.debugSet(null));

  testWidgets('L10N_setup_englishHasNoHindiScript', (t) async {
    _fakeNative();
    FakeChannel('scamshield/api', (c) async => switch (c.method) {
          'serviceStatus' => {'enabled': false, 'connected': false},
          'modelStatus' => {'status': 'MISSING', 'message': 'none'},
          'downloadStatus' => {'status': 'IDLE'},
          'micPermission' => false,
          'perm.notificationsGranted' => false,
          'perm.notificationAccessGranted' => false,
          _ => null,
        }).install();
    await _pump(t, const SetupScreen());
    expect(find.text('0 / 4 required steps done'), findsOneWidget);
    expect(find.text('Turn on call protection'), findsWidgets);
    await t.scrollUntilVisible(find.text('Open Accessibility'), 200, scrollable: find.byType(Scrollable).first);
    await t.drag(find.byType(ListView).first, const Offset(0, 6000));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('setup_firstrun_card')), findsNothing);
    // Open the optional section too, then scan every visible Text for Devanagari.
    await t.scrollUntilVisible(find.byKey(const Key('setup_advanced')), 300, maxScrolls: 100);
    await t.tap(find.byKey(const Key('setup_advanced')));
    await t.pumpAndSettle();
    final all = <String>[];
    for (var i = 0; i < 40; i++) {
      all.addAll(t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? w.textSpan?.toPlainText() ?? ''));
      await t.drag(find.byType(ListView).first, const Offset(0, -300));
      await t.pump();
    }
    expect(all.where(_devanagari.hasMatch), isEmpty);
    expect(all.any((s) => s.contains('On-device AI model')), isTrue);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('L10N_setup_hindiKeepsEnglishSecondaryLine', (t) async {
    AppLanguage.debugSet('hi');
    _fakeNative();
    FakeChannel('scamshield/api', (c) async => switch (c.method) {
          'serviceStatus' => {'enabled': false, 'connected': false},
          'modelStatus' => {'status': 'MISSING', 'message': 'none'},
          'downloadStatus' => {'status': 'IDLE'},
          'micPermission' => false,
          'perm.notificationsGranted' => false,
          'perm.notificationAccessGranted' => false,
          _ => null,
        }).install();
    await _pump(t, const SetupScreen());
    expect(find.text('0 / 4 ज़रूरी कदम पूरे'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Turn on call protection'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Turn on call protection'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  group('settings', () {
    void fakeSettings() {
      FakeChannel('scamshield/api', (c) async => c.method == 'getSettings' ? <String, Object?>{'useLlm': true} : null).install();
      FakeChannel('scamshield/prefs', (c) async => null).install();
    }

    testWidgets('L10N_settings_languageRowFirstAndSwitchesLive', (t) async {
      fakeSettings();
      await _pump(t, const SettingsScreen());
      final row = find.byKey(const Key('settings_language_row'));
      expect(row, findsOneWidget);
      // First in the list: above the "Warning settings" header.
      expect(t.getTopLeft(row).dy, lessThan(t.getTopLeft(find.text('Warning settings')).dy));
      expect(find.descendant(of: row, matching: find.text('English')), findsOneWidget);
      expect(find.text('Show warning chip during calls'), findsOneWidget);

      AppLanguage.debugSet('hi');
      await t.pumpAndSettle();
      expect(find.text('चेतावनी की सेटिंग'), findsOneWidget);
      AppLanguage.debugSet('en');
      await t.pumpAndSettle();

      await t.tap(row);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('lang_hne')), findsOneWidget);
      await t.tap(find.byKey(const Key('lang_hi')));
      await t.pumpAndSettle();
      expect(AppLanguage.code, 'hi');
      expect(find.byKey(const Key('lang_hne')), findsNothing); // page closed
      expect(find.text('चेतावनी की सेटिंग'), findsOneWidget);

      await t.tap(row);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('lang_en')));
      await t.pumpAndSettle();
      expect(find.text('Warning settings'), findsOneWidget);
      expect(find.text('चेतावनी की सेटिंग'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('L10N_settings_englishHasNoHindiExceptLanguageNames', (t) async {
      fakeSettings();
      await _pump(t, const SettingsScreen());
      await t.scrollUntilVisible(find.byKey(const Key('settings_advanced')), 300,
          scrollable: find.byType(Scrollable).first, maxScrolls: 100);
      // The extra alert row lengthens the list; bring the tile fully on screen so the tap lands.
      await t.ensureVisible(find.byKey(const Key('settings_advanced')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('settings_advanced')));
      await t.pumpAndSettle();
      final all = <String>[];
      for (var i = 0; i < 40; i++) {
        all.addAll(t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''));
        await t.drag(find.byType(Scrollable).first, const Offset(0, 300));
        await t.pump();
      }
      for (var i = 0; i < 40; i++) {
        all.addAll(t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''));
        await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await t.pump();
      }
      // The only Hindi allowed is the deliberate "Language / भाषा" label.
      expect(all.where(_devanagari.hasMatch).toSet(), isEmpty.or(equals({'Language / भाषा'})));
      expect(all, contains('Use on-device Gemma'));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  });
}

extension on Matcher {
  Matcher or(Matcher other) => anyOf(this, other);
}
