import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/api/home_api.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/main.dart';
import 'package:scamshield/models/verdict.dart';
import 'package:scamshield/profile/user_profile.dart';
import 'package:scamshield/screens/evidence_screen.dart';
import 'package:scamshield/screens/home_screen.dart';
import 'package:scamshield/screens/knowledge_screen.dart';
import 'package:scamshield/screens/onboarding_screen.dart';
import 'package:scamshield/screens/past_alerts_screen.dart';
import 'package:scamshield/theme/app_theme.dart';

/// Native side for Home, as one fake. Everything is overridable per test.
class _Native {
  _Native({
    this.paired = true,
    this.callOn = true,
    this.alerts = const [],
    this.evidence = const [],
    this.graph,
  });
  bool paired, callOn;
  List<Map<String, Object?>> alerts, evidence;
  Map<String, Object?>? graph;
  final prefs = <String, String>{};
  final calls = <String>[];

  void install(WidgetTester t) {
    final m = t.binding.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('scamshield/api'), (c) async {
      calls.add('api:${c.method}');
      return switch (c.method) {
        'serviceStatus' => {'enabled': callOn, 'connected': callOn},
        'perm.notificationsGranted' => true,
        'perm.notificationAccessGranted' => true,
        'verdicts.recent' => alerts,
        _ => null,
      };
    });
    m.setMockMethodCallHandler(const MethodChannel('scamshield/family'), (c) async => switch (c.method) {
          'family.status' => {'paired': paired},
          'family.code' => {'code': '123456', 'remainingSec': 17},
          _ => null,
        });
    m.setMockMethodCallHandler(const MethodChannel('scamshield/handoff'), (c) async {
      calls.add('handoff:${c.method}${c.arguments is Map ? ':${(c.arguments as Map)['id'] ?? (c.arguments as Map)['number'] ?? ''}' : ''}');
      return switch (c.method) {
        'evidence.make' => {'count': evidence.length, 'items': evidence},
        'graph.summary' => graph,
        'evidence.share' || 'dial' => true,
        _ => null,
      };
    });
    m.setMockMethodCallHandler(const MethodChannel('scamshield/prefs'), (c) async {
      final k = (c.arguments as Map)['key'] as String;
      if (c.method == 'setString') prefs[k] = (c.arguments as Map)['value'] as String;
      return c.method == 'getString' ? prefs[k] : null;
    });
    m.setMockMethodCallHandler(const MethodChannel('scamshield/events'), (_) async => null);
    addTearDown(() {
      for (final n in ['api', 'family', 'handoff', 'prefs', 'events']) {
        m.setMockMethodCallHandler(MethodChannel('scamshield/$n'), null);
      }
    });
  }
}

Map<String, Object?> _alert(int id, String label, double conf, int ageMin, {String type = 'OTP', String source = 'sms', List<String> triggers = const ['share your OTP']}) => {
      'id': id,
      'tsMs': DateTime.now().millisecondsSinceEpoch - ageMin * 60000,
      'source': source,
      'label': label,
      'confidence': conf,
      'scamType': type,
      'triggers': triggers,
      'engine': 'rules-only',
    };

void _phone(WidgetTester t, {double scale = 1.0}) {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1.0;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
}

Future<void> _show(WidgetTester t, Widget home, {bool dark = false}) async {
  await t.pumpWidget(MaterialApp(
    builder: (c, child) => LangScope(notifier: AppLanguage.current, child: child!),
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    home: Scaffold(body: home),
  ));
  await _settle(t);
}

