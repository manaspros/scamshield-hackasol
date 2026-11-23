import 'package:flutter/services.dart';

/// One update from the recogniser while the mic is open.
class SpeechEvent {
  const SpeechEvent(this.type, {this.text = '', this.level = 0, this.code});

  /// `ready`, `partial`, `final`, `rms`, `error` or `end`.
  final String type;
  final String text;
  final double level; // 0..1 loudness, for the waveform
  final String? code;

  static SpeechEvent fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    return SpeechEvent(
      '${m['type'] ?? 'end'}',
      text: '${m['text'] ?? ''}',
      level: (m['level'] as num?)?.toDouble() ?? 0,
      code: m['code'] as String?,
    );
  }
}

enum SpeechStatus { live, done, denied, unavailable, failed }

class SpeechStart {
  const SpeechStart(this.status, [this.text = '']);
  final SpeechStatus status;

  /// Set when the system dialog (no in-app recogniser) already returned the words.
  final String text;
}

/// Voice typing through Android's default recogniser (Google on most phones), via SpeechChannel.kt.
/// Like the other bridges it never throws: a missing plugin reads as "unavailable".
class SpeechApi {
  const SpeechApi({
    this.method = const MethodChannel('scamshield/speech'),
    this.events = const EventChannel('scamshield/speech/events'),
  });
  final MethodChannel method;
  final EventChannel events;

  /// BCP-47 tag for the app language; Chhattisgarhi is recognised as Hindi.
  static String localeFor(String lang) => lang == 'en' ? 'en-IN' : 'hi-IN';

  Stream<SpeechEvent> stream() => events.receiveBroadcastStream().map(SpeechEvent.fromMap);

  Future<SpeechStart> start(String lang) async {
    try {
      final m = await method.invokeMapMethod<Object?, Object?>('start', {'locale': localeFor(lang)});
      if (m?['mode'] == 'intent') return SpeechStart(SpeechStatus.done, '${m?['text'] ?? ''}');
      return const SpeechStart(SpeechStatus.live);
    } on MissingPluginException {
      return const SpeechStart(SpeechStatus.unavailable);
    } on PlatformException catch (e) {
      return SpeechStart(switch (e.code) {
        'NO_PERMISSION' => SpeechStatus.denied,
        'UNAVAILABLE' => SpeechStatus.unavailable,
        _ => SpeechStatus.failed,
      });
    }
  }

  Future<void> stop() => _call('stop');
  Future<void> cancel() => _call('cancel');

  Future<void> _call(String m) async {
    try {
      await method.invokeMethod<void>(m);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
