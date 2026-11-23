import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/screens/report_screen.dart';
import 'package:scamshield/theme/app_theme.dart';

const _channel = MethodChannel('scamshield/handoff');

Map<String, Object?> _pack({required bool lost}) => {
      'moneyLost': lost,
      'targets': lost
          ? [
              {'name': 'Helpline', 'phone': '1930', 'url': null},
              {'name': 'Portal', 'phone': null, 'url': 'https://cybercrime.gov.in'},
            ]
          : [
              {'name': 'Chakshu', 'phone': null, 'url': 'https://sancharsaathi.gov.in/sfc/'},
              {'name': 'Helpline', 'phone': '1930', 'url': null},
            ],
      'evidence': [
        {
          'tsMs': 1,
          'time': '2026-11-23 10:15 IST',
          'scamType': 'DIGITAL_ARREST',
          'source': 'caption',
          'triggers': ['CBI', 'arrest warrant'],
        },
      ],
      'userFields': const [],
    };

/// Fake native side: records every call and answers like HandoffChannel.kt.
class _Fake {
  final calls = <MethodCall>[];
  Map<String, Object?> golden = {'started': false};

  Future<Object?> handle(MethodCall c) async {
    calls.add(c);
    final args = c.arguments is Map ? c.arguments as Map : const {};
    switch (c.method) {
      case 'report.pack':
        return _pack(lost: args['moneyLost'] == true);
      case 'golden.status':
        return golden;
      case 'golden.start':
        return golden = {
          'started': true,
          'startMs': 1,
          'remainingMs': 3600000,
          'pack': _pack(lost: true),
        };
      case 'dial':
      case 'open':
      case 'golden.share':
        return true;
    }
    return null;
  }

  List<MethodCall> named(String m) => calls.where((c) => c.method == m).toList();
}

Future<_Fake> _setup(WidgetTester t) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1.0;
  t.platformDispatcher.textScaleFactorTestValue = 2.0;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
  final fake = _Fake();
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, fake.handle);
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
  return fake;
}

Future<void> _show(WidgetTester t) async {
  await t.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: ReportScreen())));
  await t.pump();
  await t.pump();
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pump();
  await t.pump();
}

void main() {
  setUp(() => AppLanguage.debugSet('hi')); // these tests read the default Hindi from the app-wide language
  testWidgets('T3_2_prefillsFromEvent', (t) async {
    final fake = await _setup(t);
    await _show(t);
    await _tap(t, find.byKey(const Key('path_lost')));
    expect(fake.named('report.pack').single.arguments, {'moneyLost': true});
    expect(find.text('2026-11-23 10:15 IST'), findsOneWidget);
    expect(find.textContaining('डिजिटल अरेस्ट'), findsOneWidget);
    expect(find.text('arrest warrant'), findsOneWidget);
    expect(find.byKey(const Key('field_utr')), findsOneWidget);
    expect(find.byKey(const Key('btn_open_cybercrime.gov.in')), findsOneWidget);

    await _tap(t, find.byKey(const Key('path_notyet')));
    expect(fake.named('report.pack').last.arguments, {'moneyLost': false});
    expect(find.byKey(const Key('field_utr')), findsNothing); // amount / UTR only after a loss
    expect(find.byKey(const Key('btn_open_sancharsaathi.gov.in')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('T3_2_dialIsDialNotCall', (t) async {
    final fake = await _setup(t);
    await _show(t);
    await _tap(t, find.byKey(const Key('path_lost')));
    await _tap(t, find.byKey(const Key('btn_dial_1930')));
    expect(fake.named('dial').single.arguments, {'number': '1930'});
    expect(fake.named('call'), isEmpty);

    // Native side: dialer only, no call permission anywhere.
    const k = 'android/app/src/main/kotlin/com/hackasol/scamshield/HandoffChannel.kt';
    final kt = File(k).readAsStringSync();
    expect(kt, contains('Intent.ACTION_DIAL'));
    expect(kt, isNot(contains('Intent.ACTION_CALL')));
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(), isNot(contains('CALL_PHONE')));
    expect(t.takeException(), isNull);
  });

  test('T3_2_stringsComplete', () {
    final keys = ReportStrings.en.m.keys.toSet();
    expect(ReportStrings.hi.m.keys.toSet(), keys);
    expect(ReportStrings.hne.m.keys.toSet(), keys);
  });

  testWidgets('T5_5_timerAndCard', (t) async {
    final fake = await _setup(t);
    await _show(t);
    await _tap(t, find.byKey(const Key('path_lost')));
    expect(find.byKey(const Key('golden_timer')), findsNothing);

    await _tap(t, find.byKey(const Key('golden_start')));
    expect(fake.named('golden.start').single.arguments, {'restart': false});
    expect(find.text('60:00'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    expect(find.text('59:55'), findsOneWidget);
    expect(find.text('arrest warrant'), findsOneWidget); // case card is pre-filled from the log

    await t.enterText(find.byKey(const Key('field_utr')), 'UTR000123');
    await _tap(t, find.byKey(const Key('btn_share')));
    final share = fake.named('golden.share').single.arguments as Map;
    expect((share['fields'] as Map)['utr'], 'UTR000123');

    // The start time lives natively: a rebuilt screen resumes the clock instead of showing "start".
    await t.pumpWidget(const SizedBox());
    fake.golden = {'started': true, 'startMs': 1, 'remainingMs': 3000000, 'pack': _pack(lost: true)};
    await _show(t);
    expect(find.text('50:00'), findsOneWidget);
    expect(find.byKey(const Key('golden_start')), findsNothing);

    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('androidx.core.content.FileProvider'));
    final paths = File('android/app/src/main/res/xml/file_paths.xml').readAsStringSync();
    expect(paths, contains('<cache-path name="evidence" path="evidence/"'));
    expect(paths, isNot(contains('external')));

    await t.pumpWidget(const SizedBox()); // cancels the periodic timer
    expect(t.takeException(), isNull);
  });
}
