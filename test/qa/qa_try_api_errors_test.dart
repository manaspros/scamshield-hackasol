import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/screens/try_api_screen.dart';

import 'qa_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('QA_tryApi_nativeFailure_userMessageDoesNotExposeRawExceptionText', (t) async {
    FakeChannel('scamshield/api', (c) async => throw PlatformException(code: 'MODEL', message: 'model not loaded')).install();
    await show(t, themes['light']!(), const TryApiScreen(), scale: 1.0);
    await t.enterText(find.byType(TextField), 'hello');
    await tapVisible(t, find.byType(FilledButton));
    await t.pumpAndSettle();
    expect(find.textContaining('PlatformException('), findsNothing); // currently the screen prints '$e'
  });

  testWidgets('QA_tryApi_errorClearsAfterNextSuccessfulUpiCheck', (t) async {
    var n = 0;
    FakeChannel('scamshield/api', (c) async {
      if (c.method != 'upi.check') return null;
      if (++n == 1) throw PlatformException(code: 'X', message: 'upi parser down');
      return {'valid': false};
    }).install();
    await show(t, themes['light']!(), const TryApiScreen(), scale: 1.0);
    await tapVisible(t, find.byKey(const Key('upi_section')));
    await t.pumpAndSettle();
    for (final link in ['upi://pay?pa=a@b', 'upi://pay?pa=c@d']) {
      await reveal(t, find.byKey(const Key('upi_link_field')));
      await t.enterText(find.byKey(const Key('upi_link_field')), link);
      await tapVisible(t, find.byKey(const Key('btn_upi_check')));
      await t.pumpAndSettle();
    }
    expect(find.textContaining('upi parser down'), findsNothing); // currently the stale error stays above the new result
  });
}
