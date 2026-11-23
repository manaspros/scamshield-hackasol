import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/screens/try_api_screen.dart';
import 'package:scamshield/widgets/verdict_card.dart';

import 'qa_harness.dart';

Map<String, Object?> _verdict(String label, {String? type}) => {
      'text': 'x', 'label': label, 'confidence': 0.9, 'reason': 'r', 'triggers': <String>[],
      'engine': 'rules', 'latencyMs': 1, 'source': 'manual', 'scamType': ?type,
    };

Map<String, Object?> _upi({bool mismatch = false, bool collect = false, String name = 'Ravi Kumar', String hi = ''}) => {
      'valid': true,
      'payeeName': name,
      'payeeVpa': 'ra•••@oksbi',
      'amount': '500',
      'isCollect': collect,
      'mismatch': mismatch,
      'framing': collect ? 'This QR REQUESTS Rs 500 from you' : 'You will PAY Rs 500 to $name',
      'framingHi': hi.isEmpty ? 'आप $name को ₹500 भेजेंगे' : hi,
    };

class _Env {
  _Env({this.upiReply, this.scanReply, this.classifyReply, this.dialReply = true});
  Object? Function(MethodCall)? upiReply;
  Object? Function()? scanReply;
  Object? Function(MethodCall)? classifyReply;
  Object? dialReply;
  late FakeChannel api, qr, handoff;

  List<MethodCall> get upiCalls => api.named('upi.check');
}

_Env _install(_Env e) {
  Object? pick(Object? r) => r is Exception ? throw r : r;
  e.api = FakeChannel('scamshield/api', (c) async {
    if (c.method == 'upi.check') return pick(e.upiReply?.call(c) ?? <Object?, Object?>{'valid': false});
    if (c.method == 'classify') return pick(e.classifyReply?.call(c) ?? _verdict('SAFE'));
    return null;
  })..install();
  e.qr = FakeChannel('scamshield/qr', (c) async => pick(e.scanReply?.call()))..install();
  e.handoff = FakeChannel('scamshield/handoff', (c) async => pick(e.dialReply))..install();
  return e;
}

Future<void> _open(WidgetTester t, ThemeData theme, {double scale = 2.0}) async {
  await show(t, theme, const TryApiScreen(), scale: scale);
}

Future<void> _openUpi(WidgetTester t) async {
  await tapVisible(t, find.byKey(const Key('upi_section')));
  await t.pumpAndSettle();
}

Future<void> _check(WidgetTester t, String link, {String? name}) async {
  await reveal(t, find.byKey(const Key('upi_link_field')));
  await t.enterText(find.byKey(const Key('upi_link_field')), link);
  if (name != null) {
    await reveal(t, find.byKey(const Key('upi_name_field')));
    await t.enterText(find.byKey(const Key('upi_name_field')), name);
  }
  await tapVisible(t, find.byKey(const Key('btn_upi_check')));
  await t.pumpAndSettle();
}

