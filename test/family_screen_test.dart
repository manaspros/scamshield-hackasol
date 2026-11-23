import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/screens/family_screen.dart';
import 'package:scamshield/theme/app_theme.dart';

void main() {
  setUp(() => AppLanguage.debugSet('hi')); // these tests read the default Hindi from the app-wide language
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('scamshield/family');

  testWidgets('T5_7_codeScreen', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearAllTestValues);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
      switch (call.method) {
        case 'family.status':
          return {'paired': true};
        case 'family.code':
          return {'code': '123456', 'remainingSec': 17};
      }
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, null));

    await t.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: FamilyScreen())));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 10));
    }

    await t.scrollUntilVisible(find.byKey(const Key('family_code')), 100);
    expect(t.widget<Text>(find.byKey(const Key('family_code'))).data, '123 456');
    expect(find.textContaining('17'), findsOneWidget);
    expect(find.byKey(const Key('family_no_warning')), findsNothing);

    await t.scrollUntilVisible(find.byKey(const Key('family_no')), 100);
    await t.tap(find.byKey(const Key('family_no')));
    await t.pump();
    await t.scrollUntilVisible(find.byKey(const Key('family_no_warning')), 100);
    expect(find.byKey(const Key('family_no_warning')), findsOneWidget);
    expect(find.textContaining('फ़ोन काट दें'), findsOneWidget);
    expect(t.takeException(), isNull);

    // dispose the screen so the periodic timer is cancelled before the test ends
    await t.pumpWidget(const SizedBox());
  });
}
