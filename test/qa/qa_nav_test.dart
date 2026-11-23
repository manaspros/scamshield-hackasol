import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/main.dart';
import 'package:scamshield/screens/family_screen.dart';
import 'package:scamshield/screens/lessons_screen.dart';
import 'package:scamshield/screens/live_feed_screen.dart';
import 'package:scamshield/screens/report_screen.dart';
import 'package:scamshield/screens/settings_screen.dart';
import 'package:scamshield/screens/setup_screen.dart';
import 'package:scamshield/screens/try_api_screen.dart';

import 'package:scamshield/widgets/action_tile.dart';

import 'qa_harness.dart';

const _tabs = [
  ('सेटअप', 'Setup'),
  ('जाँच', 'Check'),
  ('लाइव', 'Live'),
  ('सीखें', 'Learn'),
  ('मदद', 'Help'),
];

/// Native side for the whole app shell. [routes] is handed out once each, then null (like MainActivity).
class _App {
  _App(this.routes);
  final List<Object?> routes;
  int routeAsks = 0;

  Future<Object?> api(MethodCall c) async {
    switch (c.method) {
      case 'app.initialRoute':
        routeAsks++;
        if (routes.isEmpty) return null;
        final r = routes.removeAt(0);
        if (r is Exception) throw r;
        return r;
      case 'serviceStatus':
        return {'enabled': true, 'connected': true};
      case 'modelStatus':
        return {'status': 'READY', 'message': 'ok', 'path': '/m', 'sizeMb': 555};
      case 'downloadStatus':
        return {'status': 'IDLE'};
      case 'micPermission':
      case 'perm.notificationsGranted':
      case 'perm.notificationAccessGranted':
        return true;
      case 'getSettings':
        return {'useLlm': true};
    }
    return null;
  }
}

