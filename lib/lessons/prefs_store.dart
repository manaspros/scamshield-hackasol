import 'dart:convert';

import 'package:flutter/services.dart';

import 'quiz_engine.dart';

/// Persists best scores through native SharedPreferences on a MethodChannel.
/// The native handler (getString/setString) is wired later (T3.11); until then
/// the channel is missing and scores are kept in memory for the session.
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
