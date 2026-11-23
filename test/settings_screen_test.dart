import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/screens/settings_screen.dart';

import 'qa/qa_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T3_10_exportCallsChannel', (t) async {
    final prefs = <String, String>{};
    FakeChannel('scamshield/api', (c) async => c.method == 'getSettings' ? <String, Object?>{} : null).install();
    FakeChannel('scamshield/prefs', (c) async {
      final a = c.arguments as Map;
      if (c.method == 'setString') prefs[a['key'] as String] = a['value'] as String;
      return c.method == 'getString' ? prefs[a['key']] : null;
    }).install();
    final trend = FakeChannel('scamshield/trend', (c) async => <String, Object?>{'count': 3})..install();

    await show(t, themes['light']!(), const SettingsScreen()); // 360x740 at text scale 2.0
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

  testWidgets('T3_10_loadingThenSavedDistrict', (t) async {
    FakeChannel('scamshield/api', (c) async => c.method == 'getSettings' ? <String, Object?>{'useLlm': true} : null).install();
    FakeChannel('scamshield/prefs', (c) async => c.method == 'getString' ? 'Durg' : null).install();
    t.view.physicalSize = const Size(360, 740);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: themes['light']!(), home: const Scaffold(body: SettingsScreen())));
    expect(find.byType(SwitchListTile), findsNothing); // first frame: loading, no defaults
    expect(find.text('लोड हो रहा है…'), findsOneWidget);
    await t.pumpAndSettle();
    await tapVisible(t, find.byKey(const Key('settings_advanced')));
    await t.pumpAndSettle();
    expect(t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Use on-device Gemma')).value, isTrue);
    await reveal(t, find.byKey(const Key('districtPicker')));
    expect(find.text('Durg'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
