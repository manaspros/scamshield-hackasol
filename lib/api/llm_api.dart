import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether an on-device model is loaded, for labels like "Start AI quiz". Refreshed at app start,
/// when a quiz starts and when the model picker or Profile reads the model state.
abstract final class LlmStatus {
  static final ValueNotifier<bool> ready = ValueNotifier<bool>(false);

  static Future<void> refresh([LlmClient client = const LlmApi()]) async => ready.value = await client.ready();
}

/// On-device text generation (Gemma via MediaPipe). Abstract so tests can script answers.
abstract class LlmClient {
  /// True when a model is loaded and can answer.
  Future<bool> ready();

  /// The model's raw answer, or null when it is not ready or failed.
  Future<String?> generate(String prompt, {double temperature = 0.8});
}

class LlmApi implements LlmClient {
  const LlmApi({this.ch = const MethodChannel('scamshield/api')});
  final MethodChannel ch;

  @override
  Future<bool> ready() async {
    try {
      final m = await ch
          .invokeMapMethod<Object?, Object?>('modelStatus')
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      return m?['status'] == 'READY';
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String?> generate(String prompt, {double temperature = 0.8}) async {
    try {
      return await ch
          .invokeMethod<String>('llm.generate', {'prompt': prompt, 'temperature': temperature})
          .timeout(const Duration(seconds: 90));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on Exception {
      return null; // timeout
    }
  }
}

/// No model: every quiz and flashcard comes from the built-in lessons.
class NoLlm implements LlmClient {
  const NoLlm();
  @override
  Future<bool> ready() async => false;
  @override
  Future<String?> generate(String prompt, {double temperature = 0.8}) async => null;
}
