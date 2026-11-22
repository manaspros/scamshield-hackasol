import 'package:flutter/material.dart';

import 'screens/family_screen.dart';
import 'screens/live_feed_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/try_api_screen.dart';
import 'theme/app_theme.dart';

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

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  static const _titles = ['Setup', 'Try the Text API', 'Live call feed', 'Family code', 'Settings'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ScamShield · ${_titles[_tab]}')),
      body: IndexedStack(index: _tab, children: const [
        SetupScreen(),
        TryApiScreen(),
        LiveFeedScreen(),
        FamilyScreen(),
        SettingsScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Setup'),
          NavigationDestination(icon: Icon(Icons.text_snippet), label: 'Try API'),
          NavigationDestination(icon: Icon(Icons.graphic_eq), label: 'Live'),
          NavigationDestination(icon: Icon(Icons.family_restroom), label: 'Family'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
