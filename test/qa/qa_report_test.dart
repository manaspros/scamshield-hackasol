import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/screens/report_screen.dart';

import 'qa_harness.dart';

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
                'triggers': ['CBI', 'arrest warrant', 'डिजिटल अरेस्ट में हैं आप, किसी को मत बताना'],
              },
              {'tsMs': 2, 'time': '2026-11-23 10:20 IST', 'scamType': null, 'source': 'sms', 'triggers': <String>[]},
            ]
          : <Object?>[],
      'userFields': const [],
    };

/// Native-side fake with switchable behaviour per method.
class _Native {
  _Native({this.golden = const {'started': false}, this.evidence = true});
  Map<String, Object?> golden;
  final bool evidence;
  Object? dialResult = true;
  Object? openResult = true;
  Object? shareResult = true;
  Object? startResult; // null -> real-looking success
  final calls = <MethodCall>[];

  Future<Object?> handle(MethodCall c) async {
    calls.add(c);
    final a = c.arguments is Map ? c.arguments as Map : const {};
    Object? pick(Object? r) => r is Exception ? throw r : r;
    switch (c.method) {
      case 'report.pack':
        return _pack(lost: a['moneyLost'] == true, evidence: evidence);
      case 'golden.status':
        return golden;
      case 'golden.start':
        if (startResult != null) return pick(startResult);
        return golden = {'started': true, 'startMs': 1, 'remainingMs': 3600000, 'pack': _pack(lost: true, evidence: evidence)};
      case 'dial':
        return pick(dialResult);
      case 'open':
        return pick(openResult);
      case 'golden.share':
        return pick(shareResult);
    }
    return null;
  }

  List<MethodCall> named(String m) => calls.where((c) => c.method == m).toList();
}

_Native _install({Map<String, Object?>? golden, bool evidence = true}) {
  final n = _Native(golden: golden ?? const {'started': false}, evidence: evidence);
  FakeChannel('scamshield/handoff', n.handle).install();
  return n;
}

Future<void> _open(WidgetTester t, ThemeData theme, {double scale = 2.0, String lang = 'en'}) async {
  await show(t, theme, ReportScreen(initialLang: lang), scale: scale, settle: false);
  await t.pump();
  await t.pump();
}

Future<void> _choose(WidgetTester t, String key) async {
  await tapVisible(t, find.byKey(Key(key)));
  await t.pump();
}

