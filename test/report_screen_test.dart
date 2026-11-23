import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/api/llm_api.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/profile/user_profile.dart';
import 'package:scamshield/report/report_chat_engine.dart';
import 'package:scamshield/report/report_history.dart';
import 'package:scamshield/screens/report_screen.dart';
import 'package:scamshield/theme/app_theme.dart';

const _channel = MethodChannel('scamshield/handoff');
const _speech = MethodChannel('scamshield/speech');

Map<String, Object?> _pack({required bool lost, bool evidence = true}) => {
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
      'evidence': evidence
          ? [
              {
                'tsMs': 1,
                'time': '2026-11-23 10:15 IST',
                'scamType': 'DIGITAL_ARREST',
                'source': 'caption',
                'triggers': ['CBI', 'arrest warrant'],
              },
            ]
          : const [],
      'userFields': const [],
    };

/// Fake native side: records every call and answers like HandoffChannel.kt / SpeechChannel.kt.
class _Fake {
  final calls = <MethodCall>[];
  Map<String, Object?> golden = {'started': false};
  bool evidence = true;
  Object? picked = [
    {'path': '/no/such/shot.png', 'name': 'shot.png', 'mime': 'image/png', 'size': 10},
  ];
  Object? speechStart = {'mode': 'intent', 'text': '15000 rupees'};

  Future<Object?> handle(MethodCall c) async {
    calls.add(c);
    final args = c.arguments is Map ? c.arguments as Map : const {};
    switch (c.method) {
      case 'report.pack':
        return _pack(lost: args['moneyLost'] == true, evidence: evidence);
      case 'golden.status':
        return golden;
      case 'golden.start':
        return golden = {'started': true, 'startMs': 1, 'remainingMs': 3600000, 'pack': _pack(lost: true, evidence: evidence)};
      case 'attach.pick':
        return picked;
      case 'start':
        return speechStart;
      case 'dial':
      case 'dial.contact':
      case 'open':
      case 'golden.share':
        return true;
    }
    return null;
  }

  List<MethodCall> named(String m) => calls.where((c) => c.method == m).toList();
}

Future<_Fake> _setup(WidgetTester t, {double scale = 2.0}) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1.0;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
  final fake = _Fake();
  final m = t.binding.defaultBinaryMessenger;
  m.setMockMethodCallHandler(_channel, fake.handle);
  m.setMockMethodCallHandler(_speech, fake.handle);
  addTearDown(() {
    m.setMockMethodCallHandler(_channel, null);
    m.setMockMethodCallHandler(_speech, null);
  });
  return fake;
}

Future<void> _show(WidgetTester t, {UserProfile profile = UserProfile.empty, ThemeData? theme}) async {
  await t.pumpWidget(MaterialApp(
    theme: theme ?? AppTheme.light(),
    home: Scaffold(body: ReportScreen(profile: profile, llm: null)),
  ));
  await t.pump();
  await t.pump();
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump();
  await t.pump();
  await t.pump(const Duration(milliseconds: 400)); // scroll-to-end animation
}

Future<void> _say(WidgetTester t, String words) async {
  await t.enterText(find.byKey(const Key('chat_input')), words);
  await t.pump();
  await _tap(t, find.byKey(const Key('btn_send')));
}