/// Boots the real app at 360x740, text scale 2.0, in [dark] or light.
Future<_App> _boot(WidgetTester t, {bool dark = false, List<Object?> routes = const []}) async {
  t.view.physicalSize = const Size(360, 740);
  t.view.devicePixelRatio = 1.0;
  t.platformDispatcher.textScaleFactorTestValue = 2.0;
  t.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
  final app = _App([...routes]);
  FakeChannel('scamshield/api', app.api).install();
  FakeChannel('scamshield/family', (c) async => c.method == 'family.status' ? {'paired': false} : null).install();
  FakeChannel('scamshield/handoff', (c) async => switch (c.method) {
        'golden.status' => {'started': false},
        'report.pack' => {
            'targets': [
              {'phone': '1930'}
            ],
            'evidence': <Object?>[],
          },
        _ => null,
      }).install();
  FakeChannel('scamshield/prefs', (_) async => null).install();
  fakeEvents();
  await t.pumpWidget(const ScamShieldApp());
  await _settle(t);
  return app;
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Finder _tab(String tooltip) => find.byTooltip(tooltip);
Finder _title(String s) => find.descendant(of: find.byType(AppBar), matching: find.text(s));

Future<void> _goTab(WidgetTester t, String tooltip) async {
  await t.tap(_tab(tooltip));
  await _settle(t);
}

Future<void> _back(WidgetTester t) async {
  await t.pageBack();
  await _settle(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    group('nav $mode', () {
      testWidgets('QA_nav_fiveTabs_eachOpensItsScreen_noOverflow_${mode}_scale2', (t) async {
        await _boot(t, dark: dark);
        final screens = <String, Finder>{
          'Setup': find.byType(SetupScreen),
          'Check': find.byType(TryApiScreen),
          'Live': find.byType(LiveFeedScreen),
          'Learn': find.byType(LessonsScreen),
          'Help': find.text('रिपोर्ट करें'),
        };
        for (var i = 0; i < _tabs.length; i++) {
          final (hindi, tip) = _tabs[i];
          await _goTab(t, tip);
          expect(_title(hindi), findsOneWidget, reason: 'app bar title for $tip');
          expect(screens[tip], findsOneWidget, reason: 'screen for $tip is on stage');
          for (final other in screens.entries.where((e) => e.key != tip)) {
            expect(other.value, findsNothing, reason: '${other.key} must be hidden on $tip');
          }
          expect(t.takeException(), isNull, reason: tip);
        }
      });

      testWidgets('QA_nav_bottomBarLabels_readableAndEveryTabTappable48dp_${mode}_scale2', (t) async {
        await _boot(t, dark: dark);
        final bar = find.byType(NavigationBar);
        for (final (hindi, tip) in _tabs) {
          final label = find.descendant(of: bar, matching: find.text(hindi));
          expect(label, findsOneWidget, reason: hindi);
          final box = t.getRect(label);
          expect(box.width, greaterThan(0));
          expect(box.right, lessThanOrEqualTo(360), reason: '$hindi label clipped off screen');
          expect(box.left, greaterThanOrEqualTo(0), reason: '$hindi label clipped off screen');
          final dest = t.getSize(_tab(tip));
          expect(dest.height, greaterThanOrEqualTo(48), reason: tip);
          expect(dest.width, greaterThanOrEqualTo(48), reason: tip);
        }
        // chrome is clamped to 1.2x while the system asks for 2.0x
        final ctx = t.element(find.descendant(of: bar, matching: find.text(_tabs.first.$1)));
        expect(MediaQuery.textScalerOf(ctx).scale(10), closeTo(12, 0.01));
        // every tab actually becomes selected when tapped
        for (var i = 0; i < _tabs.length; i++) {
          await _goTab(t, _tabs[i].$2);
          expect(t.widget<NavigationBar>(bar).selectedIndex, i);
        }
      });

      testWidgets('QA_nav_report1930Button_onEveryTab_reachable48dp_opensReportAndReturns_${mode}_scale2', (t) async {
        await _boot(t, dark: dark);
        for (final (hindi, tip) in _tabs) {
          await _goTab(t, tip);
          final btn = find.byKey(const Key('btn_report_1930'));
          expect(btn, findsOneWidget, reason: 'missing on $tip');
          expect(find.descendant(of: btn, matching: find.text('ठगे गए? 1930')), findsOneWidget);
          final r = t.getRect(btn);
          expect(r.height, greaterThanOrEqualTo(48), reason: tip);
          expect(r.width, greaterThanOrEqualTo(48), reason: tip);
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(360));
          await t.tap(btn);
          await _settle(t);
          expect(find.byType(ReportScreen), findsOneWidget, reason: tip);
          expect(_title('रिपोर्ट'), findsOneWidget);
          expect(t.takeException(), isNull, reason: tip);
          await _back(t);
          expect(find.byType(ReportScreen), findsNothing, reason: 'back from Report on $tip');
          expect(_title(hindi), findsOneWidget, reason: 'returns to the same tab $tip');
        }
      });

      testWidgets('QA_nav_helpHub_tilesOpenReportFamilySettings_noOverflow_${mode}_scale2', (t) async {
        await _boot(t, dark: dark);
        await _goTab(t, 'Help');
        final tiles = [
          ('रिपोर्ट करें', find.byType(ReportScreen), 'रिपोर्ट'),
          ('परिवार कोड', find.byType(FamilyScreen), 'परिवार कोड'),
          ('सेटिंग', find.byType(SettingsScreen), 'सेटिंग'),
        ];
        for (final (label, screen, title) in tiles) {
          final tile = find.text(label);
          await t.ensureVisible(tile);
          await _settle(t);
          expect(t.getSize(tile).height, greaterThan(0));
          await t.tap(tile);
          await _settle(t);
          expect(screen, findsOneWidget, reason: label);
          expect(_title(title), findsOneWidget, reason: label);
          expect(t.takeException(), isNull, reason: label);
          await _back(t);
          expect(screen, findsNothing, reason: 'back from $label');
        }
      });

      testWidgets('QA_nav_helpHub_hasNoLessonsTile_lessonsReachedByLearnTabOnly_${mode}_scale2', (t) async {
        // Documents the actual IA: Lessons lives in the bottom bar, not the Help hub.
        await _boot(t, dark: dark);
        await _goTab(t, 'Help');
        for (final l in ['रिपोर्ट करें', 'परिवार कोड', 'सेटिंग']) {
          await reveal(t, find.text(l)); // list is lazy at 2.0 scale: scroll to build each tile
        }
        expect(find.descendant(of: find.byType(ActionTile), matching: find.textContaining('सीख')), findsNothing);
        await _goTab(t, 'Learn');
        expect(find.byType(LessonsScreen), findsOneWidget);
      });
    });
  }

  group('deep link route=report', () {
    testWidgets('QA_deepLink_report_atLaunch_opensReportOnTopOfHome_light_scale2', (t) async {
      final app = await _boot(t, routes: ['report']);
      expect(find.byType(ReportScreen), findsOneWidget);
      expect(_title('रिपोर्ट'), findsOneWidget);
      expect(app.routeAsks, 1);
      expect(t.takeException(), isNull);
      await _back(t);
      expect(find.byType(ReportScreen), findsNothing);
      expect(_title('सेटअप'), findsOneWidget); // Home is underneath
    });

    testWidgets('QA_deepLink_report_atLaunch_dark_scale2', (t) async {
      await _boot(t, dark: true, routes: ['report']);
      expect(find.byType(ReportScreen), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('QA_deepLink_report_onResume_popsDeepStackAndShowsExactlyOneReport', (t) async {
      final app = await _boot(t, routes: [null, 'report']);
      await _goTab(t, 'Help');
      await t.tap(find.text('परिवार कोड'));
      await _settle(t);
      expect(find.byType(FamilyScreen), findsOneWidget);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(t);
      expect(app.routeAsks, greaterThanOrEqualTo(2));
      expect(find.byType(ReportScreen), findsOneWidget);
      expect(find.byType(FamilyScreen), findsNothing); // stack was popped to home first
      expect(t.takeException(), isNull);
      await _back(t);
      expect(find.byType(ReportScreen), findsNothing);
      expect(_title('मदद'), findsOneWidget);
    });

    testWidgets('QA_deepLink_resumeWithoutRoute_leavesCurrentScreenAlone', (t) async {
      await _boot(t);
      await _goTab(t, 'Live');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(t);
      expect(find.byType(ReportScreen), findsNothing);
      expect(_title('लाइव'), findsOneWidget);
    });

    for (final (name, route) in <(String, Object?)>[
      ('unknownRoute', 'nonsense'),
      ('emptyString', ''),
      ('nativeThrows', PlatformException(code: 'X')),
      ('missingPlugin', MissingPluginException('none')),
    ]) {
      testWidgets('QA_deepLink_$name _homeStillUsable_noReport', (t) async {
        await _boot(t, routes: [route]);
        expect(find.byType(ReportScreen), findsNothing);
        expect(_title('सेटअप'), findsOneWidget);
        await _goTab(t, 'Check');
        expect(find.byType(TryApiScreen), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });
}
