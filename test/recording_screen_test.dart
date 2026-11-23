import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/api/llm_api.dart';
import 'package:scamshield/api/report_upload.dart';
import 'package:scamshield/recording/call_explainer.dart';
import 'package:scamshield/screens/recording_screen.dart';
import 'package:scamshield/screens/report_screen.dart';
import 'package:scamshield/screens/speech_model_screen.dart';
import 'package:scamshield/theme/app_theme.dart';

const _channel = MethodChannel('scamshield/recording');
const _prefs = MethodChannel('scamshield/prefs');

Map<String, Object?> _stmt(int ms, String text, String label, List<String> triggers) =>
    {'startMs': ms, 'text': text, 'label': label, 'triggers': triggers, 'shown': label};

final _report = {
  'overall': 'SCAM',
  'risk': 0.87,
  'statements': [
    _stmt(0, 'Hello this is your bank', 'SAFE', []),
    _stmt(12000, 'Your account is blocked, share the OTP', 'SUSPICIOUS', ['OTP']),
    _stmt(65000, 'Transfer money now or you will be arrested', 'SCAM', ['arrested', 'transfer money']),
  ],
  'topTriggers': ['arrested', 'OTP'],
};

class _Llm implements LlmClient {
  _Llm(this.answer);
  final String? answer;
  int calls = 0;
  @override
  Future<bool> ready() async => answer != null;
  @override
  Future<String?> generate(String prompt, {double temperature = 0.8}) async {
    calls++;
    return answer;
  }
}

class _Sender implements ReportSender {
  final sent = <CallReportUpload>[];
  @override
  Future<bool> send(CallReportUpload r) async {
    sent.add(r);
    return true;
  }
}

