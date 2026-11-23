import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/api/signal_kinds.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/screens/live_feed_screen.dart';
import 'package:scamshield/theme/app_theme.dart';

import 'qa/qa_harness.dart';

const _kotlinSignals = 'android/app/src/main/kotlin/com/hackasol/scamshield/core/InCallSignals.kt';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AppLanguage.debugSet('hi'));

  test('LIVE_signalKinds_matchKotlinSource', () {
    final src = File(_kotlinSignals).readAsStringSync();
    final kotlin = RegExp(r'const val KIND_\w+ = "([a-z_]+)"').allMatches(src).map((m) => m.group(1)!).toSet();
    expect(kotlin, isNotEmpty);
    expect(SignalKinds.all, kotlin);
    // The exact strings the service emits today.
    expect(SignalKinds.otp, 'otp_during_call');
    expect(SignalKinds.remoteApp, 'remote_app_during_call');
  });

  for (final lang in ['en', 'hi']) {
    testWidgets('LIVE_otpCard_rendersForRealKotlinKind_$lang', (t) async {
      AppLanguage.debugSet(lang);
      final emit = fakeEvents();
      await show(t, AppTheme.light(), const LiveFeedScreen(), scale: 1.0);
      emit({'type': 'call', 'active': true});
      emit({'type': 'signal', 'kind': 'otp_during_call', 'pkg': 'com.example.sms', 'trigger': 'OTP'});
      await t.pumpAndSettle();
      expect(find.byKey(const Key('otp_alert')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('LIVE_otpCard_notShownForOtherKinds', (t) async {
    final emit = fakeEvents();
    await show(t, AppTheme.light(), const LiveFeedScreen(), scale: 1.0);
    emit({'type': 'signal', 'kind': 'remote_app_during_call', 'pkg': 'com.anydesk.anydeskandroid', 'trigger': 'AnyDesk'});
    await t.pumpAndSettle();
    expect(find.byKey(const Key('otp_alert')), findsNothing);
  });
}
