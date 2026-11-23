import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'demo/demo_flag.dart';
import 'screens/demo_lab_screen.dart';
import 'screens/family_screen.dart';
import 'screens/lessons_screen.dart';
import 'screens/live_feed_screen.dart';
import 'screens/recording_screen.dart';
import 'screens/report_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';
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
      title: 'ScamShield',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
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
  static const _titles = ['सेटअप', 'जाँच', 'लाइव', 'सीखें', 'मदद'];

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
      _push('रिकॉर्डिंग', const RecordingScreen());
    }
  }

  void _push(String title, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(appBar: _bar(title), body: page),
      ));

  void _openReport() => _push('रिपोर्ट', const ReportScreen());

  Widget _page(int i) => switch (i) {
        0 => const SetupScreen(),
        1 => const TryApiScreen(),
        2 => const LiveFeedScreen(),
        3 => const LessonsScreen(),
        _ => _HelpHub(onOpen: _push),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _bar(_titles[_tab], actions: [
        // Always visible: the fastest way to the 1930 report flow (the dial itself happens only in ReportScreen).
        TextButton(
          key: const Key('btn_report_1930'),
          onPressed: _openReport,
          style: TextButton.styleFrom(minimumSize: const Size(kTouch, kTouch)),
          child: const Text('ठगे गए? 1930'),
        ),
        const SizedBox(width: Sp.s),
      ]),
      body: IndexedStack(index: _tab, children: [
        for (var i = 0; i < _titles.length; i++) _visited.contains(i) ? _page(i) : const SizedBox.shrink(),
      ]),
      bottomNavigationBar: _clamped(NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _visited.add(i);
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checklist), label: 'सेटअप', tooltip: 'Setup'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: 'जाँच', tooltip: 'Check'),
          NavigationDestination(icon: Icon(Icons.graphic_eq), label: 'लाइव', tooltip: 'Live'),
          NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school), label: 'सीखें', tooltip: 'Learn'),
          NavigationDestination(icon: Icon(Icons.help_outline), selectedIcon: Icon(Icons.help), label: 'मदद', tooltip: 'Help'),
        ],
      )),
    );
  }
}

/// Help tab: one big icon-first tile per task without a bottom-bar slot. Hindi label, English caption.
class _HelpHub extends StatelessWidget {
  const _HelpHub({required this.onOpen});
  final void Function(String title, Widget page) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.xl),
      children: [
        const SectionHeader(title: 'मदद', icon: Icons.help, subtitle: 'Help'),
        ActionTile(
          icon: Icons.flag,
          label: 'रिपोर्ट करें',
          caption: 'Report a scam (1930)',
          onTap: () => onOpen('रिपोर्ट', const ReportScreen()),
        ),
        const SizedBox(height: Sp.m),
        ActionTile(
          icon: Icons.family_restroom,
          label: 'परिवार कोड',
          caption: 'Family code',
          onTap: () => onOpen('परिवार कोड', const FamilyScreen()),
        ),
        const SizedBox(height: Sp.m),
        ActionTile(
          icon: Icons.settings,
          label: 'सेटिंग',
          caption: 'Settings',
          onTap: () => onOpen('सेटिंग', const SettingsScreen()),
        ),
        const SizedBox(height: Sp.m),
        ActionTile(
          icon: Icons.mic,
          label: 'कॉल रिकॉर्डिंग',
          caption: 'Check a recorded call',
          onTap: () => onOpen('रिकॉर्डिंग', const RecordingScreen()),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: DemoFlag.enabled,
          builder: (_, on, _) => on
              ? Padding(
                  padding: const EdgeInsets.only(top: Sp.m),
                  child: ActionTile(
                    key: const Key('tile_demo_lab'),
                    icon: Icons.science,
                    label: 'डेमो लैब',
                    caption: 'Demo Lab',
                    onTap: () => onOpen('डेमो लैब', const DemoLabScreen()),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