void main() {
  late StreamController<Object?> events;
  late bool modelReady;
  late List<MethodCall> calls;

  setUp(() {
    events = StreamController<Object?>.broadcast();
    modelReady = true;
    calls = [];
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_channel, (c) async {
      calls.add(c);
      return switch (c.method) {
        'recording.status' => {'modelReady': modelReady, 'busy': false, 'sttId': 'vosk-small-hi'},
        'recording.list' => {
            'granted': true,
            'items': [
              {'uri': 'content://media/external/audio/media/7', 'name': 'Call recording SBI', 'dateMs': DateTime(2026, 11, 2, 16, 32).millisecondsSinceEpoch, 'durationMs': 194000},
            ],
          },
        'recording.pending' || 'recording.pick' => false,
        _ => true,
      };
    });
    m.setMockMethodCallHandler(_prefs, (c) async => c.method == 'getString' ? 'Raipur' : null);
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_channel, null);
    m.setMockMethodCallHandler(_prefs, null);
    events.close();
  });

  Future<void> show(WidgetTester t, {bool dark = false, LlmClient llm = const NoLlm(), ReportSender? sender}) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      home: Scaffold(
        body: RecordingScreen(
          initialLang: 'en',
          api: RecordingApi(events: events.stream),
          explainer: CallExplainer(llm: llm),
          sender: sender ?? _Sender(),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  Future<void> transcribe(WidgetTester t) async {
    await t.tap(find.byKey(const Key('call_0')));
    await t.pump(); // not pumpAndSettle: the bar is indeterminate until the first percent arrives
    await t.pump(const Duration(milliseconds: 500));
    events.add({'stage': 'stt', 'pct': 20, 'segment': {'startMs': 0, 'text': 'Hello this is your bank'}});
    await t.pump(const Duration(milliseconds: 700));
    events.add({'stage': 'stt', 'pct': 60, 'segment': {'startMs': 12000, 'text': 'Your account is blocked, share the OTP'}});
    await t.pump(const Duration(milliseconds: 700));
  }

  for (final dark in [false, true]) {
    testWidgets('REC_readyListsCallRecordings_thenTranscriptIsOneParagraph_thenKeywordReport${dark ? '_dark' : ''}', (t) async {
      await show(t, dark: dark);
      expect(find.byKey(const Key('btn_pick')), findsOneWidget);
      expect(find.text('Call recording SBI'), findsOneWidget);
      expect(find.text('2 Nov, 4:32 PM · 3:14'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);

      await transcribe(t);
      expect(calls.where((c) => c.method == 'recording.use').single.arguments, {'uri': 'content://media/external/audio/media/7'});
      expect(find.byKey(const Key('progress_bar')), findsOneWidget);
      // One paragraph holds everything heard so far.
      final para = t.widget<Text>(find.descendant(of: find.byKey(const Key('live_transcript')), matching: find.byType(Text)));
      expect(para.textSpan!.toPlainText(), 'Hello this is your bank Your account is blocked, share the OTP');

      events.add({'stage': 'done', 'pct': 100, 'report': _report});
      await t.pumpAndSettle();
      // No AI model: the keyword report, plus a pointer to the AI model.
      expect(find.byKey(const Key('risk_card')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('risk_value'))).data, '87%');
      expect(find.byKey(const Key('trigger_0')), findsOneWidget);
      expect(find.byKey(const Key('no_ai')), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const Key('row_2')), 200);
      expect(t.widget<Text>(find.byKey(const Key('row_time_2'))).data, '01:05');
      await t.scrollUntilVisible(find.byKey(const Key('btn_report')), 200);
      await t.tap(find.byKey(const Key('btn_report')));
      await t.pumpAndSettle();
      expect(find.byType(ReportScreen), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('REC_aiExplainsWholeCall_thenYesAndShareSendsWithConsent', (t) async {
    final llm = _Llm('```json\n${jsonEncode({
      'verdict': 'scam',
      'risk': 93,
      'summary': 'The caller pretended to be the bank and asked for the OTP.',
      'steps': ['Said he was from the bank', 'Asked for the OTP'],
      'flags': [{'quote': 'share the OTP', 'why': 'Banks never ask for an OTP.'}],
      'todo': ['Do not share the OTP'],
    })}\n```');
    final sender = _Sender();
    await show(t, llm: llm, sender: sender);
    await transcribe(t);
    events.add({'stage': 'done', 'pct': 100, 'report': _report});
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('ai_card')), findsOneWidget); // hand-off shown while the AI reads
    await t.pumpAndSettle();
    expect(llm.calls, 1);
    expect(find.text('The caller pretended to be the bank and asked for the OTP.'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('risk_value'))).data, '93%');
    expect(find.byKey(const Key('no_ai')), findsNothing);
    await t.scrollUntilVisible(find.byKey(const Key('flag_0')), 200);
    expect(find.text('“share the OTP”'), findsOneWidget);
    expect(find.text('00:12'), findsWidgets); // the quote was matched to its line

    await t.scrollUntilVisible(find.byKey(const Key('ans_yes')), 200);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -200)); // clear of the bottom edge
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ans_yes')));
    await t.pumpAndSettle();
    expect(find.text('Help protect others?'), findsOneWidget);
    expect(find.text('Raipur'), findsOneWidget);
    expect(sender.sent, isEmpty); // nothing leaves before the Share tap
    await t.ensureVisible(find.byKey(const Key('share_yes')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('share_yes')));
    await t.pumpAndSettle();
    final r = sender.sent.single;
    expect(r.district, 'Raipur');
    expect(r.userValidated, true);
    expect(r.llm['verdict'], 'scam');
    expect(r.toJson()['transcript'], contains('share the OTP'));
    await t.pump(const Duration(seconds: 5)); // island toast
  });

  testWidgets('REC_noThanksSendsNothing', (t) async {
    final sender = _Sender();
    await show(t, sender: sender);
    await transcribe(t);
    events.add({'stage': 'done', 'pct': 100, 'report': _report});
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('ans_no')), 200);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -200)); // clear of the bottom edge
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ans_no')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('share_no')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('share_no')));
    await t.pumpAndSettle();
    expect(sender.sent, isEmpty);
    expect(find.byKey(const Key('confirm_done')), findsOneWidget);
  });

  testWidgets('REC_noSpeechModel_centredButtonOpensSpeechModelSettings', (t) async {
    modelReady = false;
    await show(t);
    expect(find.byKey(const Key('btn_pick')), findsNothing);
    expect(find.text('First, get the speech model'), findsOneWidget);
    await t.tap(find.byKey(const Key('btn_get_model')));
    await t.pumpAndSettle();
    expect(find.byType(SpeechModelScreen), findsOneWidget);
    expect(find.byKey(const Key('sm_opt_vosk-small-hi')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 5)); // device-info timeout
  });

  testWidgets('REC_errorShowsMessage_retryGoesBackToPicking', (t) async {
    await show(t);
    events.add({'stage': 'shared', 'pct': 0});
    await t.pump();
    await t.pump();
    events.add({'stage': 'error', 'pct': 0, 'code': 'noSpeech'});
    await t.pumpAndSettle();
    expect(find.byKey(const Key('error_text')), findsOneWidget);
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('btn_pick')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
