import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/api/home_api.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/models/verdict.dart';
import 'package:scamshield/screens/knowledge_screen.dart';
import 'package:scamshield/screens/past_alerts_screen.dart';
import 'package:scamshield/theme/app_theme.dart';

final _graph = <String, Object?>{
  'empty': false,
  'brands': [
    {'brand': 'examplebank', 'types': {'MONEY_RECEIVED': 3}, 'lastMs': 1},
  ],
  'recent': [],
  'senders': [],
  'ingested': 3,
};

/// Fake 'scamshield/handoff'; records every call. graph.summary returns the empty state once deleted.
List<MethodCall> _install(WidgetTester t, {bool feedbackResult = true}) {
  final calls = <MethodCall>[];
  var deleted = false;
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), (c) async {
    calls.add(c);
    switch (c.method) {
      case 'graph.summary':
        return deleted ? {'empty': true} : _graph;
      case 'graph.delete':
        deleted = true;
        return {'ok': true};
      case 'feedback.mark':
        return feedbackResult;
    }
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), null));
  return calls;
}

Future<void> _show(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(400, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (c, child) => LangScope(notifier: AppLanguage.current, child: child!),
    theme: AppTheme.light(),
    home: Scaffold(body: home),
  ));
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppLanguage.debugSet('en'));

  Iterable<MethodCall> deletes(List<MethodCall> c) => c.where((x) => x.method == 'graph.delete');

  testWidgets('R3_KB_delete_defaultsToKeepingAlerts_thenShowsEmptyStateAndDeletedSnackbar', (t) async {
    final calls = _install(t);
    await _show(t, const KnowledgeScreen());
    await t.scrollUntilVisible(find.byKey(const Key('kn_delete')), 200);
    await t.tap(find.byKey(const Key('kn_delete')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('kn_del_confirm')));
    await t.pump(const Duration(milliseconds: 300));
    expect(deletes(calls).single.arguments, {'alerts': false});
    expect(find.text('Deleted'), findsOneWidget);
    expect(find.text('Nothing learned yet'), findsOneWidget);
  });

  testWidgets('R3_KB_delete_alsoAlertsToggleSendsAlertsTrue', (t) async {
    final calls = _install(t);
    await _show(t, const KnowledgeScreen());
    await t.scrollUntilVisible(find.byKey(const Key('kn_delete')), 200);
    await t.tap(find.byKey(const Key('kn_delete')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('kn_del_alerts')));
    await t.pump();
    await t.tap(find.byKey(const Key('kn_del_confirm')));
    await t.pump(const Duration(milliseconds: 300));
    expect(deletes(calls).single.arguments, {'alerts': true});
  });

  testWidgets('R3_KB_delete_buttonShownInEmptyStateAndDeletesAlerts', (t) async {
    final calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), (c) async {
      calls.add(c);
      return c.method == 'graph.summary' ? {'empty': true} : {'ok': true};
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), null));
    await _show(t, const KnowledgeScreen());
    expect(find.text('Nothing learned yet'), findsOneWidget);
    await t.tap(find.byKey(const Key('kn_delete')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('kn_del_alerts')));
    await t.pump();
    await t.tap(find.byKey(const Key('kn_del_confirm')));
    await t.pump(const Duration(milliseconds: 300));
    expect(deletes(calls).single.arguments, {'alerts': true});
    expect(find.text('Deleted'), findsOneWidget);
  });

  testWidgets('R3_KB_delete_cancelCallsNothing', (t) async {
    final calls = _install(t);
    await _show(t, const KnowledgeScreen());
    await t.scrollUntilVisible(find.byKey(const Key('kn_delete')), 200);
    await t.tap(find.byKey(const Key('kn_delete')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('kn_del_cancel')));
    await t.pumpAndSettle();
    expect(deletes(calls), isEmpty);
    expect(find.text('Deleted'), findsNothing);
  });

  final alert = PastAlert(id: 1, tsMs: 1234567, source: 'sms', label: RiskLabel.scam, confidence: 0.9, triggers: const ['share your OTP'], scamType: 'OTP');

  for (final safe in [true, false]) {
    testWidgets('R3_KB_feedback_${safe ? 'safe' : 'scam'}_sendsTsMsAndVerdict', (t) async {
      final calls = _install(t);
      await _show(t, AlertDetail(alert: alert));
      final k = Key(safe ? 'alert_mark_safe' : 'alert_mark_scam');
      await t.scrollUntilVisible(find.byKey(k), 200);
      await t.tap(find.byKey(k));
      await t.pump(const Duration(milliseconds: 300));
      expect(calls.single.method, 'feedback.mark');
      expect(calls.single.arguments, {'tsMs': 1234567, 'verdict': safe ? 'safe' : 'scam'});
      expect(find.text(safe ? "We'll trust this sender" : "Reported. We'll warn you if they message again"), findsOneWidget);
    });
  }

  testWidgets('R3_KB_feedback_noStoredSender_saysNothingWasSaved', (t) async {
    _install(t, feedbackResult: false);
    await _show(t, AlertDetail(alert: alert));
    await t.scrollUntilVisible(find.byKey(const Key('alert_mark_safe')), 200);
    await t.tap(find.byKey(const Key('alert_mark_safe')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Nothing to remember: this alert has no sender (calls and pasted text).'), findsOneWidget);
  });
}
