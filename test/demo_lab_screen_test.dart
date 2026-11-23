import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/demo/demo_flag.dart';
import 'package:scamshield/main.dart';
import 'package:scamshield/screens/demo_lab_screen.dart';

import 'qa/qa_harness.dart';

Map<String, Object?> _step(int i, {required int delayMs, required String text, required List<String> ctx, required String label}) => {
      'index': i,
      'delayMs': delayMs,
      'source': i == 0 ? 'sms' : 'call',
      'sender': i == 0 ? 'AX-FAKEBK' : 'caller_1',
      'text': text,
      'contextLines': ctx,
      'ruleTriggers': i == 0 ? ['debited', 'amount'] : ['send back'],
      'gemma': i == 0 ? {'label': 'SUSPICIOUS', 'scamType': 'FAKE_DEBIT', 'reason': 'Looks typed by a person'} : null,
      'fused': {
        'label': label,
        'confidence': i == 0 ? 0.72 : 0.93,
        'scamType': i == 0 ? null : 'MISTAKEN_TRANSFER',
        'raisedBy': i == 0 ? ['gemma'] : ['graph', 'rules'],
      },
      'alert': i == 0
          ? null
          : {'title': '[DEMO] Possible scam call', 'text': 'This caller refers to a message you wrote yourself.', 'reportAction': 'report'},
      'expectedLabel': label,
      'expectedFlags': i == 0 ? <String>[] : ['MISTAKEN_TRANSFER'],
      'actualFlags': i == 0 ? <String>[] : ['MISTAKEN_TRANSFER'],
      'pass': true,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DemoFlag.enabled.value = kDebugMode);

  testWidgets('T8_1_hiddenWhenFlagOff', (t) async {
    t.view.physicalSize = const Size(360, 740);
    t.view.devicePixelRatio = 1.0;
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearAllTestValues);
    FakeChannel('scamshield/api', (c) async => switch (c.method) {
          'serviceStatus' => {'enabled': true, 'connected': true},
          'modelStatus' => {'status': 'READY', 'message': 'ok', 'path': '/m', 'sizeMb': 555},
          'downloadStatus' => {'status': 'IDLE'},
          'micPermission' || 'perm.notificationsGranted' || 'perm.notificationAccessGranted' => true,
          'getSettings' => {'useLlm': true},
          _ => null,
        }).install();
    FakeChannel('scamshield/prefs', (c) async => c.method == 'getString' && (c.arguments as Map)['key'] == 'demo_mode' ? '0' : null).install();
    fakeEvents();

    await t.pumpWidget(const ScamShieldApp());
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.byTooltip('Help'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));

    expect(find.text('रिपोर्ट करें'), findsOneWidget); // the hub itself is on screen
    expect(find.byKey(const Key('tile_demo_lab')), findsNothing);
    expect(find.text('डेमो लैब'), findsNothing);
    expect(DemoFlag.enabled.value, isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('T8_1_runShowsTimeline', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    const ctxLine = 'Known context: user-typed SMS about a debit, 2 min ago, not from a bank';
    final demo = FakeChannel('scamshield/demo', (c) async => switch (c.method) {
          'demo.scenarios' => [
              {
                'id': 's1',
                'icon': 'sms',
                'titleHi': 'खाते से पैसे कटे, फिर कॉल',
                'titleEn': 'Debit SMS, then a call',
                'storyHi': 'एक SMS आया, फिर कॉल: पैसे लौटा दो',
                'storyEn': 'An SMS, then a call: send the money back',
                'steps': 2,
              }
            ],
          'demo.modelReady' => false,
          'demo.run' => {
              'scenarioId': 's1',
              'engineUsed': 'rules',
              'note': 'Model not ready, rules only',
              'steps': [
                _step(0, delayMs: 0, text: 'Rs 5000 debited from your account', ctx: const [], label: 'SUSPICIOUS'),
                _step(1, delayMs: 800, text: 'Please send the money back', ctx: const [ctxLine], label: 'SCAM'),
              ],
              'pass': true,
            },
          _ => null,
        })..install();

    await t.pumpWidget(MaterialApp(
      theme: themes['light']!(),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)), child: w!),
      home: const Scaffold(body: DemoLabScreen()),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    // modelReady false: Gemma is forced off, with the reason on screen.
    expect(t.widget<SwitchListTile>(find.byKey(const Key('demo_engine'))).onChanged, isNull);
    expect(find.text('The model is not ready, so only rules will run.'), findsNothing); // Hindi first
    expect(find.text('मॉडल तैयार नहीं है, इसलिए सिर्फ़ नियम चलेंगे।'), findsOneWidget);

    await tapVisible(t, find.byKey(const Key('demo_run_s1')));
    await t.pump(const Duration(milliseconds: 100));
    expect(demo.named('demo.run').single.arguments, {'id': 's1', 'engine': 'rules', 'coldStart': false});
    expect(find.byKey(const Key('demo_step_1')), findsOneWidget);
    expect(find.byKey(const Key('demo_step_2')), findsNothing); // step 2 waits on its 800 ms delay

    await t.tap(find.byKey(const Key('demo_skip')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('demo_step_2')), findsOneWidget);
    expect(find.byKey(const Key('demo_skip')), findsNothing); // run finished

    for (final stage in ['Event ingested', 'Known context', 'Rule hits (masked)', 'Gemma output', 'Fusion', 'Alert fired']) {
      expect(find.text(stage), findsNWidgets(2), reason: stage);
    }
    await reveal(t, find.text(ctxLine));
    await reveal(t, find.text('[DEMO] Possible scam call'));
    expect(find.byKey(const Key('demo_alert_preview')), findsOneWidget);
    expect(find.byKey(const Key('demo_alert_report')), findsOneWidget);
    expect(find.text('सिर्फ़ नियम, Gemma नहीं'), findsNWidgets(1)); // step 2 has no Gemma output
    expect(find.descendant(of: find.byKey(const Key('demo_badge_s1')), matching: find.text('PASS')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('demo_step_badge_2')), matching: find.text('PASS')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
