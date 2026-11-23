import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shown in Settings; the hidden 7-tap switch hangs off this row. Keep in step with pubspec.yaml `version`.
const kAppVersion = '1.0.0';

/// Feature flag for the Demo Lab. Stored as "1" / "0" under `demo_mode` on the native prefs channel.
/// Unset means [kDebugMode]: on in debug builds, off in release until someone turns it on.
abstract final class DemoFlag {
  static const key = 'demo_mode';
  static const _channel = MethodChannel('scamshield/prefs');

  /// UI listens to this; it is also the in-session copy when the native prefs channel is missing.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(kDebugMode);

  /// Re-reads the stored value. Anything other than "1" / "0" (unset, junk) leaves the current value.
  static Future<void> load() async {
    try {
      final v = await _channel.invokeMethod<String>('getString', {'key': key});
      if (v == '1' || v == '0') enabled.value = v == '1';
    } on MissingPluginException {
      // tests / non-Android: keep the in-session value
    } on PlatformException {
      // unreadable store: keep the in-session value
    }
  }

  static Future<void> set(bool on) async {
    enabled.value = on;
    try {
      await _channel.invokeMethod<void>('setString', {'key': key, 'value': on ? '1' : '0'});
    } on MissingPluginException {
      // session only
    } on PlatformException {
      // session only
    }
  }
}