// pumpAndSettle never returns while the family countdown ticks, so pump a fixed span.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _end(WidgetTester t) => t.pumpWidget(const SizedBox()); // cancels the countdown timer

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppLanguage.debugSet('en'));

  group('onboarding', () {
    testWidgets('HOME_onboarding_shownOnce_skipPersists_thenNeverAgain', (t) async {
      _phone(t);
      final n = _Native()..install(t);
      Onboarding.debugReset();
      await t.pumpWidget(const ScamShieldApp());
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('onb_step')), findsOneWidget);
      expect(find.byKey(const Key('home_hero')), findsNothing);

      await t.tap(find.byKey(const Key('onb_skip')));
      await _settle(t);
      expect(n.prefs['onboarded_v1'], '1');
      expect(find.byKey(const Key('home_hero')), findsOneWidget);
      await _end(t);

      // Next launch: the stored flag is read, onboarding never shows.
      Onboarding.debugReset();
      await t.pumpWidget(const ScamShieldApp());
      await _settle(t);
      expect(find.byKey(const Key('onb_step')), findsNothing);
      expect(find.byKey(const Key('home_hero')), findsOneWidget);
      await _end(t);
    });

    testWidgets('HOME_onboarding_fourSteps_finishLandsOnHome', (t) async {
      _phone(t);
      final n = _Native(paired: false)..install(t);
      Onboarding.debugReset();
      await t.pumpWidget(const ScamShieldApp());
      await t.pump();
      await t.pump();
      for (var i = 1; i <= 3; i++) {
        expect(t.widget<Semantics>(find.byKey(const Key('onb_step'))).properties.label, 'Step $i of 4');
        await t.tap(find.byKey(const Key('onb_next')));
        await _settle(t);
      }
      expect(t.widget<Semantics>(find.byKey(const Key('onb_step'))).properties.label, 'Step 4 of 4');
      expect(find.byKey(const Key('onb_skip')), findsNothing); // nothing left to skip
      await t.tap(find.text('Start using ScamShield'));
      await _settle(t);
      expect(n.prefs['onboarded_v1'], '1');
      expect(find.byKey(const Key('home_hero')), findsOneWidget);
      expect(find.byKey(const Key('setup_primary')), findsNothing); // the setup list is not on Home
      await _end(t);
    });

    testWidgets('HOME_onboarding_backReturnsToPreviousStep', (t) async {
      _phone(t);
      _Native().install(t);
      Onboarding.debugReset();
      await t.pumpWidget(const ScamShieldApp());
      await t.pump();
      await t.pump();
      await t.tap(find.byKey(const Key('onb_next')));
      await _settle(t);
      await t.tap(find.byKey(const Key('onb_back')));
      await _settle(t);
      expect(t.widget<Semantics>(find.byKey(const Key('onb_step'))).properties.label, 'Step 1 of 4');
      await _end(t);
    });
  });

  group('home', () {
    testWidgets('HOME_home_paired_showsLiveFamilyCodeAndHint_noSetupList', (t) async {
      _phone(t);
      _Native().install(t);
      await _show(t, const HomeScreen());
      expect(find.text("You're protected"), findsOneWidget);
      expect(find.byKey(const Key('home_fix')), findsNothing);
      await t.scrollUntilVisible(find.byKey(const Key('home_family_code')), 200);
      expect(t.widget<Text>(find.byKey(const Key('home_family_code'))).data, '123 456');
      expect(find.byKey(const Key('home_family_ask')), findsOneWidget);
      expect(find.byKey(const Key('home_family_pair')), findsNothing);
      expect(find.byKey(const Key('setup_primary')), findsNothing);
      await _end(t);
    });

    testWidgets('HOME_home_unpaired_showsPairCallToAction', (t) async {
      _phone(t);
      _Native(paired: false).install(t);
      await _show(t, const HomeScreen());
      await t.scrollUntilVisible(find.byKey(const Key('home_family_pair')), 200);
      expect(find.byKey(const Key('home_family_code')), findsNothing);
      expect(find.byKey(const Key('home_family_pair')), findsOneWidget);
      await _end(t);
    });

    testWidgets('HOME_home_criticalPermissionOff_showsOneFixRow_notTheList', (t) async {
      _phone(t);
      _Native(callOn: false).install(t);
      await _show(t, const HomeScreen());
      expect(find.text('Needs attention: Call protection is off'), findsOneWidget);
      expect(find.byKey(const Key('home_fix')), findsOneWidget);
      expect(find.byKey(const Key('setup_primary')), findsNothing);
      await t.tap(find.byKey(const Key('home_fix')));
      await _settle(t);
      expect(find.byKey(const Key('setup_primary')), findsOneWidget); // Fix opens Setup & permissions
      await _end(t);
    });

    testWidgets('HOME_home_greetingStatusAndWeekAboveTheFold_360x664', (t) async {
      _phone(t); // 664dp is what is left of an 800dp phone under the app bar and the floating bar
      t.view.physicalSize = const Size(360, 664);
      _Native().install(t);
      await _show(t, const HomeScreen());
      for (final k in ['home_greeting', 'home_hero', 'home_stat_blocked', 'home_stat_score']) {
        expect(t.getBottomLeft(find.byKey(Key(k))).dy, lessThanOrEqualTo(664), reason: k);
      }
      expect(t.takeException(), isNull);
      await _end(t);
    });

    testWidgets('HOME_home_greetsByFirstName_whenProfileHasOne', (t) async {
      _phone(t);
      _Native().install(t);
      ProfileStore.debugSet(const UserProfile(name: 'Ramesh Sahu'));
      addTearDown(ProfileStore.debugReset);
      await _show(t, HomeScreen(now: () => DateTime(2026, 11, 23, 19)));
      expect(find.text('Good evening, Ramesh'), findsOneWidget);
      expect(find.text('Monday, 23 November'), findsOneWidget);
      await _end(t);
    });

    testWidgets('HOME_home_recentAttempts_newestThree_countThisWeek_andEmptyState', (t) async {
      _phone(t);
      _Native(alerts: [
        _alert(1, 'SUSPICIOUS', 0.7, 300, type: 'KYC'),
        _alert(2, 'SCAM', 0.8, 120, type: 'OTP'),
        _alert(3, 'SCAM', 0.95, 600, type: 'KYC', source: 'caption'),
        _alert(4, 'SCAM', 0.9, 900, type: 'KYC'),
        _alert(5, 'SAFE', 0.1, 10),
        _alert(6, 'SCAM', 0.9, 60 * 24 * 10, type: 'JOB'), // 10 days ago: not this week
      ]).install(t);
      await _show(t, const HomeScreen());
      final blocked = find.descendant(of: find.byKey(const Key('home_stat_blocked')), matching: find.byType(Text)).first;
      expect(t.widget<Text>(blocked).data, '4');
      expect(find.descendant(of: find.byKey(const Key('home_stat_top')), matching: find.text('KYC')), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const Key('home_attempt_3')), 200);
      for (final id in [2, 1, 3]) {
        expect(find.byKey(Key('home_attempt_$id')), findsOneWidget, reason: '$id');
      }
      expect(find.byKey(const Key('home_attempt_4')), findsNothing); // only the newest three
      expect(find.byKey(const Key('home_attempt_5')), findsNothing); // SAFE is never an attempt
      await _end(t);

      _Native().install(t);
      await _show(t, const HomeScreen());
      await t.scrollUntilVisible(find.byKey(const Key('home_recent_empty')), 200);
      expect(find.text("No attempts this week — you're safe"), findsOneWidget);
      await _end(t);
    });

    testWidgets('HOME_home_heroFixSitsBesideStatus_notOnItsOwnRow', (t) async {
      _phone(t);
      _Native(callOn: false).install(t);
      await _show(t, const HomeScreen());
      // Fix sits beside the status text, not on a row of its own (the test font is wider than real text, so no pixel height).
      expect(t.getTopLeft(find.byKey(const Key('home_fix'))).dx, greaterThan(t.getTopRight(find.byKey(const Key('home_hero_text'))).dx - 1));
      await _end(t);
    });

    testWidgets('HOME_home_threeButtonsOpenTheirScreens', (t) async {
      _phone(t);
      _Native().install(t);
      for (final (key, type) in [
        ('home_make_evidence', EvidenceScreen),
        ('home_about_me', KnowledgeScreen),
        ('home_past_alerts', PastAlertsScreen),
      ]) {
        await _show(t, const HomeScreen());
        await t.scrollUntilVisible(find.byKey(Key(key)), 100, scrollable: find.byType(Scrollable).first);
        await t.ensureVisible(find.byKey(Key(key)));
        await t.pump();
        await t.tap(find.byKey(Key(key)));
        await _settle(t);
        expect(find.byType(type), findsOneWidget, reason: key);
        await _end(t);
      }
    });
  });

  group('past alerts', () {
    final seeded = [
      _alert(1, 'SUSPICIOUS', 0.7, 300, type: 'KYC'),
      _alert(2, 'SCAM', 0.8, 120, type: 'OTP'),
      _alert(3, 'SCAM', 0.95, 600, type: 'DIGITAL_ARREST', source: 'caption'),
      _alert(4, 'SAFE', 0.1, 10),
    ];
    double dy(WidgetTester t, int id) => t.getTopLeft(find.byKey(Key('alert_$id'))).dy;

    testWidgets('HOME_alerts_newestFirstByDefault_safeExcluded_andRowShowsTypeSourceTimeReason', (t) async {
      _phone(t);
      _Native(alerts: seeded).install(t);
      await _show(t, const PastAlertsScreen());
      expect(find.byKey(const Key('alert_4')), findsNothing);
      expect(dy(t, 2), lessThan(dy(t, 1)));
      expect(dy(t, 1), lessThan(dy(t, 3)));
      final row = find.byKey(const Key('alert_3'));
      for (final s in ['Digital arrest', 'Phone call · 10 h ago', 'share your OTP']) {
        expect(find.descendant(of: row, matching: find.text(s)), findsOneWidget, reason: s);
      }
    });

    testWidgets('HOME_alerts_filterChipsAndRiskSort', (t) async {
      _phone(t);
      _Native(alerts: seeded).install(t);
      await _show(t, const PastAlertsScreen());
      await t.tap(find.byKey(const Key('alerts_f_scam')));
      await _settle(t);
      expect(find.byKey(const Key('alert_1')), findsNothing);
      await t.tap(find.byKey(const Key('alerts_f_susp')));
      await _settle(t);
      expect(find.byKey(const Key('alert_2')), findsNothing);
      expect(find.byKey(const Key('alert_1')), findsOneWidget);
      await t.tap(find.byKey(const Key('alerts_f_all')));
      await t.tap(find.byKey(const Key('alerts_s_risk')));
      await _settle(t);
      expect(dy(t, 3), lessThan(dy(t, 2)), reason: 'higher confidence scam first');
      expect(dy(t, 2), lessThan(dy(t, 1)), reason: 'scam before suspicious');
    });

    testWidgets('HOME_alerts_rowOpensDetail_makeEvidenceForThisPassesTheId', (t) async {
      _phone(t);
      final n = _Native(alerts: seeded, evidence: [_alert(3, 'SCAM', 0.95, 600)])..install(t);
      await _show(t, const PastAlertsScreen());
      await t.tap(find.byKey(const Key('alert_3')));
      await _settle(t);
      expect(find.text('Confidence 95%'), findsOneWidget);
      await t.tap(find.byKey(const Key('alert_make_evidence')));
      await _settle(t);
      expect(n.calls, contains('handoff:evidence.make:3'));
      expect(find.byKey(const Key('evidence_done')), findsOneWidget);
    });

    testWidgets('HOME_alerts_emptyLog_showsEmptyState', (t) async {
      _phone(t);
      _Native().install(t);
      await _show(t, const PastAlertsScreen());
      expect(find.text('No alerts yet'), findsOneWidget);
    });

    test('HOME_alerts_sortAndFilter_pure', () {
      PastAlert a(int id, RiskLabel l, double c, int ts) =>
          PastAlert(id: id, tsMs: ts, source: 'sms', label: l, confidence: c, triggers: const []);
      final all = [a(1, RiskLabel.suspicious, 0.9, 5), a(2, RiskLabel.scam, 0.6, 1), a(3, RiskLabel.safe, 0.9, 9), a(4, RiskLabel.scam, 0.6, 7)];
      final flagged = filterAlerts(all);
      expect(flagged.map((e) => e.id), [1, 2, 4]);
      expect(sortAlerts(flagged, AlertSort.newest).map((e) => e.id), [4, 1, 2]);
      expect(sortAlerts(flagged, AlertSort.risk).map((e) => e.id), [4, 2, 1]);
      expect(filterAlerts(all, only: RiskLabel.suspicious).map((e) => e.id), [1]);
    });
  });

  group('evidence', () {
    testWidgets('HOME_evidence_nothingFlagged_showsEmptyState', (t) async {
      _phone(t);
      _Native().install(t);
      await _show(t, const EvidenceScreen());
      expect(find.text('Nothing to report'), findsOneWidget);
      expect(find.byKey(const Key('evidence_share')), findsNothing);
    });

    testWidgets('HOME_evidence_done_listsItems_shareWorks_dialOnlyDials', (t) async {
      _phone(t);
      final n = _Native(evidence: [_alert(2, 'SCAM', 0.8, 120), _alert(3, 'SCAM', 0.9, 30, type: 'KYC')])..install(t);
      await _show(t, const EvidenceScreen());
      expect(find.text('2 alerts saved in one file'), findsOneWidget);
      expect(find.text('OTP theft'), findsOneWidget);
      await t.tap(find.byKey(const Key('evidence_share')));
      await t.pump();
      expect(n.calls, contains('handoff:evidence.share'));
      await t.ensureVisible(find.byKey(const Key('evidence_dial')));
      await t.tap(find.byKey(const Key('evidence_dial')));
      await t.pump();
      expect(n.calls, contains('handoff:dial:1930'));
      expect(n.calls.where((c) => c.contains('call')), isEmpty);
    });

    testWidgets('HOME_evidence_nativeFailure_showsRetry', (t) async {
      _phone(t);
      _Native().install(t);
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('scamshield/handoff'), (c) async => throw PlatformException(code: 'EVIDENCE'));
      await _show(t, const EvidenceScreen());
      expect(find.text('Could not make evidence'), findsOneWidget);
    });
  });

  group('knowledge', () {
    final graph = <String, Object?>{
      'empty': false,
      'ingested': 12,
      'brands': [
        {'brand': 'examplebank', 'count': 3, 'lastMs': DateTime.now().millisecondsSinceEpoch - 3600000, 'types': {'CREDIT': 3}},
        {'brand': 'shopco', 'count': 1, 'lastMs': DateTime.now().millisecondsSinceEpoch - 86400000, 'types': {'ORDER': 1}},
      ],
      'recent': [
        {'brand': 'examplebank', 'type': 'CREDIT', 'tsMs': DateTime.now().millisecondsSinceEpoch - 3600000},
      ],
      'senders': [
        {'sender': 'AX-EXMPBK', 'count': 5, 'firstMs': 1, 'lastMs': DateTime.now().millisecondsSinceEpoch - 3600000, 'dlt': true},
      ],
      'numbers': 4,
      'upiIds': 2,
    };

    testWidgets('HOME_knowledge_showsGroupedCardsWithCountsAndDates', (t) async {
      _phone(t);
      _Native(graph: graph).install(t);
      await _show(t, const KnowledgeScreen());
      expect(find.text('Examplebank'), findsWidgets);
      expect(find.text('Money received 3'), findsOneWidget);
      expect(find.text('AX-EXMPBK'), findsOneWidget);
      expect(find.text('5 messages'), findsOneWidget);
      await t.scrollUntilVisible(find.text('4 phone numbers'), 200);
      expect(find.text('4 phone numbers'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Learned from 12 messages'), 200);
      expect(find.text('Learned from 12 messages'), findsOneWidget);
    });

    testWidgets('HOME_knowledge_personalNumbersAreOnlyCounted_noDigitRunOf6OnScreen', (t) async {
      _phone(t);
      _Native(graph: {...graph, 'personalSenders': 4, 'personalMessages': 12}).install(t);
      await _show(t, const KnowledgeScreen());
      await t.scrollUntilVisible(find.text('12 messages from 4 personal numbers'), 200);
      expect(find.text('12 messages from 4 personal numbers'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Learned from 12 messages'), 200);
      // Everything rendered, top to bottom: no phone-number-sized digit run anywhere.
      final all = <String>[];
      await t.drag(find.byType(Scrollable).first, const Offset(0, 5000));
      for (var i = 0; i < 8; i++) {
        all.addAll(t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''));
        await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await t.pump();
      }
      expect(all.where(RegExp(r'\d{6,}').hasMatch), isEmpty);
    });

    testWidgets('HOME_knowledge_emptyGraph_showsEmptyState', (t) async {
      _phone(t);
      _Native(graph: {'empty': true, 'ingested': 0, 'brands': [], 'recent': [], 'senders': [], 'numbers': 0, 'upiIds': 0}).install(t);
      await _show(t, const KnowledgeScreen());
      expect(find.text('Nothing learned yet'), findsOneWidget);
    });

    testWidgets('HOME_knowledge_nativeMissing_showsRetry', (t) async {
      _phone(t);
      _Native().install(t); // graph.summary returns null
      await _show(t, const KnowledgeScreen());
      expect(find.text('Could not load this'), findsOneWidget);
    });
  });

  group('scale', () {
    for (final dark in [false, true]) {
      for (final lang in ['en', 'hi']) {
        testWidgets('HOME_scale2_at360dp_noOverflow_${dark ? 'dark' : 'light'}_$lang', (t) async {
          _phone(t, scale: 2.0);
          AppLanguage.debugSet(lang);
          final n = _Native(
            callOn: false,
            alerts: [_alert(1, 'SCAM', 0.9, 20, type: 'COURIER_CUSTOMS', triggers: const ['customs duty', 'parcel held', 'pay now'])],
            evidence: [_alert(1, 'SCAM', 0.9, 20, type: 'COURIER_CUSTOMS')],
            graph: {
              'empty': false, 'ingested': 3, 'numbers': 1, 'upiIds': 1,
              'brands': [{'brand': 'examplebank', 'count': 2, 'lastMs': DateTime.now().millisecondsSinceEpoch, 'types': {'CREDIT': 1, 'BILL': 1}}],
              'recent': [{'brand': 'examplebank', 'type': 'OUT_FOR_DELIVERY', 'tsMs': DateTime.now().millisecondsSinceEpoch}],
              'senders': [{'sender': 'AX-EXMPBK', 'count': 2, 'firstMs': 1, 'lastMs': DateTime.now().millisecondsSinceEpoch, 'dlt': true}],
            },
          )..install(t);
          for (final paired in [true, false]) {
            n.paired = paired;
            await _show(t, const HomeScreen(), dark: dark);
            expect(t.takeException(), isNull, reason: 'home paired=$paired');
            await _end(t);
          }
          for (final w in <Widget>[
            const PastAlertsScreen(),
            AlertDetail(alert: PastAlert.fromMap(_alert(1, 'SCAM', 0.9, 20, type: 'COURIER_CUSTOMS')), api: const HomeApi()),
            const EvidenceScreen(),
            const KnowledgeScreen(),
            const OnboardingScreen(),
          ]) {
            await _show(t, w, dark: dark);
            expect(t.takeException(), isNull, reason: '${w.runtimeType}');
            await _end(t);
          }
        });
      }
    }

    testWidgets('HOME_scale2_onboardingEveryStep_noOverflow', (t) async {
      _phone(t, scale: 2.0);
      _Native().install(t);
      await _show(t, const OnboardingScreen());
      for (var i = 0; i < 3; i++) {
        expect(t.takeException(), isNull, reason: 'step ${i + 1}');
        await t.tap(find.byKey(const Key('onb_next')));
        await _settle(t);
      }
      expect(t.takeException(), isNull, reason: 'step 4');
      await _end(t);
    });
  });
}
