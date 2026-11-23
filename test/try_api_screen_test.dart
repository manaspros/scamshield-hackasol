import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/screens/try_api_screen.dart';
import 'package:scamshield/theme/app_theme.dart';
import 'package:scamshield/widgets/status_chip.dart';

void main() {
  setUp(() => AppLanguage.debugSet('hi')); // these tests assert the Hindi-first copy
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T2_1_showsTypeAndTriggers', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Object? sent;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), (call) async {
      sent = call.arguments;
      return <Object?, Object?>{
        'text': 'OTP bata dijiye',
        'label': 'SCAM',
        'confidence': 0.9,
        'reason': 'OTP maanga ja raha hai',
        'triggers': ['OTP bata', 'turant'],
        'engine': 'rules-only',
        'latencyMs': 5,
        'source': 'paste',
        'scamType': 'OTP',
      };
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('scamshield/api'), null));

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(2.0)),
        child: const Scaffold(body: TryApiScreen()),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'OTP bata dijiye');
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // Legacy default 'manual' maps to Source.PASTE in Kotlin Source.parse (T1.1).
    expect((sent as Map)['source'], 'manual');
    // ListView is lazy and 2.0x type pushes the result down: scroll each piece into view.
    await tester.dragUntilVisible(find.byType(StatusChip), find.byType(ListView), const Offset(0, -100));
    expect(find.text('ओटीपी माँगना · OTP theft'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('verdict_why')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('verdict_why')));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.text('turant'), find.byType(ListView), const Offset(0, -200));
    expect(find.text('OTP bata'), findsOneWidget);
    expect(find.text('turant'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
