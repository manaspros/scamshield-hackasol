import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/llm_api.dart';
import 'api/model_catalog.dart';
import 'demo/demo_flag.dart';
import 'l10n/app_language.dart';
import 'l10n/strings_shell.dart';
import 'learn/learn_plan.dart';
import 'profile/user_profile.dart';
import 'screens/family_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lessons_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/recording_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'theme/tokens.dart';
import 'widgets/floating_nav.dart';
import 'widgets/shell_bar.dart';
import 'widgets/shield_logo.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Loaded once here (not per screen) so widget tests, which never run main(), start from empty in-memory state.
  ThemeController.load();
  ProfileStore.load();
  LearnStore.load();
  LlmStatus.refresh();
  ModelCatalogStore.loadCached().then((_) => ModelCatalogStore.refresh()); // online models.json, quietly
  runApp(const ScamShieldApp());
}

class ScamShieldApp extends StatelessWidget {
  const ScamShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (_, mode, _) => MaterialApp(
        // LangScope sits above the Navigator so every pushed screen rebuilds when the language changes.
        builder: (context, child) => LangScope(notifier: AppLanguage.current, child: child!),
        title: 'ScamShield',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: const LanguageGate(child: OnboardingGate(child: HomeShell())),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  static const _api = MethodChannel('scamshield/api');
  static const _tabKeys = ['tab_home', 'tab_learn', 'tab_profile'];

  int _tab = 0;
  final _visited = <int>{0}; // tabs are built on first visit, then kept alive

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DemoFlag.load(); // re-reads demo_mode; Profile's help list listens to DemoFlag.enabled
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialRoute());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _openInitialRoute();
  }

  /// Native hands out the launch/notification route once ("report", later "recording"), then null.
  Future<void> _openInitialRoute() async {
    String? route;
    try {
      route = await _api.invokeMethod<String>('app.initialRoute');
    } on MissingPluginException {
      return; // tests / non-Android
    } on PlatformException {
      return;
    }
    if (!mounted) return;
    if (route == 'report') {
      Navigator.of(context).popUntil((r) => r.isFirst);
      openReport(context);
    } else if (route == 'recording') {
      Navigator.of(context).popUntil((r) => r.isFirst);
      _push('recording_title', const RecordingScreen());
    } else if (route == 'family') {
      Navigator.of(context).popUntil((r) => r.isFirst);
      _push('family', const FamilyScreen());
    }
  }

  // titleKey is a shellStrings key, resolved in the route so the title follows a live language change.
  void _push(String titleKey, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(appBar: shellBar(titleText: shellT(AppLanguage.of(ctx), titleKey)), body: page),
      ));

  void _go(int i) => setState(() {
        _tab = i;
        _visited.add(i);
      });

  Widget _page(int i) => switch (i) {
        0 => HomeScreen(onOpenLearn: () => _go(1)),
        1 => const LessonsScreen(),
        _ => ProfileScreen(onOpen: _push),
      };

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    String t(String k) => shellT(lang, k);
    final home = _tab == 0;
    return Scaffold(
      appBar: shellBar(
        title: home
            // Keeps the user's text size (the bar is clamped at 1.2x); no FittedBox shrinking it.
            ? const Row(mainAxisSize: MainAxisSize.min, children: [
                ShieldLogo(size: 28),
                SizedBox(width: Sp.s),
                Flexible(child: Text('ScamShield', overflow: TextOverflow.ellipsis)),
              ])
            : Text(t(_tabKeys[_tab]), overflow: TextOverflow.ellipsis),
      ),
      body: IndexedStack(index: _tab, children: [
        for (var i = 0; i < _tabKeys.length; i++) _visited.contains(i) ? _page(i) : const SizedBox.shrink(),
      ]),
      bottomNavigationBar: clampedChrome(FloatingNav(
        index: _tab,
        onTap: _go,
        items: [
          FloatingNavItem(key: const Key('nav_home'), icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: t('tab_home')),
          FloatingNavItem(key: const Key('nav_learn'), icon: Icons.menu_book_outlined, selectedIcon: Icons.menu_book_rounded, label: t('tab_learn')),
          FloatingNavItem(key: const Key('nav_profile'), icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: t('tab_profile')),
        ],
      )),
    );
  }
}
