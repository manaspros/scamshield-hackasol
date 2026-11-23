import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/demo/demo_flag.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/screens/settings_screen.dart';
import 'package:scamshield/theme/theme_controller.dart';

import 'qa/qa_harness.dart';

Switch _sw(WidgetTester t, String key) => t.widget<Switch>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Switch)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppLanguage.debugSet('hi')); // these tests assert the Hindi-first copy

  testWidgets('T3_10_exportCallsChannel', (t) async {
    final prefs = <String, String>{};
    FakeChannel('scamshield/api', (c) async => c.method == 'getSettings' ? <String, Object?>{} : null).install();
    FakeChannel('scamshield/prefs', (c) async {
      final a = c.arguments as Map;
      if (c.method == 'setString') prefs[a['key'] as String] = a['value'] as String;
      return c.method == 'getString' ? prefs[a['key']] : null;
    }).install();
    final trend = FakeChannel('scamshield/trend', (c) async => <String, Object?>{'count': 3})..install();

    await show(t, themes['light']!(), const ShareCountsScreen()); // 360x740 at text scale 2.0
    final export = find.byKey(const Key('exportButton'));

    // No district yet: export is disabled.
    await tapVisible(t, export);
    expect(trend.calls, isEmpty);

    await tapVisible(t, find.byKey(const Key('districtPicker')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Raipur'), 200,
        scrollable: find.descendant(of: find.byKey(const Key('districtList')), matching: find.byType(Scrollable)));
    await t.ensureVisible(find.text('Raipur'));
    await t.pumpAndSettle();
    await t.tap(find.text('Raipur'));
    await t.pumpAndSettle();

    await tapVisible(t, export);
    await t.pumpAndSettle();
    expect(trend.calls, hasLength(1));
    expect(trend.calls.single.method, 'trend.export');
    expect((trend.calls.single.arguments as Map)['district'], 'Raipur');
    expect(prefs['district'], 'Raipur');
    expect(t.takeException(), isNull);
  });

  testWidgets('T3_10_loadingThenSavedDistrict_onTheShareRow', (t) async {
    FakeChannel('scamshield/api', (c) async => c.method == 'getSettings' ? <String, Object?>{'useLlm': true} : null).install();
    FakeChannel('scamshield/prefs', (c) async => c.method == 'getString' ? 'Durg' : null).install();
    t.view.physicalSize = const Size(360, 740);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: themes['light']!(), home: const Scaffold(body: SettingsScreen())));
    expect(find.byType(Switch), findsNothing); // first frame: loading, no defaults
    expect(find.text('लोड हो रहा है…'), findsOneWidget);
    await t.pumpAndSettle();
    await reveal(t, find.byKey(const Key('sw_useLlm')));
    expect(_sw(t, 'sw_useLlm').value, isTrue);
    await reveal(t, find.byKey(const Key('settings_share')));
    expect(find.descendant(of: find.byKey(const Key('settings_share')), matching: find.text('Durg')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('SETTINGS_theme_startsOnSystem_segmentsSwitchAndPersist', (t) async {
    final prefs = <String, String>{};
    FakeChannel('scamshield/api', (c) async => c.method == 'getSettings' ? <String, Object?>{} : null).install();
    FakeChannel('scamshield/prefs', (c) async {
      final a = c.arguments as Map;
      if (c.method == 'setString') prefs[a['key'] as String] = a['value'] as String;
      return c.method == 'getString' ? prefs[a['key']] : null;
    }).install();
    AppLanguage.debugSet('en');
    await show(t, themes['light']!(), const SettingsScreen(), scale: 1.0);
    expect(ThemeController.mode.value, ThemeMode.system);
    expect(find.text('Follows your phone. Pick one to override.'), findsOneWidget);
    await t.tap(find.byKey(const Key('theme_dark')));
    await t.pumpAndSettle();
    expect(ThemeController.mode.value, ThemeMode.dark);
    expect(prefs['theme_v1'], 'dark');
    await t.tap(find.byKey(const Key('theme_system')));
    await t.pumpAndSettle();
    expect(ThemeController.mode.value, ThemeMode.system);
    expect(prefs['theme_v1'], 'system');
  });

  testWidgets('SETTINGS_advancedPage_holdsDebugOptions_andDemoMode', (t) async {
    final api = FakeChannel('scamshield/api', (c) async => switch (c.method) {
          'getSettings' => <String, Object?>{'ocrFallback': false, 'captionPackages': 'com.x'},
          'setSettings' => <String, Object?>{'ocrFallback': true, 'captionPackages': 'com.x'},
          _ => null,
        })..install();
    FakeChannel('scamshield/prefs', (c) async => null).install();
    AppLanguage.debugSet('en');
    await show(t, themes['light']!(), const AdvancedSettingsScreen());
    expect(_sw(t, 'sw_ocrFallback').value, isFalse);
    await tapVisible(t, find.byKey(const Key('sw_ocrFallback')));
    await t.pumpAndSettle();
    expect(api.named('setSettings').single.arguments, {'ocrFallback': true});
    expect(_sw(t, 'sw_ocrFallback').value, isTrue);
    await reveal(t, find.byKey(const Key('demoModeSwitch')));
    expect(_sw(t, 'demoModeSwitch').value, DemoFlag.enabled.value);
    expect(t.takeException(), isNull);
  });
}
