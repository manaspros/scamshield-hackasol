import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/screens/try_api_screen.dart';
import 'package:scamshield/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T4_2_mismatchWarning', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final apiCalls = <MethodCall>[];
    final handoffCalls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), (call) async {
      apiCalls.add(call);
      return <Object?, Object?>{
        'valid': true,
        'payeeName': 'Ravi Kumar',
        'payeeVpa': 'ra•••@oksbi',
        'amount': '500',
        'isCollect': false,
        'mismatch': true,
        'framing': 'You will PAY Rs 500 to Ravi Kumar',
        'framingHi': 'आप Ravi Kumar को ₹500 भेजेंगे',
      };
    });
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), (call) async {
      handoffCalls.add(call);
      return true;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), null);
    });

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(2.0)),
        child: const Scaffold(body: TryApiScreen()),
      ),
    ));

    // ListView is lazy and 2.0x type pushes things down: scroll each target into view first.
    // ensureVisible animates: settle before tapping, or the tap lands on the pre-scroll position.
    Future<void> reveal(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
    }

    await reveal(find.byKey(const Key('upi_section')));
    await tester.tap(find.byKey(const Key('upi_section')));
    await tester.pumpAndSettle();

    await reveal(find.byKey(const Key('upi_link_field')));
    await tester.enterText(find.byKey(const Key('upi_link_field')), 'upi://pay?pa=ravi.k@oksbi&pn=Ravi%20Kumar&am=500');
    await reveal(find.byKey(const Key('upi_name_field')));
    await tester.enterText(find.byKey(const Key('upi_name_field')), 'Sunita Devi');
    await reveal(find.byKey(const Key('btn_upi_check')));
    await tester.tap(find.byKey(const Key('btn_upi_check')));
    await tester.pumpAndSettle();

    final check = apiCalls.singleWhere((c) => c.method == 'upi.check');
    expect((check.arguments as Map)['link'], startsWith('upi://pay?'));
    expect((check.arguments as Map)['expectedName'], 'Sunita Devi');

    await reveal(find.byKey(const Key('upi_card')));
    expect(find.text('आप Ravi Kumar को ₹500 भेजेंगे'), findsOneWidget);
    expect(find.text('You will PAY Rs 500 to Ravi Kumar'), findsOneWidget);
    await reveal(find.byKey(const Key('upi_vpa')));
    expect(find.textContaining('ra•••@oksbi'), findsOneWidget);
    await reveal(find.byKey(const Key('upi_mismatch')));
    expect(find.byKey(const Key('upi_mismatch')), findsOneWidget);
    expect(find.text('Name does not match this UPI ID'), findsOneWidget);
    expect(find.byKey(const Key('upi_collect')), findsNothing);

    await reveal(find.byKey(const Key('helpline_1930')));
    expect(find.text('1930 पर कॉल करें'), findsOneWidget);
    await tester.tap(find.byKey(const Key('helpline_1930')));
    await tester.pumpAndSettle();
    final dial = handoffCalls.singleWhere((c) => c.method == 'dial');
    expect((dial.arguments as Map)['number'], '1930');

    expect(tester.takeException(), isNull);
  });

  testWidgets('T4_3_scanFillsLinkAndChecks', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const scanned = 'upi://pay?pa=ravi.k@oksbi&pn=Ravi%20Kumar&am=500';
    final apiCalls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/qr'), (call) async => scanned);
    messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), (call) async {
      apiCalls.add(call);
      return <Object?, Object?>{'valid': false};
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/qr'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('scamshield/api'), null);
    });

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(2.0)),
        child: const Scaffold(body: TryApiScreen()),
      ),
    ));

    Future<void> reveal(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
    }

    await reveal(find.byKey(const Key('upi_section')));
    await tester.tap(find.byKey(const Key('upi_section')));
    await tester.pumpAndSettle();
    await reveal(find.byKey(const Key('btn_upi_scan')));
    await tester.tap(find.byKey(const Key('btn_upi_scan')));
    await tester.pumpAndSettle();

    final check = apiCalls.singleWhere((c) => c.method == 'upi.check');
    expect((check.arguments as Map)['link'], scanned);
    await reveal(find.byKey(const Key('upi_link_field')));
    expect(tester.widget<TextField>(find.byKey(const Key('upi_link_field'))).controller!.text, scanned);
    expect(tester.takeException(), isNull);
  });
}
