import 'package:flutter/material.dart';

import '../lessons/prefs_store.dart';

/// App-wide light / dark / system choice, stored under `theme_v1`.
abstract final class ThemeController {
  static const key = 'theme_v1';
  static var _prefs = PrefsStrings();

  static final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> load() async {
    final v = await _prefs.get(key);
    mode.value = switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    await _prefs.set(key, m.name);
  }

  /// The top-bar button: flips to the opposite of what is on screen now.
  static Future<void> toggle(Brightness current) =>
      set(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);

  @visibleForTesting
  static void debugReset() {
    _prefs = PrefsStrings();
    mode.value = ThemeMode.system;
  }
}
