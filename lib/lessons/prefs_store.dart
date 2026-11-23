import 'dart:convert';

import 'package:flutter/services.dart';

import 'quiz_engine.dart';

/// Persists best scores through native SharedPreferences on a MethodChannel.
/// The native handler (getString/setString) is wired later (T3.11); until then
/// the channel is missing and scores are kept in memory for the session.
/// Single string values (language, first-run flags) on the same channel and with the
/// same in-memory fallback as [PrefsQuizStore].
class PrefsStrings {
  PrefsStrings({MethodChannel channel = const MethodChannel('scamshield/prefs')}) : _ch = channel;

  static const langKey = 'lang_v1';
  static const captionsKey = 'captions_ack_v1';
  static const onboardedKey = 'onboarded_v1';
  final MethodChannel _ch;
  final _mem = <String, String>{};

  Future<String?> get(String key) async {
    try {
      final raw = await _ch.invokeMethod<String>('getString', {'key': key});
      if (raw != null && raw.isNotEmpty) _mem[key] = raw;
    } on MissingPluginException {
      // native side not wired yet: in-memory only
    } on PlatformException {
      // unreadable store: use the in-memory copy
    }
    return _mem[key];
  }

  Future<void> set(String key, String value) async {
    _mem[key] = value;
    try {
      await _ch.invokeMethod<void>('setString', {'key': key, 'value': value});
    } on MissingPluginException {
      // in-memory only until the native handler exists
    } on PlatformException {
      // keep the in-memory copy
    }
  }
}

class PrefsQuizStore implements QuizStore {
  PrefsQuizStore({
    MethodChannel channel = const MethodChannel('scamshield/prefs'),
  }) : _ch = channel;

  static const _key = 'lesson_best_v1';
  final MethodChannel _ch;
  Map<String, int> _mem = {};

  @override
  Future<Map<String, int>> loadBest() async {
    try {
      final raw = await _ch.invokeMethod<String>('getString', {'key': _key});
      if (raw != null && raw.isNotEmpty) {
        _mem = (jsonDecode(raw) as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        );
      }
    } on MissingPluginException {
      // native side not wired yet: keep in-memory scores
    } on PlatformException {
      // unreadable store: start from in-memory scores
    } on FormatException {
      // corrupt value: ignore it
    }
    return Map.of(_mem);
  }

  @override
  Future<void> saveBest(Map<String, int> best) async {
    _mem = Map.of(best);
    try {
      await _ch.invokeMethod<void>('setString', {
        'key': _key,
        'value': jsonEncode(best),
      });
    } on MissingPluginException {
      // in-memory only until the native handler exists
    } on PlatformException {
      // keep the in-memory copy
    }
  }
}