Map<String, Object?> _running(int ms, {bool evidence = true}) =>
    {'started': true, 'startMs': 1, 'remainingMs': ms, 'pack': _pack(lost: true, evidence: evidence)};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final e in themes.entries) {
    group('report ${e.key}', () {
      testWidgets('QA_report_lostPath_goldenRunning_noOverflow_allButtonsReachable48dp_${e.key}_scale2', (t) async {
        _install(golden: _running(3_000_000));
        await _open(t, e.value());
        expect(t.takeException(), isNull);
        expect(find.text('50:00'), findsOneWidget);
        for (final k in ['path_lost', 'path_notyet', 'btn_dial_1930', 'btn_open_cybercrime.gov.in', 'btn_share']) {
          await reveal(t, find.byKey(Key(k)));
          expectTapTarget(t, find.byKey(Key(k)));
        }
        for (final k in ['scammer_number', 'amount', 'utr', 'screenshots']) {
          await reveal(t, find.byKey(Key('field_$k')));
          expectTapTarget(t, find.byKey(Key('field_$k')));
        }
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      });

      testWidgets('QA_report_goldenStartButton_reachable48dp_noOverflow_${e.key}_scale2', (t) async {
        _install();
        await _open(t, e.value());
        await _choose(t, 'path_lost');
        await reveal(t, find.byKey(const Key('golden_start')));
        expectTapTarget(t, find.byKey(const Key('golden_start')));
        expect(t.takeException(), isNull);
      });

      testWidgets('QA_report_goldenExpired_restartButtonReachable_noOverflow_${e.key}_scale2', (t) async {
        final n = _install(golden: _running(0));
        await _open(t, e.value());
        expect(find.text('00:00'), findsOneWidget);
        expect(find.text('Time is up. Still call 1930.'), findsOneWidget);
        await reveal(t, find.byKey(const Key('golden_restart')));
        expectTapTarget(t, find.byKey(const Key('golden_restart')));
        await tapVisible(t, find.byKey(const Key('golden_restart')));
        await t.pump();
        expect(n.named('golden.start').single.arguments, {'restart': true}); // restart flag only when expired
        expect(find.text('60:00'), findsOneWidget);
        expect(find.byKey(const Key('golden_restart')), findsNothing);
        await t.pumpWidget(const SizedBox());
      });

      testWidgets('QA_report_notYetPath_noOverflow_hindiLongStrings_${e.key}_scale2', (t) async {
        _install();
        await _open(t, e.value(), lang: 'hne');
        await _choose(t, 'path_notyet');
        for (final k in ['btn_open_sancharsaathi.gov.in', 'btn_dial_1930', 'field_scammer_number', 'field_screenshots']) {
          await reveal(t, find.byKey(Key(k)));
        }
        expect(find.byKey(const Key('field_amount')), findsNothing);
        expect(find.byKey(const Key('golden_start')), findsNothing); // no clock without a loss
        expect(t.takeException(), isNull);
      });
    });
  }

  group('report channel contract', () {
    testWidgets('QA_report_1930_sendsDialMethodWithExactNumber_neverCallMethod', (t) async {
      final n = _install();
      await _open(t, themes['light']!(), scale: 1.0);
      await _choose(t, 'path_notyet'); // 1930 is also on the no-loss path
      await tapVisible(t, find.byKey(const Key('btn_dial_1930')));
      await t.pump();
      final d = n.named('dial').single;
      expect(d.arguments, {'number': '1930'}); // number only: no tel: scheme, no extra keys
      expect(n.calls.map((c) => c.method).where((m) => m.toLowerCase().contains('call')), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('QA_report_portalAndChakshu_sendOpenWithFullUrl', (t) async {
      final n = _install();
      await _open(t, themes['light']!(), scale: 1.0);
      await _choose(t, 'path_lost');
      await tapVisible(t, find.byKey(const Key('btn_open_cybercrime.gov.in')));
      await _choose(t, 'path_notyet');
      await tapVisible(t, find.byKey(const Key('btn_open_sancharsaathi.gov.in')));
      await t.pump();
      expect(n.named('open').map((c) => c.arguments), [
        {'url': 'https://cybercrime.gov.in'},
        {'url': 'https://sancharsaathi.gov.in/sfc/'},
      ]);
    });

    testWidgets('QA_report_shareButton_sendsGoldenShareWithAllFourTypedFields', (t) async {
      final n = _install(golden: _running(1_800_000));
      await _open(t, themes['light']!(), scale: 1.0);
      await t.enterText(find.byKey(const Key('field_scammer_number')), '+91 98765 43210');
      await t.enterText(find.byKey(const Key('field_amount')), '25000');
      await t.enterText(find.byKey(const Key('field_utr')), 'UTR9988');
      await t.enterText(find.byKey(const Key('field_screenshots')), 'शॉट1.png, shot2.png');
      await tapVisible(t, find.byKey(const Key('btn_share')));
      await t.pump();
      expect(n.named('golden.share').single.arguments, {
        'fields': {
          'scammer_number': '+91 98765 43210',
          'amount': '25000',
          'utr': 'UTR9988',
          'screenshots': 'शॉट1.png, shot2.png',
        },
      });
      expect(find.byType(SnackBar), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('QA_report_shareButton_absentUntilGoldenHourStarted_andOnNoLossPath', (t) async {
      _install();
      await _open(t, themes['light']!(), scale: 1.0);
      await _choose(t, 'path_lost');
      expect(find.byKey(const Key('btn_share')), findsNothing);
      await _choose(t, 'path_notyet');
      expect(find.byKey(const Key('btn_share')), findsNothing);
    });
  });

  group('report empty and error states', () {
    testWidgets('QA_report_emptyEvidence_showsNoWarningsHint_andFieldsStillUsable', (t) async {
      _install(evidence: false);
      await _open(t, themes['dark']!());
      await _choose(t, 'path_lost');
      await reveal(t, find.text('No warnings found. Write the details below.'));
      expect(find.text('The app added these for you.'), findsNothing);
      await reveal(t, find.byKey(const Key('field_utr')));
      expect(t.takeException(), isNull);
    });

    testWidgets('QA_report_evidenceRows_unknownTypeAndLongTriggers_noOverflow_scale2', (t) async {
      _install();
      await _open(t, themes['light']!());
      await _choose(t, 'path_lost');
      await reveal(t, find.text('SMS')); // row with no scamType prints only the source
      await reveal(t, find.textContaining('किसी को मत बताना'));
      expect(t.takeException(), isNull);
    });

    for (final (name, err) in [
      ('platformException', PlatformException(code: 'E', message: 'boom') as Object),
      ('missingPlugin', MissingPluginException('none') as Object),
    ]) {
      testWidgets('QA_report_packFails_${name}_fallsBackToWorkingDial1930Button', (t) async {
        final calls = <MethodCall>[];
        FakeChannel('scamshield/handoff', (c) async {
          calls.add(c);
          if (c.method == 'dial') return true;
          throw err;
        }).install();
        await _open(t, themes['light']!(), scale: 2.0);
        expect(find.text('Report a scam'), findsOneWidget);
        await _choose(t, 'path_lost');
        await reveal(t, find.byKey(const Key('btn_dial_1930'))); // helpline survives a dead native side
        expectTapTarget(t, find.byKey(const Key('btn_dial_1930')));
        await tapVisible(t, find.byKey(const Key('btn_dial_1930')));
        expect(calls.where((c) => c.method == 'dial').single.arguments, {'number': '1930'});
        await reveal(t, find.text('No warnings found. Write the details below.'));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('QA_report_dialReturnsFalse_showsDialYourselfMessage', (t) async {
      final n = _install()..dialResult = false;
      await _open(t, themes['light']!(), scale: 1.0);
      await _choose(t, 'path_notyet');
      await tapVisible(t, find.byKey(const Key('btn_dial_1930')));
      await t.pump();
      expect(find.text('Could not open this. Dial 1930 yourself.'), findsOneWidget);
      expect(n.named('dial'), hasLength(1));
    });

    testWidgets('QA_report_dialThrows_showsMessage_noCrash', (t) async {
      _install().dialResult = PlatformException(code: 'NO_DIALER');
      await _open(t, themes['light']!(), scale: 1.0);
      await _choose(t, 'path_notyet');
      await tapVisible(t, find.byKey(const Key('btn_dial_1930')));
      await t.pump();
      expect(find.text('Could not open this. Dial 1930 yourself.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('QA_report_portalOpenFails_showsOpenError', (t) async {
      _install().openResult = false;
      await _open(t, themes['light']!(), scale: 1.0);
      await _choose(t, 'path_lost');
      await tapVisible(t, find.byKey(const Key('btn_open_cybercrime.gov.in')));
      await t.pump();
      expect(find.text('Could not open this. Dial 1930 yourself.'), findsOneWidget);
    });

    testWidgets('QA_report_shareFails_showsShareErrorInSelectedLanguage', (t) async {
      final n = _install(golden: _running(1_000_000))..shareResult = false;
      await _open(t, themes['light']!(), scale: 1.0, lang: 'hi');
      await tapVisible(t, find.byKey(const Key('btn_share')));
      await t.pump();
      expect(n.named('golden.share'), hasLength(1));
      expect(find.text('सबूत नहीं बन सका। फिर कोशिश करें।'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('QA_report_shareThrows_showsShareError_noCrash', (t) async {
      _install(golden: _running(1_000_000)).shareResult = PlatformException(code: 'IO');
      await _open(t, themes['light']!(), scale: 1.0);
      await tapVisible(t, find.byKey(const Key('btn_share')));
      await t.pump();
      expect(find.text('Could not build the evidence file. Try again.'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('QA_report_goldenStartFails_showsStartErrorAndNoClock_and1930StillThere', (t) async {
      final n = _install()..startResult = PlatformException(code: 'X');
      await _open(t, themes['light']!(), scale: 1.0);
      await _choose(t, 'path_lost');
      await tapVisible(t, find.byKey(const Key('golden_start')));
      await t.pump();
      expect(n.named('golden.start').single.arguments, {'restart': false});
      expect(find.text('Could not start the clock. Call 1930.'), findsOneWidget);
      expect(find.byKey(const Key('golden_timer')), findsNothing);
      expect(find.byKey(const Key('golden_start')), findsOneWidget); // can retry
      await reveal(t, find.byKey(const Key('btn_dial_1930')));
    });

    testWidgets('QA_report_goldenStartNotStarted_isTreatedAsFailure', (t) async {
      _install().startResult = {'started': false};
      await _open(t, themes['light']!(), scale: 1.0);
      await _choose(t, 'path_lost');
      await tapVisible(t, find.byKey(const Key('golden_start')));
      await t.pump();
      expect(find.text('Could not start the clock. Call 1930.'), findsOneWidget);
      expect(find.byKey(const Key('golden_timer')), findsNothing);
    });
  });

  group('golden hour clock', () {
    testWidgets('QA_golden_countsDownToZero_thenExpiredCopyAndRestart_andStopsTicking', (t) async {
      _install(golden: _running(3000));
      await _open(t, themes['light']!(), scale: 1.0);
      expect(find.text('00:03'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('00:02'), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('Time is up. Still call 1930.'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      expect(find.text('00:00'), findsOneWidget); // clamps, never negative
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('QA_golden_startFresh_sendsRestartFalse_and60MinuteClock', (t) async {
      final n = _install();
      await _open(t, themes['light']!(), scale: 1.0);
      await _choose(t, 'path_lost');
      await tapVisible(t, find.byKey(const Key('golden_start')));
      await t.pump();
      expect(n.named('golden.start').single.arguments, {'restart': false});
      expect(find.text('60:00'), findsOneWidget);
      expect(find.byKey(const Key('golden_start')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('QA_golden_switchingToNoLossPath_hidesClockButKeepsItRunningNatively', (t) async {
      final n = _install(golden: _running(3_000_000));
      await _open(t, themes['light']!(), scale: 1.0);
      expect(find.byKey(const Key('golden_timer')), findsOneWidget);
      await _choose(t, 'path_notyet');
      expect(find.byKey(const Key('golden_timer')), findsNothing);
      expect(n.named('golden.start'), isEmpty); // switching path must not restart the clock
      await t.pumpWidget(const SizedBox());
    });
  });
}
