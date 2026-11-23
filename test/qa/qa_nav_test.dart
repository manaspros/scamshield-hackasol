import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/main.dart';
import 'package:scamshield/screens/family_screen.dart';
import 'package:scamshield/screens/home_screen.dart';
import 'package:scamshield/screens/lessons_screen.dart';
import 'package:scamshield/screens/live_feed_screen.dart';
import 'package:scamshield/screens/profile_screen.dart';
import 'package:scamshield/screens/report_screen.dart';
import 'package:scamshield/screens/settings_screen.dart';
import 'package:scamshield/screens/try_api_screen.dart';
import 'package:scamshield/theme/theme_controller.dart';
import 'package:scamshield/widgets/floating_nav.dart';

import 'qa_harness.dart';

/// (app-bar title, nav key). Home's bar shows the wordmark instead of a tab name.
const _tabs = [
  ('ScamShield', 'nav_home', 'होम'),
  ('सीखें', 'nav_learn', 'सीखें'),
  ('प्रोफ़ाइल', 'nav_profile', 'प्रोफ़ाइल'),
];

/// Native side for the whole app shell. [routes] is handed out once each, then null (like MainActivity).
class _App {
  _App(this.routes);
  final List<Object?> routes;
  int routeAsks = 0;
  final prefs = <String, String>{};

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
        return {'status': 'NOT_FOUND', 'message': '', 'installed': <Object?>[]};
      case 'downloadStatus':
        return {'status': 'IDLE'};
      case 'micPermission':
      case 'perm.notificationsGranted':
      case 'perm.notificationAccessGranted':
        return true;
      case 'getSettings':
        return {'useLlm': true};
      case 'verdicts.recent':
        return <Object?>[];
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
  FakeChannel('scamshield/prefs', (c) async {
    final a = (c.arguments as Map?) ?? const {};
    if (c.method == 'setString') app.prefs['${a['key']}'] = '${a['value']}';
    return c.method == 'getString' ? app.prefs['${a['key']}'] : null;
  }).install();
  fakeEvents();
  await t.pumpWidget(const ScamShieldApp());
  await _settle(t);
  return app;
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Finder _title(String s) => find.descendant(of: find.byType(AppBar), matching: find.text(s));

Future<void> _goTab(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await _settle(t);
}

Future<void> _back(WidgetTester t) async {
  await t.pageBack();
  await _settle(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AppLanguage.debugSet('hi'); // these tests assert the Hindi shell
    ThemeController.debugReset();
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    group('nav $mode', () {
      testWidgets('QA_nav_threeTabs_eachOpensItsScreen_noOverflow_${mode}_scale2', (t) async {
        await _boot(t, dark: dark);
        final screens = <String, Finder>{
          'nav_home': find.byType(HomeScreen),
          'nav_learn': find.byType(LessonsScreen),
          'nav_profile': find.byType(ProfileScreen),
        };
        for (final (title, key, _) in _tabs) {
          await _goTab(t, key);
          expect(_title(title), findsOneWidget, reason: 'app bar title for $key');
          expect(screens[key], findsOneWidget, reason: 'screen for $key is on stage');
          for (final other in screens.entries.where((e) => e.key != key)) {
            expect(other.value, findsNothing, reason: '${other.key} must be hidden on $key');
          }
          expect(t.takeException(), isNull, reason: key);
        }
      });

      testWidgets('QA_nav_floatingBar_everyTabShowsItsWord_everyTab48dp_${mode}_scale2', (t) async {
        await _boot(t, dark: dark);
        final bar = find.byType(FloatingNav);
        for (final (_, key, _) in _tabs) {
          await _goTab(t, key);
          // Every tab shows its word, whichever is selected, fully inside the 360dp screen.
          for (final (_, other, otherWord) in _tabs) {
            final label = find.descendant(of: bar, matching: find.text(otherWord));
            expect(label, findsOneWidget, reason: '$other shows its word while $key is selected');
            final r = t.getRect(label);
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(360));
          }
          for (final (_, k, _) in _tabs) {
            expectTapTarget(t, find.byKey(Key(k)));
          }
        }
        // chrome is clamped to 1.2x while the system asks for 2.0x
        final ctx = t.element(find.descendant(of: bar, matching: find.text(_tabs.last.$3)));
        expect(MediaQuery.textScalerOf(ctx).scale(10), closeTo(12, 0.01));
      });

      testWidgets('QA_nav_reportButton_onEveryTab_reachable48dp_opensReportAndReturns_${mode}_scale2', (t) async {
        await _boot(t, dark: dark);
        for (final (title, key, _) in _tabs) {
          await _goTab(t, key);
          final btn = find.byKey(const Key('btn_report_1930'));
          expect(btn, findsOneWidget, reason: 'missing on $key');
          expect(find.descendant(of: btn, matching: find.text('रिपोर्ट')), findsOneWidget);
          expect(find.descendant(of: btn, matching: find.byIcon(Icons.call_rounded)), findsOneWidget);
          final r = t.getRect(btn);
          expect(r.height, greaterThanOrEqualTo(48), reason: key);
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(360));
          await t.tap(btn);
          await _settle(t);
          expect(find.byType(ReportScreen), findsOneWidget, reason: key);
          expect(_title('रिपोर्ट'), findsOneWidget);
          expect(find.byKey(const Key('btn_report_1930')), findsNothing, reason: 'no Report button on Report itself');
          expect(t.takeException(), isNull, reason: key);
          await _back(t);
          expect(find.byType(ReportScreen), findsNothing, reason: 'back from Report on $key');
          expect(_title(title), findsOneWidget, reason: 'returns to the same tab $key');
        }
      });

      testWidgets('QA_nav_profileHelp_opensReportFamilySettings_noOverflow_${mode}_scale2', (t) async {
        await _boot(t, dark: dark);
        await _goTab(t, 'nav_profile');
        final rows = [
          ('profile_report', find.byType(ReportScreen), 'रिपोर्ट'),
          ('profile_family_code', find.byType(FamilyScreen), 'परिवार कोड'),
          ('profile_settings', find.byType(SettingsScreen), 'सेटिंग'),
        ];
        for (final (key, screen, title) in rows) {
          await tapVisible(t, find.byKey(Key(key)));
          await _settle(t);
          expect(screen, findsOneWidget, reason: key);
          expect(_title(title), findsOneWidget, reason: key);
          expect(t.takeException(), isNull, reason: key);
          await _back(t);
          expect(screen, findsNothing, reason: 'back from $key');
        }
      });

      testWidgets('QA_nav_homeQuickActions_openCheckAndLive_${mode}_scale2', (t) async {
        await _boot(t, dark: dark);
        await tapVisible(t, find.byKey(const Key('home_check')));
        await _settle(t);
        expect(find.byType(TryApiScreen), findsOneWidget);
        expect(_title('जाँच'), findsOneWidget);
        await _back(t);
        await tapVisible(t, find.byKey(const Key('home_live')));
        await _settle(t);
        expect(find.byType(LiveFeedScreen), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    });
  }

  testWidgets('QA_topBar_themeToggle_flipsWholeApp_andPersists', (t) async {
    final app = await _boot(t);
    expect(Theme.of(t.element(find.byType(HomeScreen))).brightness, Brightness.light);
    await t.tap(find.byKey(const Key('btn_theme')));
    await t.pumpAndSettle();
    expect(Theme.of(t.element(find.byType(HomeScreen))).brightness, Brightness.dark);
    expect(app.prefs['theme_v1'], 'dark');
    // also from a pushed screen
    await tapVisible(t, find.byKey(const Key('home_check')));
    await _settle(t);
    await t.tap(find.byKey(const Key('btn_theme')));
    await t.pumpAndSettle();
    expect(Theme.of(t.element(find.byType(TryApiScreen))).brightness, Brightness.light);
    expect(app.prefs['theme_v1'], 'light');
    expect(t.takeException(), isNull);
  });

  testWidgets('QA_topBar_languageIsland_switchesWholeApp_andPersists', (t) async {
    final app = await _boot(t);
    await t.tap(find.byKey(const Key('btn_lang')));
    await t.pumpAndSettle();
    for (final c in ['en', 'hi', 'hne']) {
      expect(find.byKey(Key('lang_menu_$c')), findsOneWidget);
    }
    expect(find.text('छत्तीसगढ़ी'), findsOneWidget);
    await t.tap(find.byKey(const Key('lang_menu_en')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('lang_menu_en')), findsNothing, reason: 'island closes after a pick');
    expect(AppLanguage.code, 'en');
    expect(app.prefs['lang_v1'], 'en');
    expect(find.descendant(of: find.byKey(const Key('btn_report_1930')), matching: find.text('Report')), findsOneWidget);
    expect(find.descendant(of: find.byType(FloatingNav), matching: find.text('Home')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  group('deep link route=report', () {
    testWidgets('QA_deepLink_report_atLaunch_opensReportOnTopOfHome_light_scale2', (t) async {
      final app = await _boot(t, routes: ['report']);
      expect(find.byType(ReportScreen), findsOneWidget);
      expect(_title('रिपोर्ट'), findsOneWidget);
      expect(app.routeAsks, 1);
      expect(t.takeException(), isNull);
      await _back(t);
      expect(find.byType(ReportScreen), findsNothing);
      expect(_title('ScamShield'), findsOneWidget); // Home is underneath
    });

    testWidgets('QA_deepLink_report_atLaunch_dark_scale2', (t) async {
      await _boot(t, dark: true, routes: ['report']);
      expect(find.byType(ReportScreen), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('QA_deepLink_report_onResume_popsDeepStackAndShowsExactlyOneReport', (t) async {
      final app = await _boot(t, routes: [null, 'report']);
      await _goTab(t, 'nav_profile');
      await tapVisible(t, find.byKey(const Key('profile_family_code')));
      await _settle(t);
      expect(find.byType(FamilyScreen), findsOneWidget);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(t);
      await _settle(t); // let the popped Family screen finish its exit animation
      expect(app.routeAsks, greaterThanOrEqualTo(2));
      expect(find.byType(ReportScreen), findsOneWidget);
      expect(find.byType(FamilyScreen), findsNothing); // stack was popped to home first
      expect(t.takeException(), isNull);
      await _back(t);
      expect(find.byType(ReportScreen), findsNothing);
      expect(_title('प्रोफ़ाइल'), findsOneWidget);
    });

    testWidgets('QA_deepLink_resumeWithoutRoute_leavesCurrentScreenAlone', (t) async {
      await _boot(t);
      await _goTab(t, 'nav_learn');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(t);
      expect(find.byType(ReportScreen), findsNothing);
      expect(_title('सीखें'), findsOneWidget);
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
        expect(_title('ScamShield'), findsOneWidget);
        await tapVisible(t, find.byKey(const Key('home_check')));
        await _settle(t);
        expect(find.byType(TryApiScreen), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });
}