void main() {
  setUp(() {
    AppLanguage.debugSet('hi'); // the chat speaks the app-wide language
    ReportHistory.debugReset();
    LlmStatus.ready.value = false;
  });

  testWidgets('no language chips: the report follows the app language from the top bar', (t) async {
    await _setup(t);
    await _show(t);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(const Key('lang_en')), findsNothing);
    expect(find.text('मेरे पैसे कट गए'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('lost money: clock starts, bot shows the caught warning and asks in Hindi', (t) async {
    final fake = await _setup(t, scale: 1.0);
    await _show(t);
    await _tap(t, find.byKey(const Key('path_lost')));
    expect(fake.named('report.pack').single.arguments, {'moneyLost': true});
    expect(fake.named('golden.start').single.arguments, {'restart': false});
    expect(find.byKey(const Key('golden_timer')), findsOneWidget);
    expect(find.text('60:00'), findsOneWidget);
    expect(find.textContaining('डिजिटल अरेस्ट'), findsOneWidget);
    expect(find.textContaining('arrest warrant'), findsOneWidget);
    expect(find.text('क्या आप इसी की शिकायत करना चाहते हैं?'), findsOneWidget);

    await _tap(t, find.byKey(const Key('chip_yes')));
    expect(find.text('हाँ, यही'), findsWidgets); // the user's answer bubble
    expect(find.text('यह कब हुआ?'), findsOneWidget); // next: when it happened
    expect(t.takeException(), isNull);
  });

  testWidgets('full scripted chat fills the evidence file, attachments included', (t) async {
    final fake = await _setup(t, scale: 1.0);
    AppLanguage.debugSet('en');
    await _show(t);
    await _tap(t, find.byKey(const Key('path_lost')));
    await _tap(t, find.byKey(const Key('chip_yes'))); // confirm the caught warning
    await _tap(t, find.byKey(const Key('chip_today')));
    await _say(t, 'earnfast@ybl');
    await _tap(t, find.byKey(const Key('chip_gpay')));
    await _say(t, '₹15,000');
    await _tap(t, find.byKey(const Key('chip_yes'))); // shared an OTP
    expect(find.textContaining('This happens to many people'), findsOneWidget);
    await _say(t, '123456789012');
    await _tap(t, find.byKey(const Key('chip_attach')));
    expect(fake.named('attach.pick'), hasLength(1));
    expect(find.text('1 file(s) added'), findsOneWidget);
    await _tap(t, find.byKey(const Key('chip_done')));

    expect(find.byKey(const Key('report_summary')), findsOneWidget);
    expect(find.text('Your report is ready'), findsOneWidget);
    expect(find.text('₹15,000 via Google Pay'), findsOneWidget);
    expect(find.text('earnfast@ybl'), findsWidgets);
    expect(find.byKey(const Key('btn_open_cybercrime.gov.in')), findsOneWidget);

    await _tap(t, find.byKey(const Key('btn_share')));
    final share = fake.named('golden.share').single.arguments as Map;
    final fields = share['fields'] as Map;
    expect(fields['scammer_number'], 'earnfast@ybl');
    expect(fields['amount'], '15000');
    expect(fields['utr'], '123456789012');
    expect(fields['screenshots'], 'shot.png');
    expect(share['attachments'], ['/no/such/shot.png']);
    expect(t.takeException(), isNull);
  });

  testWidgets('summary can be edited by hand', (t) async {
    final fake = await _setup(t, scale: 1.0);
    AppLanguage.debugSet('en');
    fake.evidence = false;
    await _show(t);
    await _tap(t, find.byKey(const Key('path_notyet')));
    for (var i = 0; i < 6 && find.byKey(const Key('report_summary')).evaluate().isEmpty; i++) {
      final chips = find.byWidgetPredicate((w) => w is OutlinedButton && '${w.key}'.contains('chip_'));
      await _tap(t, chips.last);
    }
    expect(find.byKey(const Key('report_summary')), findsOneWidget);
    expect(find.byKey(const Key('btn_share')), findsNothing); // no golden-hour case without a loss
    expect(find.byKey(const Key('btn_open_sancharsaathi.gov.in')), findsOneWidget);
    await _tap(t, find.byKey(const Key('btn_edit_report')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('field_utr')), findsNothing); // amount / UTR only after a loss
    await t.enterText(find.byKey(const Key('field_scammer_number')), '9876543210');
    await t.tap(find.byKey(const Key('btn_save_edit')));
    await t.pumpAndSettle();
    expect(find.text('9876543210'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('senior persona gets simpler questions and senior scam types', (t) async {
    final fake = await _setup(t, scale: 1.0);
    AppLanguage.debugSet('en');
    fake.evidence = false;
    await _show(t, profile: UserProfile(dob: DateTime(1958, 1, 1), gender: Gender.female));
    await _tap(t, find.byKey(const Key('path_lost')));
    expect(find.text('Who did the caller say they were?'), findsOneWidget);
    expect(find.byKey(const Key('chip_PENSION')), findsOneWidget);
    await t.dragUntilVisible(find.textContaining('one easy question at a time'), find.byType(ListView), const Offset(0, 200));
    expect(find.textContaining('one easy question at a time'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('voice answer (Google recogniser) is sent as a spoken bubble in the app language', (t) async {
    final fake = await _setup(t, scale: 1.0);
    AppLanguage.debugSet('en');
    fake.evidence = false;
    await _show(t);
    await _tap(t, find.byKey(const Key('path_lost')));
    await _tap(t, find.byKey(const Key('chip_KYC')));
    await _tap(t, find.byKey(const Key('chip_call')));
    await _tap(t, find.byKey(const Key('btn_mic')));
    expect((fake.named('start').single.arguments as Map)['locale'], 'en-IN');
    expect(find.text('15000 rupees'), findsOneWidget);
    expect(find.text('Spoken'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('switching the app language re-renders scripted bot lines live', (t) async {
    await _setup(t, scale: 1.0);
    await _show(t);
    await _tap(t, find.byKey(const Key('path_lost')));
    expect(find.text('क्या आप इसी की शिकायत करना चाहते हैं?'), findsOneWidget);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: LangScope(notifier: AppLanguage.current, child: const Scaffold(body: ReportScreen(llm: null))),
    ));
    AppLanguage.debugSet('en');
    await t.pump();
    await t.pump();
    expect(find.text('I lost money'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('dial is dial, not call', (t) async {
    final fake = await _setup(t);
    await _show(t);
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

  test('strings complete', () {
    final keys = ReportStrings.en.m.keys.toSet();
    expect(ReportStrings.hi.m.keys.toSet(), keys);
    expect(ReportStrings.hne.m.keys.toSet(), keys);
  });

  testWidgets('golden hour resumes after a rebuild and can restart when expired', (t) async {
    final fake = await _setup(t);
    fake.golden = {'started': true, 'startMs': 1, 'remainingMs': 3000000, 'pack': _pack(lost: true)};
    await _show(t);
    expect(find.text('50:00'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    expect(find.text('49:55'), findsOneWidget);
    expect(fake.named('golden.start'), isEmpty);

    await t.pumpWidget(const SizedBox());
    fake.golden = {'started': true, 'startMs': 1, 'remainingMs': 0, 'pack': _pack(lost: true)};
    await _show(t);
    expect(find.text('00:00'), findsOneWidget);
    await _tap(t, find.byKey(const Key('golden_restart')));
    expect(fake.named('golden.start').single.arguments, {'restart': true});
    expect(find.text('60:00'), findsOneWidget);

    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('androidx.core.content.FileProvider'));
    final paths = File('android/app/src/main/res/xml/file_paths.xml').readAsStringSync();
    expect(paths, contains('<cache-path name="evidence" path="evidence/"'));
    expect(paths, isNot(contains('external')));

    await t.pumpWidget(const SizedBox()); // cancels the periodic timer
    expect(t.takeException(), isNull);
  });

  testWidgets('dark theme at 2x text: whole chat, no overflow', (t) async {
    await _setup(t);
    await _show(t, theme: AppTheme.dark(), profile: UserProfile(dob: DateTime(1958, 1, 1)));
    await _tap(t, find.byKey(const Key('path_lost')));
    await _tap(t, find.byKey(const Key('chip_yes')));
    await _say(t, '9876543210');
    expect(t.takeException(), isNull);
  });

  testWidgets('history: answers are saved, a new report starts clean, and the old one reopens with its chat', (t) async {
    final fake = await _setup(t, scale: 1.0);
    AppLanguage.debugSet('en');
    fake.evidence = false;
    await _show(t);
    await _tap(t, find.byKey(const Key('path_notyet')));
    await _tap(t, find.byKey(const Key('chip_KYC')));
    expect(ReportHistory.items.value, hasLength(1));
    expect(ReportHistory.items.value.single.scamType, 'KYC');

    await _tap(t, find.byKey(const Key('btn_new_report')));
    expect(find.byKey(const Key('chat_input')), findsNothing); // back to the two paths

    await _tap(t, find.byKey(const Key('btn_history')));
    await t.pumpAndSettle();
    expect(find.text('Past reports'), findsOneWidget);
    expect(find.text('Bank / KYC'), findsWidgets);
    expect(find.text('Unfinished'), findsOneWidget);
    await t.tap(find.byKey(Key('hist_${ReportHistory.items.value.single.id}')));
    await t.pumpAndSettle();
    expect(find.textContaining('Your earlier report is open'), findsOneWidget);
    expect(find.text('How did the scammer contact you?'), findsOneWidget); // carries on where it stopped
    expect(t.takeException(), isNull);
  });

  testWidgets('history: delete removes a report', (t) async {
    final fake = await _setup(t, scale: 1.0);
    AppLanguage.debugSet('en');
    fake.evidence = false;
    await _show(t);
    await _tap(t, find.byKey(const Key('path_notyet')));
    await _tap(t, find.byKey(const Key('chip_OTP')));
    await _tap(t, find.byKey(const Key('btn_new_report')));
    await _tap(t, find.byKey(const Key('btn_history')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('hist_del_${ReportHistory.items.value.single.id}')));
    await t.pumpAndSettle();
    expect(ReportHistory.items.value, isEmpty);
    expect(find.text('No past reports yet.'), findsOneWidget);
  });

  testWidgets('with a model loaded, Gemma writes the question and its options; tapping one fills that fact', (t) async {
    final fake = await _setup(t, scale: 1.0);
    AppLanguage.debugSet('en');
    fake.evidence = false;
    LlmStatus.ready.value = true;
    final llm = _ScriptedLlm([
      '{"ask": "scam_type", "question": "Who did the caller pretend to be?", "options": ["Police officer", "Bank staff"]}',
      '{"extracted": {"channel": "video call"}, "ask": "when", "question": "When did they call you?", "options": ["Today", "Yesterday"]}',
    ]);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: ReportScreen(profile: UserProfile.empty, llm: ReportChatLlm(client: llm))),
    ));
    await t.pump();
    await t.pump();
    await _tap(t, find.byKey(const Key('path_notyet')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Who did the caller pretend to be?'), findsOneWidget);
    expect(find.text('Police officer'), findsOneWidget);
    await _tap(t, find.text('Police officer'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('When did they call you?'), findsOneWidget); // channel came from the model's extraction
    expect(llm.prompts.last, contains('scam_type: Police officer'));
    expect(llm.prompts.last, contains('Person: Police officer'));
    LlmStatus.ready.value = false;
    expect(t.takeException(), isNull);
  });

  testWidgets('a bad model reply falls back to the scripted question', (t) async {
    final fake = await _setup(t, scale: 1.0);
    AppLanguage.debugSet('en');
    fake.evidence = false;
    LlmStatus.ready.value = true;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: ReportScreen(profile: UserProfile.empty, llm: ReportChatLlm(client: _ScriptedLlm(['nonsense'])))),
    ));
    await t.pump();
    await t.pump();
    await _tap(t, find.byKey(const Key('path_notyet')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('What kind of scam was it?'), findsOneWidget);
    expect(find.byKey(const Key('chip_KYC')), findsOneWidget);
    LlmStatus.ready.value = false;
  });

  testWidgets('the 1930 button stays above the system navigation bar', (t) async {
    await _setup(t, scale: 1.0);
    t.view.padding = const FakeViewPadding(bottom: 48);
    t.view.viewPadding = const FakeViewPadding(bottom: 48);
    await _show(t);
    final bottom = t.getBottomLeft(find.byKey(const Key('btn_dial_1930'))).dy;
    expect(bottom, lessThanOrEqualTo(800 - 48));
  });
}

/// Answers model prompts from a list, in order; records the prompts.
class _ScriptedLlm implements LlmClient {
  _ScriptedLlm(this.replies);
  final List<String> replies;
  final prompts = <String>[];
  @override
  Future<bool> ready() async => true;
  @override
  Future<String?> generate(String prompt, {double temperature = 0.8}) async {
    prompts.add(prompt);
    return prompts.length <= replies.length ? replies[prompts.length - 1] : null;
  }
}