Future<void> _analyse(WidgetTester t, String text) async {
  // the paste field is the first list item: bring it back into the (lazy) tree before typing
  final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
  pos.jumpTo(pos.minScrollExtent);
  await t.pump();
  await t.enterText(find.byType(TextField).first, text);
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pump();
  await tapVisible(t, find.byType(FilledButton));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final e in themes.entries) {
    group('upi layout ${e.key}', () {
      testWidgets('QA_upi_allActionsReachable48dp_noOverflow_mismatchAndCollectCards_${e.key}_scale2', (t) async {
        final env = _install(_Env(
          upiReply: (_) => _upi(mismatch: true, collect: true, hi: 'आप सुनीता देवी को ₹५०० भेजेंगे'),
          classifyReply: (_) => _verdict('SCAM', type: 'DIGITAL_ARREST'),
        ));
        await _open(t, e.value());
        for (final k in ['upi_section']) {
          await reveal(t, find.byKey(Key(k)));
          expectTapTarget(t, find.byKey(Key(k)));
        }
        await _openUpi(t);
        for (final k in ['btn_upi_scan', 'upi_link_field', 'upi_name_field', 'btn_upi_check']) {
          await reveal(t, find.byKey(Key(k)));
          expectTapTarget(t, find.byKey(Key(k)));
        }
        await _check(t, 'upi://pay?pa=ravi.k@oksbi&pn=Ravi%20Kumar&am=500', name: 'सुनीता देवी');
        for (final k in ['upi_card', 'upi_framing_hi', 'upi_framing_en', 'upi_vpa', 'upi_mismatch', 'upi_collect']) {
          await reveal(t, find.byKey(Key(k)));
        }
        // paste result below the card: scam advice with its own 1930 tile
        await _analyse(t, 'मैं सीबीआई से बोल रहा हूं');
        expect(env.api.named('classify'), hasLength(1));
        // two independent 1930 tiles: one in the UPI card, one in the paste result
        for (final owner in [find.byKey(const Key('upi_card')), find.byType(VerdictCard)]) {
          final tile = find.descendant(of: owner, matching: find.byKey(const Key('helpline_1930')));
          await reveal(t, tile);
          expectTapTarget(t, tile);
        }
        expect(t.takeException(), isNull);
      });
    });
  }

  group('upi check verdicts', () {
    testWidgets('QA_upi_nameMismatch_devanagariPayee_warnsAndPassesExpectedNameVerbatim', (t) async {
      final env = _install(_Env(upiReply: (_) => _upi(mismatch: true, name: 'सुनीता देवी')));
      await _open(t, themes['light']!(), scale: 1.0);
      await _openUpi(t);
      await _check(t, '  upi://pay?pa=sunita@okaxis&pn=%E0%A4%B8&am=500  ', name: ' रवि कुमार ');
      final args = env.upiCalls.single.arguments as Map;
      expect(args, {'link': 'upi://pay?pa=sunita@okaxis&pn=%E0%A4%B8&am=500', 'expectedName': 'रवि कुमार'});
      await reveal(t, find.byKey(const Key('upi_mismatch')));
      expect(find.text('Name does not match this UPI ID'), findsOneWidget);
      expect(find.text('आप सुनीता देवी को ₹500 भेजेंगे'), findsOneWidget);
      expect(find.byKey(const Key('upi_collect')), findsNothing);
      expect(find.byKey(const Key('upi_invalid')), findsNothing);
    });

    testWidgets('QA_upi_collectRequest_warnsMoneyGoesOut_notMismatch', (t) async {
      final env = _install(_Env(upiReply: (_) => _upi(collect: true)));
      await _open(t, themes['dark']!(), scale: 1.0);
      await _openUpi(t);
      await _check(t, 'upi://collect?pa=x@ybl&pn=Shop&am=500');
      expect((env.upiCalls.single.arguments as Map)['link'], startsWith('upi://collect'));
      await reveal(t, find.byKey(const Key('upi_collect')));
      expect(find.textContaining('This QR requests money'), findsOneWidget);
      expect(find.byKey(const Key('upi_mismatch')), findsNothing);
      await reveal(t, find.byKey(const Key('helpline_1930')));
    });

    testWidgets('QA_upi_cleanLink_showsFramingOnly_noWarningsNoHelpline', (t) async {
      _install(_Env(upiReply: (_) => _upi()));
      await _open(t, themes['light']!(), scale: 1.0);
      await _openUpi(t);
      await _check(t, 'upi://pay?pa=ravi.k@oksbi&pn=Ravi%20Kumar&am=500', name: 'Ravi Kumar');
      await reveal(t, find.byKey(const Key('upi_card')));
      expect(find.text('You will PAY Rs 500 to Ravi Kumar'), findsOneWidget);
      expect(find.byKey(const Key('upi_mismatch')), findsNothing);
      expect(find.byKey(const Key('upi_collect')), findsNothing);
      expect(find.byKey(const Key('helpline_1930')), findsNothing);
    });

    for (final (name, reply) in <(String, Object? Function(MethodCall))>[
      ('nativeSaysInvalid', (_) => {'valid': false}),
      ('nativeReturnsNull', (_) => null),
      ('validFieldMissing', (_) => <Object?, Object?>{'payeeName': 'x'}),
    ]) {
      testWidgets('QA_upi_malformedOrNonUpi_$name _showsInvalidNotice_noCard', (t) async {
        final env = _install(_Env(upiReply: reply));
        await _open(t, themes['light']!(), scale: 1.0);
        await _openUpi(t);
        await _check(t, 'https://evil.example/pay?pa=a@b');
        expect((env.upiCalls.single.arguments as Map)['link'], 'https://evil.example/pay?pa=a@b'); // Dart never pre-judges
        await reveal(t, find.byKey(const Key('upi_invalid')));
        expect(find.byKey(const Key('upi_card')), findsNothing);
        expect(find.byKey(const Key('helpline_1930')), findsNothing);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('QA_upi_secondCheckInvalid_replacesEarlierWarningCard', (t) async {
      var n = 0;
      _install(_Env(upiReply: (_) => ++n == 1 ? _upi(mismatch: true) : {'valid': false}));
      await _open(t, themes['light']!(), scale: 1.0);
      await _openUpi(t);
      await _check(t, 'upi://pay?pa=a@b');
      await reveal(t, find.byKey(const Key('upi_mismatch')));
      await _check(t, 'garbage');
      await reveal(t, find.byKey(const Key('upi_invalid')));
      expect(find.byKey(const Key('upi_mismatch')), findsNothing);
      expect(find.byKey(const Key('upi_card')), findsNothing);
    });

    testWidgets('QA_upi_emptyAndWhitespaceField_neverCallsNative', (t) async {
      final env = _install(_Env());
      await _open(t, themes['light']!(), scale: 1.0);
      await _openUpi(t);
      await tapVisible(t, find.byKey(const Key('btn_upi_check')));
      await _check(t, '    ');
      expect(env.upiCalls, isEmpty);
      expect(find.byKey(const Key('upi_invalid')), findsNothing);
      expect(find.byKey(const Key('upi_card')), findsNothing);
    });

    testWidgets('QA_upi_sectionToggle_hidesAndShowsFields', (t) async {
      _install(_Env());
      await _open(t, themes['light']!(), scale: 1.0);
      expect(find.byKey(const Key('upi_link_field')), findsNothing);
      await _openUpi(t);
      expect(find.byKey(const Key('upi_link_field')), findsOneWidget);
      await _openUpi(t);
      expect(find.byKey(const Key('upi_link_field')), findsNothing);
    });
  });

  group('qr scan button', () {
    testWidgets('QA_qr_scanValue_fillsFieldAndChecksTrimmedLink', (t) async {
      final env = _install(_Env(scanReply: () => '  upi://pay?pa=ravi.k@oksbi&pn=Ravi&am=500\n', upiReply: (_) => _upi(mismatch: true)));
      await _open(t, themes['light']!(), scale: 2.0);
      await _openUpi(t);
      await tapVisible(t, find.byKey(const Key('btn_upi_scan')));
      await t.pumpAndSettle();
      expect(env.qr.named('qr.scan'), hasLength(1));
      expect((env.upiCalls.single.arguments as Map)['link'], 'upi://pay?pa=ravi.k@oksbi&pn=Ravi&am=500');
      await reveal(t, find.byKey(const Key('upi_link_field')));
      expect(t.widget<TextField>(find.byKey(const Key('upi_link_field'))).controller!.text, 'upi://pay?pa=ravi.k@oksbi&pn=Ravi&am=500');
      await reveal(t, find.byKey(const Key('upi_mismatch')));
    });

    testWidgets('QA_qr_nonUpiPayload_stillGoesToNativeAndShowsInvalid', (t) async {
      final env = _install(_Env(scanReply: () => 'https://example.com/menu'));
      await _open(t, themes['dark']!(), scale: 1.0);
      await _openUpi(t);
      await tapVisible(t, find.byKey(const Key('btn_upi_scan')));
      await t.pumpAndSettle();
      expect((env.upiCalls.single.arguments as Map)['link'], 'https://example.com/menu');
      await reveal(t, find.byKey(const Key('upi_invalid')));
    });

    for (final (name, value) in <(String, String?)>[('cancelled', null), ('emptyString', ''), ('whitespace', ' \n ')]) {
      testWidgets('QA_qr_scan_$name _noCheckNoErrorFieldUntouched', (t) async {
        final env = _install(_Env(scanReply: () => value));
        await _open(t, themes['light']!(), scale: 1.0);
        await _openUpi(t);
        await tapVisible(t, find.byKey(const Key('btn_upi_scan')));
        await t.pumpAndSettle();
        expect(env.qr.named('qr.scan'), hasLength(1));
        expect(env.upiCalls, isEmpty);
        expect(find.byKey(const Key('upi_invalid')), findsNothing);
        expect(find.textContaining('स्कैनर'), findsNothing);
        expect(t.widget<TextField>(find.byKey(const Key('upi_link_field'))).controller!.text, isEmpty);
      });
    }

    testWidgets('QA_qr_unavailable_showsBilingualPasteInsteadHint_noCheck_noCrash', (t) async {
      final env = _install(_Env(scanReply: () => PlatformException(code: 'UNAVAILABLE', message: 'module missing')));
      await _open(t, themes['light']!(), scale: 2.0);
      await _openUpi(t);
      await tapVisible(t, find.byKey(const Key('btn_upi_scan')));
      await t.pumpAndSettle();
      await reveal(t, find.textContaining('QR स्कैनर उपलब्ध नहीं है'));
      expect(find.textContaining('QR scanner not available'), findsOneWidget);
      expect(find.textContaining('module missing'), findsNothing); // generic hint, not the raw cause
      expect(env.upiCalls, isEmpty);
      // fallback path still works: paste the link by hand
      await reveal(t, find.byKey(const Key('upi_link_field')));
      expect(t.takeException(), isNull);
    });

    testWidgets('QA_qr_scanChannelNotRegistered_tapDoesNotThrow_noCheck', (t) async {
      final env = _install(_Env());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('scamshield/qr'), null); // non-Android: nobody answers
      await _open(t, themes['light']!(), scale: 1.0);
      await _openUpi(t);
      await tapVisible(t, find.byKey(const Key('btn_upi_scan')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(env.upiCalls, isEmpty);
    });

    testWidgets('QA_qr_permissionDenied_otherPlatformError_showsItsMessage', (t) async {
      final env = _install(_Env(scanReply: () => PlatformException(code: 'PERMISSION_DENIED', message: 'Camera permission denied')));
      await _open(t, themes['light']!(), scale: 1.0);
      await _openUpi(t);
      await tapVisible(t, find.byKey(const Key('btn_upi_scan')));
      await t.pumpAndSettle();
      expect(find.text('जाँच नहीं हो पाई, फिर कोशिश करें'), findsOneWidget);
      expect(find.text('दोबारा जाँचें'), findsOneWidget); // retry action
      expect(find.textContaining('Camera permission denied'), findsNothing); // raw detail never shown
      expect(env.upiCalls, isEmpty);
      expect(t.takeException(), isNull);
    });
  });

  group('paste result advice', () {
    testWidgets('QA_paste_scamResult_showsAdviceAndScamTypeChip_1930SendsDialNumber', (t) async {
      final env = _install(_Env(classifyReply: (_) => _verdict('SCAM', type: 'DIGITAL_ARREST')));
      await _open(t, themes['light']!(), scale: 1.0);
      await _analyse(t, 'मैं सीबीआई से बोल रहा हूं, आप डिजिटल अरेस्ट में हैं');
      await reveal(t, find.text('घबराएँ नहीं। अभी यह करें:'));
      expect(find.text('पैसे न भेजें, कॉल काट दें'), findsOneWidget);
      expect(find.text('OTP या PIN किसी को न बताएँ'), findsOneWidget);
      expect(find.text('डिजिटल अरेस्ट · Digital arrest'), findsOneWidget);
      await tapVisible(t, find.byKey(const Key('helpline_1930')));
      await t.pump();
      expect(env.handoff.calls.map((c) => c.method), ['dial']);
      expect(env.handoff.calls.single.arguments, {'number': '1930'});
      expect(env.api.named('upi.check'), isEmpty); // no link in the text
    });

    testWidgets('QA_paste_suspiciousResult_showsSuspiciousAdviceAndHelpline', (t) async {
      _install(_Env(classifyReply: (_) => _verdict('SUSPICIOUS')));
      await _open(t, themes['dark']!(), scale: 1.0);
      await _analyse(t, 'SBI se bol raha hoon, aapka KYC update pending hai');
      await reveal(t, find.text('जल्दबाज़ी न करें, कॉल काट दें'));
      expect(find.text('पहले अपने परिवार से पूछें'), findsOneWidget);
      expect(find.text('पैसे न भेजें, कॉल काट दें'), findsNothing);
      await reveal(t, find.byKey(const Key('helpline_1930')));
    });

    testWidgets('QA_paste_safeResult_noAdviceNoHelplineNoChip', (t) async {
      _install(_Env(classifyReply: (_) => _verdict('SAFE', type: 'OTP')));
      await _open(t, themes['light']!(), scale: 1.0);
      await _analyse(t, 'Beta khana kha liya? Kal shaam ko milte hain');
      expect(find.text('घबराएँ नहीं। अभी यह करें:'), findsNothing);
      expect(find.byKey(const Key('helpline_1930')), findsNothing);
      expect(find.textContaining('OTP theft'), findsNothing); // type chip only for warnings
    });

    testWidgets('QA_paste_unknownScamType_noChipButAdviceStays', (t) async {
      _install(_Env(classifyReply: (_) => _verdict('SCAM', type: 'FUTURE_TYPE')));
      await _open(t, themes['light']!(), scale: 1.0);
      await _analyse(t, 'x y z');
      await reveal(t, find.byKey(const Key('helpline_1930')));
      expect(find.textContaining('FUTURE_TYPE'), findsNothing);
    });

    testWidgets('QA_paste_1930DialFails_showsOpenErrorSnack', (t) async {
      final env = _install(_Env(classifyReply: (_) => _verdict('SCAM'), dialReply: false));
      await _open(t, themes['light']!(), scale: 1.0);
      await _analyse(t, 'OTP bata do');
      await tapVisible(t, find.byKey(const Key('helpline_1930')));
      await t.pump();
      expect(env.handoff.named('dial'), hasLength(1));
      expect(find.text('यह नहीं खुल सका। 1930 खुद डायल करें।'), findsOneWidget);
    });

    testWidgets('QA_paste_1930DialChannelMissing_noCrash', (t) async {
      _install(_Env(classifyReply: (_) => _verdict('SCAM'), dialReply: MissingPluginException('none')));
      await _open(t, themes['light']!(), scale: 1.0);
      await _analyse(t, 'OTP bata do');
      await tapVisible(t, find.byKey(const Key('helpline_1930')));
      await t.pump();
      expect(find.text('यह नहीं खुल सका। 1930 खुद डायल करें।'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('QA_paste_textWithUpiLink_runsUpiCheckOnExtractedLinkOnly_uppercaseSchemeToo', (t) async {
      final env = _install(_Env(classifyReply: (_) => _verdict('SCAM'), upiReply: (_) => _upi(collect: true)));
      await _open(t, themes['light']!(), scale: 1.0);
      await _analyse(t, 'Refund ke liye scan karein UPI://collect?pa=a@b&am=9 turant, dhanyavaad');
      final args = env.upiCalls.single.arguments as Map;
      expect(args['link'], 'UPI://collect?pa=a@b&am=9'); // stops at whitespace
      expect(args['expectedName'], '');
      await reveal(t, find.byKey(const Key('upi_collect')));
    });

    testWidgets('QA_paste_upiCheckFails_showsErrorButKeepsTextVerdict', (t) async {
      _install(_Env(
          classifyReply: (_) => _verdict('SCAM'),
          upiReply: (_) => PlatformException(code: 'X', message: 'upi parser down')));
      await _open(t, themes['light']!(), scale: 1.0);
      await _analyse(t, 'pay upi://pay?pa=a@b now');
      expect(find.text('जाँच नहीं हो पाई, फिर कोशिश करें'), findsOneWidget);
      expect(find.text('दोबारा जाँचें'), findsOneWidget); // retry action
      expect(find.textContaining('upi parser down'), findsNothing); // raw detail never shown
      await reveal(t, find.byKey(const Key('helpline_1930')));
      expect(find.byKey(const Key('upi_card')), findsNothing);
    });
  });
}
