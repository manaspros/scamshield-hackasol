import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/main.dart';
import 'package:scamshield/screens/lessons_screen.dart';
import 'package:scamshield/screens/recording_screen.dart';
import 'package:scamshield/screens/report_screen.dart';

void _phone(WidgetTester tester, {String? route}) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = 2.0;
  const channel = MethodChannel('scamshield/api');
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => call.method == 'app.initialRoute' ? route : null);
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppLanguage.debugSet('hi')); // these tests assert the Hindi shell

  testWidgets('T3_11_deepLinkOpensReport', (tester) async {
    _phone(tester, route: 'report');
    await tester.pumpWidget(const ScamShieldApp());
    await tester.pump(); // post-frame callback fires the deep link
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ReportScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T3_11_deepLinkOpensRecording', (tester) async {
    _phone(tester, route: 'recording');
    await tester.pumpWidget(const ScamShieldApp());
    await tester.pump(); // post-frame callback fires the deep link
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(RecordingScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T3_11_1930EntryOpensReport', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const ScamShieldApp());
    await tester.pump();
    expect(find.byType(ReportScreen), findsNothing);

    await tester.tap(find.byKey(const Key('btn_report_1930')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ReportScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T3_11_learnTabShowsLessons', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const ScamShieldApp());
    await tester.pump();

    await tester.tap(find.byTooltip('Learn'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(LessonsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
