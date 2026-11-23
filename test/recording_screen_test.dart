import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/screens/recording_screen.dart';
import 'package:scamshield/screens/report_screen.dart';
import 'package:scamshield/theme/app_theme.dart';
import 'package:scamshield/widgets/status_chip.dart';

const _channel = MethodChannel('scamshield/recording');

Map<String, Object?> _stmt(int ms, String text, String label, List<String> triggers) =>
    {'startMs': ms, 'text': text, 'label': label, 'triggers': triggers, 'shown': label};

void main() {
  late StreamController<Object?> events;

  setUp(() {
    events = StreamController<Object?>.broadcast();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (c) async {
      switch (c.method) {
        case 'recording.status':
          return {'modelReady': true, 'busy': false};
        case 'recording.pending':
        case 'recording.pick':
          return false;
        default:
          return true;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
    events.close();
  });

  for (final dark in [false, true]) {
    testWidgets('T2_7_rendersTimelineAndRisk${dark ? '_dark' : ''}', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: RecordingScreen(initialLang: 'en', api: RecordingApi(events: events.stream)),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('btn_pick')), findsOneWidget);
      expect(find.byKey(const Key('privacy_line')), findsOneWidget);

      // Fake the native side starting a job, then streaming progress.
      await t.tap(find.byKey(const Key('btn_pick'))); // pick -> false: stays idle
      await t.pumpAndSettle();
      events.add({'stage': 'shared', 'pct': 0}); // a share starts the job
      await t.pump(); // not pumpAndSettle: the indeterminate bar animates forever
      await t.pump();
      events.add({
        'stage': 'stt',
        'pct': 40,
        'segment': {'startMs': 0, 'text': 'Hello this is your bank'},
      });
      await t.pumpAndSettle();
      expect(find.byKey(const Key('progress_bar')), findsOneWidget);

      events.add({
        'stage': 'done',
        'pct': 100,
        'report': {
          'overall': 'SCAM',
          'risk': 0.87,
          'statements': [
            _stmt(0, 'Hello this is your bank', 'SAFE', []),
            _stmt(12000, 'Your account is blocked, share the OTP', 'SUSPICIOUS', ['OTP']),
            _stmt(65000, 'Transfer money now or you will be arrested', 'SCAM', ['arrested', 'transfer money']),
          ],
          'topTriggers': ['arrested', 'OTP'],
        },
      });
      await t.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('row_$i')), findsOneWidget);
      }
      expect(t.widget<Text>(find.byKey(const Key('row_time_2'))).data, '01:05');
      expect(find.text('Transfer money now or you will be arrested'), findsOneWidget);
      expect(find.byKey(const Key('risk_card')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('risk_value'))).data, '87%');
      expect(find.byKey(const Key('trigger_0')), findsOneWidget);
      expect(find.text('arrested'), findsOneWidget);
      expect(find.byType(StatusChip), findsNWidgets(4)); // overall + 3 rows
      expect(find.byKey(const Key('progress_bar')), findsNothing);

      // Report button opens ReportScreen.
      await t.ensureVisible(find.byKey(const Key('btn_report')));
      await t.tap(find.byKey(const Key('btn_report')));
      await t.pumpAndSettle();
      expect(find.byType(ReportScreen), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('T2_7_errorShowsMessage', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: RecordingScreen(initialLang: 'en', api: RecordingApi(events: events.stream))),
    ));
    await t.pumpAndSettle();
    events.add({'stage': 'shared', 'pct': 0});
    await t.pump();
    await t.pump();
    events.add({'stage': 'error', 'pct': 0, 'code': 'noSpeech'});
    await t.pumpAndSettle();
    expect(find.byKey(const Key('error_text')), findsOneWidget);
    expect(find.byKey(const Key('btn_pick')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
