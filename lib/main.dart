import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'demo/demo_flag.dart';
import 'l10n/app_language.dart';
import 'l10n/strings_shell.dart';
import 'screens/demo_lab_screen.dart';
import 'screens/family_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lessons_screen.dart';
import 'screens/live_feed_screen.dart';
import 'screens/recording_screen.dart';
import 'screens/report_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/try_api_screen.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'widgets/action_tile.dart';
import 'widgets/section_header.dart';

void main() => runApp(const ScamShieldApp());

class ScamShieldApp extends StatelessWidget {
  const ScamShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // LangScope sits above the Navigator so every pushed screen rebuilds when the language changes.
      builder: (context, child) => LangScope(notifier: AppLanguage.current, child: child!),
      title: 'ScamShield',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const LanguageGate(child: OnboardingGate(child: HomeShell())),
    );
  }
}

/// Chrome (app bar, nav bar) stops growing at 1.2x so it fits at system 2.0x; page content keeps full scale.
Widget _clamped(Widget child) => MediaQuery.withClampedTextScaling(maxScaleFactor: 1.2, child: child);

PreferredSizeWidget _bar(String title, {List<Widget>? actions}) => PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: _clamped(AppBar(title: Text(title), actions: actions)),
    );

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  static const _api = MethodChannel('scamshield/api');
  static const _tabKeys = ['tab_home', 'tab_check', 'tab_live', 'tab_learn', 'tab_help'];

  int _tab = 0;
  final _visited = <int>{0}; // tabs are built on first visit, then kept alive

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DemoFlag.load(); // re-reads demo_mode; _HelpHub listens to DemoFlag.enabled
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
      _openReport();
    } else if (route == 'recording') {
      Navigator.of(context).popUntil((r) => r.isFirst);
      _push('recording_title', const RecordingScreen());
    }
  }

  // titleKey is a shellStrings key, resolved in the route so the title follows a live language change.
  void _push(String titleKey, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(appBar: _bar(shellT(AppLanguage.of(ctx), titleKey)), body: page),
      ));

  void _openReport() => _push('report_title', const ReportScreen());

  Widget _page(int i) => switch (i) {
        0 => const HomeScreen(),
        1 => const TryApiScreen(),
        2 => const LiveFeedScreen(),
        3 => const LessonsScreen(),
        _ => _HelpHub(onOpen: _push),
      };

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    String t(String k) => shellT(lang, k);
    return Scaffold(
      appBar: _bar(t(_tabKeys[_tab]), actions: [
        // Always visible: the fastest way to the 1930 report flow (the dial itself happens only in ReportScreen).
        Builder(builder: (context) {
          final st = Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
          return TextButton.icon(
            key: const Key('btn_report_1930'),
            onPressed: _openReport,
            style: TextButton.styleFrom(
              minimumSize: const Size(kTouch, 48),
              padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: 0),
              foregroundColor: st.scam,
              backgroundColor: Color.alphaBlend(st.scam.withValues(alpha: 0.10), Theme.of(context).colorScheme.surface),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.support_agent, size: 24),
            label: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('help_me'), style: TextStyle(height: 1.1)),
              Text(t('help_1930'), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: st.scam, height: 1.1)),
            ]),
          );
        }),
        const SizedBox(width: Sp.s),
      ]),
      body: IndexedStack(index: _tab, children: [
        for (var i = 0; i < _tabKeys.length; i++) _visited.contains(i) ? _page(i) : const SizedBox.shrink(),
      ]),
      bottomNavigationBar: _clamped(NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _visited.add(i);
        }),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: t('tab_home'), tooltip: 'Home'),
          NavigationDestination(icon: const Icon(Icons.fact_check_outlined), selectedIcon: const Icon(Icons.fact_check), label: t('tab_check'), tooltip: 'Check'),
          NavigationDestination(icon: const Icon(Icons.graphic_eq), label: t('tab_live'), tooltip: 'Live'),
          NavigationDestination(icon: const Icon(Icons.school_outlined), selectedIcon: const Icon(Icons.school), label: t('tab_learn'), tooltip: 'Learn'),
          NavigationDestination(icon: const Icon(Icons.help_outline), selectedIcon: const Icon(Icons.help), label: t('tab_help'), tooltip: 'Help'),
        ],
      )),
    );
  }
}

/// Help tab: one big icon-first tile per task without a bottom-bar slot. Primary label in the app language, the other script as caption.
class _HelpHub extends StatelessWidget {
  const _HelpHub({required this.onOpen});
  final void Function(String titleKey, Widget page) onOpen;

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    String t(String k) => shellT(lang, k);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.xl),
      children: [
        SectionHeader(title: t('tab_help'), icon: Icons.help, subtitle: t('help_sub')),
        ActionTile(
          icon: Icons.flag,
          label: t('report'),
          caption: t('report_cap'),
          onTap: () => onOpen('report_title', const ReportScreen()),
        ),
        const SizedBox(height: Sp.m),
        ActionTile(
          icon: Icons.family_restroom,
          label: t('family'),
          caption: t('family_cap'),
          onTap: () => onOpen('family', const FamilyScreen()),
        ),
        const SizedBox(height: Sp.m),
        ActionTile(
          icon: Icons.settings,
          label: t('settings'),
          caption: t('settings_cap'),
          onTap: () => onOpen('settings', const SettingsScreen()),
        ),
        const SizedBox(height: Sp.m),
        ActionTile(
          icon: Icons.mic,
          label: t('recording'),
          caption: t('recording_cap'),
          onTap: () => onOpen('recording_title', const RecordingScreen()),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: DemoFlag.enabled,
          builder: (_, on, _) => on
              ? Padding(
                  padding: const EdgeInsets.only(top: Sp.m),
                  child: ActionTile(
                    key: const Key('tile_demo_lab'),
                    icon: Icons.science,
                    label: t('demo'),
                    caption: t('demo_cap'),
                    onTap: () => onOpen('demo', const DemoLabScreen()),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
