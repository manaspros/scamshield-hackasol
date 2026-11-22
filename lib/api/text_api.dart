import 'package:flutter/services.dart';

import '../models/verdict.dart';

/// Dart facade over the native Text API (Kotlin `TextApi` + `GemmaClassifier`).
class TextApi {
  TextApi._();
  static const _api = MethodChannel('scamshield/api');
  static const _events = EventChannel('scamshield/events');

  /// Classify one statement/message. [source]: 'manual' | 'sms' | 'caption'.
  static Future<Verdict> classify(String text,
      {List<String> context = const [], String source = 'manual'}) async {
    final m = await _api.invokeMapMethod<Object?, Object?>(
        'classify', {'text': text, 'context': context, 'source': source});
    return Verdict.fromMap(m ?? const {});
  }

  /// Live pipeline events: caption, statement, verdict, discovery, call, model, service...
  static Stream<Map<Object?, Object?>> get events =>
      _events.receiveBroadcastStream().map((e) => (e as Map).cast<Object?, Object?>());

  static Future<Map<Object?, Object?>> modelStatus() async =>
      await _api.invokeMapMethod<Object?, Object?>('modelStatus') ?? {};
  static Future<Map<Object?, Object?>> loadModel() async =>
      await _api.invokeMapMethod<Object?, Object?>('loadModel') ?? {};
  static Future<Map<Object?, Object?>> importModel() async =>
      await _api.invokeMapMethod<Object?, Object?>('importModel') ?? {};
  static Future<Map<Object?, Object?>> serviceStatus() async =>
      await _api.invokeMapMethod<Object?, Object?>('serviceStatus') ?? {};
  static Future<Map<Object?, Object?>> getSettings() async =>
      await _api.invokeMapMethod<Object?, Object?>('getSettings') ?? {};
  static Future<Map<Object?, Object?>> setSettings(Map<String, Object?> s) async =>
      await _api.invokeMapMethod<Object?, Object?>('setSettings', s) ?? {};
  static Future<void> openAccessibilitySettings() => _api.invokeMethod('openAccessibilitySettings');
  static Future<void> openCaptionSettings() => _api.invokeMethod('openCaptionSettings');
  static Future<void> testOverlay() => _api.invokeMethod('testOverlay');
  static Future<Map<Object?, Object?>> downloadModel() async =>
      await _api.invokeMapMethod<Object?, Object?>('downloadModel') ?? {};
  static Future<Map<Object?, Object?>> downloadStatus() async =>
      await _api.invokeMapMethod<Object?, Object?>('downloadStatus') ?? {};
  static Future<void> cancelDownload() => _api.invokeMethod('cancelDownload');
  static Future<bool> micPermission() async => await _api.invokeMethod<bool>('micPermission') ?? false;
  static Future<void> requestMic() => _api.invokeMethod('requestMic');
  static Future<void> runMicProbe() => _api.invokeMethod('runMicProbe');
  static Future<void> playProbe(String path) => _api.invokeMethod('playProbe', {'path': path});
}
