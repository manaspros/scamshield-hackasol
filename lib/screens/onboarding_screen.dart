import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../lessons/prefs_store.dart';
import '../theme/tokens.dart';
import 'family_screen.dart';
import 'page_route.dart';
import 'setup_screen.dart';

/// Whether first-run onboarding is finished, stored under `onboarded_v1` on the native prefs channel.
/// `done` is null until the stored value has been read, so onboarding never flashes for returning users.
abstract final class Onboarding {
  static var _prefs = PrefsStrings();

  static final ValueNotifier<bool?> done = ValueNotifier<bool?>(null);

  static Future<void> load() async {
    done.value = await _prefs.get(PrefsStrings.onboardedKey) == '1';
  }

  static Future<void> complete() async {
    done.value = true;
    await _prefs.set(PrefsStrings.onboardedKey, '1');
  }

  /// Tests only: define the state without touching storage.
  @visibleForTesting
  static void debugSet(bool? v) => done.value = v;

  /// Tests only: back to a cold start.
  @visibleForTesting
  static void debugReset() {
    _prefs = PrefsStrings();
    done.value = null;
  }
}

/// Shows onboarding until it has been finished or skipped once, then [child] forever.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, required this.child});
  final Widget child;
  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  @override
  void initState() {
    super.initState();
    if (Onboarding.done.value == null) Onboarding.load();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool?>(
        valueListenable: Onboarding.done,
        builder: (_, done, _) => done == null
            ? const Scaffold(body: SizedBox.shrink())
            : done
                ? widget.child
                : const OnboardingScreen(),
      );
}

/// Four short steps: what it does, permissions, optional family pairing, done. Skip is always available.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _steps = 4;
  int _i = 0;

  void _go(int d) => setState(() => _i = (_i + d).clamp(0, _steps - 1));

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    String t(String k, [Map<String, Object?> a = const {}]) => homeT(lang, k, a);
    final th = Theme.of(context);
    final last = _i == _steps - 1;
    final next = FilledButton(
      key: const Key('onb_next'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
      onPressed: last ? Onboarding.complete : () => _go(1),
      child: Text(last ? t('ob_start') : t('ob_next'), textAlign: TextAlign.center),
    );
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.s, Sp.s, Sp.s, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              if (_i == 0)
                const SizedBox.shrink()
              else
                // Icon only: with "Skip" beside it, a text label overflows at 2x.
                IconButton(
                  key: const Key('onb_back'),
                  tooltip: t('ob_back'),
                  onPressed: () => _go(-1),
                  icon: const Icon(Icons.arrow_back),
                ),
              if (!last) TextButton(key: const Key('onb_skip'), onPressed: Onboarding.complete, child: Text(t('ob_skip'))),
            ]),
          ),
          // The step count is spoken, not printed: a text counter costs a line at large sizes.
          LinearProgressIndicator(
            key: const Key('onb_step'),
            value: (_i + 1) / _steps,
            minHeight: 4,
            semanticsLabel: t('ob_step', {'n': _i + 1, 'm': _steps}),
          ),
          Expanded(
            child: switch (_i) {
              0 => _welcome(th, t),
              1 => Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Sp.l, Sp.l, Sp.l, 0),
                    child: Align(alignment: Alignment.centerLeft, child: Text(t('ob2_t'), style: th.textTheme.titleLarge)),
                  ),
                  // The permission list and its one primary action are the Setup screen itself: one implementation.
                  const Expanded(child: SetupScreen()),
                ]),
              2 => _family(th, t),
              _ => _done(th, t),
            },
          ),
          Padding(
            padding: const EdgeInsets.all(Sp.l),
            child: _i == 1 ? FilledButton.tonal(key: const Key('onb_next'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)), onPressed: () => _go(1), child: Text(t('ob_next'))) : next,
          ),
        ]),
      ),
    );
  }

  Widget _welcome(ThemeData th, String Function(String, [Map<String, Object?>]) t) {
    final cs = th.colorScheme;
    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: Sp.l),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 32, color: cs.primary),
            const SizedBox(width: Sp.m),
            Expanded(child: Text(text, style: th.textTheme.titleMedium)),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(Sp.xl), children: [
      Icon(Icons.shield, size: 64, color: cs.primary),
      const SizedBox(height: Sp.l),
      Semantics(header: true, child: Text(t('ob1_t'), style: th.textTheme.headlineSmall)),
      const SizedBox(height: Sp.xl),
      point(Icons.hearing, t('ob1_a')),
      point(Icons.notifications_active, t('ob1_b')),
      point(Icons.lock_outline, t('ob1_c')),
    ]);
  }

  Widget _family(ThemeData th, String Function(String, [Map<String, Object?>]) t) => ListView(
        padding: const EdgeInsets.all(Sp.xl),
        children: [
          Icon(Icons.family_restroom, size: 64, color: th.colorScheme.primary),
          const SizedBox(height: Sp.l),
          Semantics(header: true, child: Text(t('ob3_t'), style: th.textTheme.headlineSmall)),
          const SizedBox(height: Sp.m),
          Text(t('ob3_b'), style: th.textTheme.bodyLarge),
          const SizedBox(height: Sp.xl),
          OutlinedButton.icon(
            key: const Key('onb_pair'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
            onPressed: () => pushTitled(context, t('fam_title'), const FamilyScreen()),
            icon: const Icon(Icons.link, size: 28),
            label: Text(t('ob3_pair'), textAlign: TextAlign.center),
          ),
          const SizedBox(height: Sp.s),
          TextButton(
            key: const Key('onb_later'),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
            onPressed: () => _go(1),
            child: Text(t('ob3_later')),
          ),
        ],
      );

  Widget _done(ThemeData th, String Function(String, [Map<String, Object?>]) t) => ListView(
        padding: const EdgeInsets.all(Sp.xl),
        children: [
          Icon(Icons.check_circle, size: 64, color: th.colorScheme.primary),
          const SizedBox(height: Sp.l),
          Semantics(header: true, child: Text(t('ob4_t'), style: th.textTheme.headlineSmall)),
          const SizedBox(height: Sp.m),
          Text(t('ob4_b'), style: th.textTheme.bodyLarge),
        ],
      );
}
