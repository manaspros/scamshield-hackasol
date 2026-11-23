import 'package:flutter/material.dart';

import '../lessons/prefs_store.dart';
import '../theme/tokens.dart';

const kLangCodes = ['en', 'hi', 'hne'];

/// App-wide language: the single source of truth, stored under `lang_v1` on the native prefs channel
/// (Kotlin reads the same key for notifications and the overlay).
/// `current` is null until the user picks one (first launch); [code] is then 'hi', the original look.
abstract final class AppLanguage {
  static var _prefs = PrefsStrings();

  static final ValueNotifier<String?> current = ValueNotifier<String?>(null);

  /// False until the stored choice has been read, so the picker never flashes for existing users.
  static final ValueNotifier<bool> ready = ValueNotifier<bool>(false);

  static String get code => current.value ?? 'hi';

  static Future<void> load() async {
    final v = await _prefs.get(PrefsStrings.langKey);
    if (v != null && kLangCodes.contains(v)) current.value = v;
    ready.value = true;
  }

  static Future<void> set(String lang) async {
    if (!kLangCodes.contains(lang)) return;
    current.value = lang;
    await _prefs.set(PrefsStrings.langKey, lang);
  }

  /// Tests only: define the language (or the first-run state with null) without touching storage.
  @visibleForTesting
  static void debugSet(String? lang) {
    current.value = lang;
    ready.value = true;
  }

  /// Tests only: back to a cold start (nothing loaded, no cached pref, no choice).
  @visibleForTesting
  static void debugReset() {
    _prefs = PrefsStrings();
    current.value = null;
    ready.value = false;
  }

  /// The language for this build context. Rebuilds the caller when the language changes
  /// (needs the [LangScope] that `ScamShieldApp` installs; without it, the value at call time).
  static String of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<LangScope>();
    return s?.notifier?.value ?? code;
  }
}

class LangScope extends InheritedNotifier<ValueNotifier<String?>> {
  const LangScope({super.key, required super.notifier, required super.child});
}

/// Three-language string table. Missing hne falls back to hi; missing en never falls back to Hindi
/// (it shows the key, which a test catches).
class Tri {
  const Tri({required this.hi, this.hne = const {}, required this.en});
  final Map<String, String> hi, hne, en;

  String call(String lang, String key) => switch (lang) {
        'en' => en[key] ?? key,
        'hne' => hne[key] ?? hi[key] ?? key,
        _ => hi[key] ?? key,
      };
}

/// First launch gate: loads the stored language, shows the picker while none is chosen, else the app.
class LanguageGate extends StatefulWidget {
  const LanguageGate({super.key, required this.child});
  final Widget child;
  @override
  State<LanguageGate> createState() => _LanguageGateState();
}

class _LanguageGateState extends State<LanguageGate> {
  @override
  void initState() {
    super.initState();
    if (!AppLanguage.ready.value) AppLanguage.load();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: AppLanguage.ready,
        builder: (_, ready, _) => !ready
            ? const Scaffold(body: SizedBox.shrink())
            : ValueListenableBuilder<String?>(
                valueListenable: AppLanguage.current,
                builder: (_, lang, _) => lang == null
                    ? Scaffold(body: SafeArea(child: LanguagePicker(onPicked: AppLanguage.set)))
                    : widget.child,
              ),
      );
}

/// Full-screen language choice: three large rows, nothing pre-selected unless [selected] is given.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, required this.onPicked, this.selected, this.showPrompt = true});
  final ValueChanged<String> onPicked;
  final String? selected;
  final bool showPrompt;

  static const _rows = [
    ('en', 'English', 'Aa'),
    ('hi', 'हिन्दी', 'अ'),
    ('hne', 'छत्तीसगढ़ी', 'छ'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(Sp.xl),
      children: [
        if (showPrompt) ...[
          const SizedBox(height: Sp.xl),
          Icon(Icons.translate, size: 56, color: cs.primary),
          const SizedBox(height: Sp.l),
          Semantics(
            header: true,
            child: Text('Choose your language / अपनी भाषा चुनें',
                key: const Key('lang_prompt'), style: t.textTheme.headlineSmall),
          ),
          const SizedBox(height: Sp.xl),
        ],
        for (final (code, label, sample) in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.m),
            child: Semantics(
              button: true,
              selected: selected == code,
              child: OutlinedButton(
                key: Key('lang_$code'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(80),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.m),
                  backgroundColor: selected == code ? cs.primary.withValues(alpha: 0.12) : null,
                  side: BorderSide(color: selected == code ? cs.primary : cs.outlineVariant, width: selected == code ? 2 : 1),
                ),
                onPressed: () => onPicked(code),
                child: Row(children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: cs.primary.withValues(alpha: 0.12),
                    child: Text(sample, style: t.textTheme.titleLarge?.copyWith(color: cs.primary)),
                  ),
                  const SizedBox(width: Sp.l),
                  Expanded(child: Text(label, style: t.textTheme.titleLarge)),
                  if (selected == code) Icon(Icons.check_circle, color: cs.primary),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}
