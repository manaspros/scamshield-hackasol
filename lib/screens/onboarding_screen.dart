import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/home_api.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../lessons/prefs_store.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/premium.dart';
import '../widgets/shell_bar.dart';
import 'family_screen.dart';
import 'page_route.dart';
import 'profile_screen.dart';
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

/// Four swipeable steps: welcome, permissions, family pairing, done. The language can be changed and the rest
/// skipped from every step but the last.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.api = const HomeApi()});
  final HomeApi api;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  static const _steps = 4;
  final _pages = PageController();
  late final _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  int _i = 0;
  int _permsOn = 0;
  Protection? _prot;
  bool? _paired;

  @override
  void initState() {
    super.initState();
    // Gentle float and pulse; still when the system asks for reduced motion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) _loop.repeat();
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _go(int i) {
    final n = i.clamp(0, _steps - 1);
    if (_pages.hasClients) {
      _pages.animateToPage(n, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    } else {
      setState(() => _i = n);
    }
  }

  Future<void> _onPage(int i) async {
    setState(() => _i = i);
    if (i == _steps - 1) {
      final p = await widget.api.protection();
      final f = await widget.api.familyPaired();
      if (mounted) {
        setState(() {
          _prot = p;
          _paired = f;
        });
      }
    }
  }

  Future<void> _pair() async {
    await pushTitled(context, homeT(AppLanguage.code, 'fam_title'), const FamilyScreen());
    if (mounted) _go(3);
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    String t(String k, [Map<String, Object?> a = const {}]) => homeT(lang, k, a);
    final th = Theme.of(context);
    final p = palOf(context);
    final last = _i == _steps - 1;
    final (label, onNext) = switch (_i) {
      0 => (t('ob_get_started'), () => _go(1)),
      1 => (t(_permsOn == 4 ? 'ob_continue' : 'ob_continue_anyway'), () => _go(2)),
      2 => (t('ob3_later'), () => _go(3)),
      _ => (t('ob_start'), Onboarding.complete),
    };
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          clampedChrome(Padding(
            padding: const EdgeInsets.fromLTRB(Sp.s, Sp.s, Sp.s, 0),
            child: Row(children: [
              if (_i > 0)
                IconButton(
                  key: const Key('onb_back'),
                  tooltip: t('ob_back'),
                  onPressed: () => _go(_i - 1),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              const LanguageButton(),
              const Spacer(),
              if (!last)
                TextButton(
                  key: const Key('onb_skip'),
                  style: TextButton.styleFrom(foregroundColor: p.muted),
                  onPressed: Onboarding.complete,
                  child: Text(t('ob_skip')),
                ),
            ]),
          )),
          Expanded(
            child: PageView(
              key: const Key('onb_pages'),
              controller: _pages,
              onPageChanged: _onPage,
              children: [
                _welcome(th, p, t),
                _perms(th, p, t),
                _family(th, p, t),
                _done(th, p, t),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.s, Sp.xl, Sp.l),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Semantics(
                key: const Key('onb_step'),
                label: t('ob_step', {'n': _i + 1, 'm': _steps}),
                excludeSemantics: true,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var k = 0; k < _steps; k++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: k == _i ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(color: k <= _i ? p.accent : p.hairline, borderRadius: BorderRadius.circular(Rad.pill)),
                    ),
                ]),
              ),
              const SizedBox(height: Sp.m + 2),
              if (_i == 2) ...[
                FilledButton.icon(
                  key: const Key('onb_pair'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
                  onPressed: _pair,
                  icon: const Icon(Icons.link_rounded),
                  label: Text(t('ob3_pair'), textAlign: TextAlign.center),
                ),
                const SizedBox(height: Sp.xs),
                TextButton(
                  key: const Key('onb_next'),
                  style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: onNext,
                  child: Text(label),
                ),
              ] else
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Rad.pill),
                    boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.32), blurRadius: 24, offset: const Offset(0, 10))],
                  ),
                  child: FilledButton(
                    key: const Key('onb_next'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
                    onPressed: onNext,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Flexible(child: Text(label, textAlign: TextAlign.center)),
                      const SizedBox(width: Sp.s),
                      const Icon(Icons.arrow_forward_rounded, size: 22),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// A float offset for the welcome chips and family code (phase in 0..1 shifts each one).
  double _bob(double phase) => math.sin((_loop.value + phase) * 2 * math.pi) * 5;

  Widget _welcome(ThemeData th, Pal p, String Function(String, [Map<String, Object?>]) t) {
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    Widget chip(String text, Color dot, double phase) => AnimatedBuilder(
          animation: _loop,
          builder: (_, child) => Transform.translate(offset: Offset(0, _bob(phase)), child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: Sp.s),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16), boxShadow: Elev.island(th.brightness)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: Sp.s),
              Text(text, style: th.textTheme.labelMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ),
        );
    Widget feature(IconData icon, Color c, String text) => Padding(
          padding: const EdgeInsets.only(bottom: Sp.m),
          child: Row(children: [
            IconBadge(icon: icon, color: c, size: 40, iconSize: 22),
            const SizedBox(width: Sp.m + 2),
            Expanded(child: Text(text, style: th.textTheme.bodyLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w500, height: 1.35))),
          ]),
        );
    return ListView(padding: const EdgeInsets.symmetric(horizontal: Sp.xl), children: [
      SizedBox(
        height: 280,
        child: Stack(alignment: Alignment.center, children: [
          Container(width: 240, height: 240, decoration: BoxDecoration(color: p.accent.withValues(alpha: p.isDark ? 0.10 : 0.07), shape: BoxShape.circle)),
          Container(width: 184, height: 184, decoration: BoxDecoration(color: p.accent.withValues(alpha: p.isDark ? 0.18 : 0.14), shape: BoxShape.circle)),
          AnimatedBuilder(
            animation: _loop,
            builder: (_, _) {
              final v = (_loop.value * 1.4) % 1.0;
              return Opacity(
                opacity: (1 - v).clamp(0.0, 1.0) * 0.6,
                child: Transform.scale(
                  scale: 0.9 + v * 0.35,
                  child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.accent, width: 2))),
                ),
              );
            },
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                color: p.accent,
                borderRadius: BorderRadius.circular(36),
                boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.38), blurRadius: 36, offset: const Offset(0, 16))],
              ),
              child: Icon(Icons.verified_user_rounded, color: p.onAccent, size: 62),
            ),
          ),
          Positioned(left: 0, top: 26, child: chip(t('ob_chip_otp'), st.scam, 0)),
          Positioned(right: 0, top: 120, child: chip(t('ob_chip_kyc'), st.suspicious, 0.33)),
          Positioned(left: 12, bottom: 20, child: chip(t('ob_chip_safe'), st.safe, 0.66)),
        ]),
      ),
      Semantics(
        header: true,
        child: Text(t('ob1_t'), style: th.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.15, fontSize: 30)),
      ),
      const SizedBox(height: Sp.s),
      Text(t('ob1_s'), style: th.textTheme.bodyLarge?.copyWith(color: p.muted, fontSize: 17, height: 1.45)),
      const SizedBox(height: Sp.l + 4),
      feature(Icons.hearing_rounded, p.accent, t('ob1_a')),
      feature(Icons.notifications_active_rounded, st.suspicious, t('ob1_b')),
      feature(Icons.lock_rounded, st.safe, t('ob1_c')),
    ]);
  }

  // The same cards as Setup & permissions (one implementation); the title scrolls with them.
  Widget _perms(ThemeData th, Pal p, String Function(String, [Map<String, Object?>]) t) => SetupScreen(
        compact: true,
        onCount: (n) => setState(() => _permsOn = n),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.xs, 0, Sp.xs, Sp.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(t('ob2_t'), style: th.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 28))),
            const SizedBox(height: Sp.xs),
            Text(t('ob2_s'), style: th.textTheme.bodyLarge?.copyWith(color: p.muted, fontSize: 16)),
          ]),
        ),
      );

  Widget _family(ThemeData th, Pal p, String Function(String, [Map<String, Object?>]) t) {
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    Widget phone(String who, Color c, Color on) => Container(
          width: 96,
          height: 150,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: p.hairline, width: 2),
            boxShadow: Elev.island(th.brightness),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircleAvatar(radius: 22, backgroundColor: c, child: Text(who, style: th.textTheme.titleSmall?.copyWith(color: on, fontWeight: FontWeight.w800))),
            const SizedBox(height: Sp.s),
            Container(width: 52, height: 6, decoration: BoxDecoration(color: p.hairline, borderRadius: BorderRadius.circular(3))),
          ]),
        );
    return ListView(padding: const EdgeInsets.symmetric(horizontal: Sp.xl), children: [
      SizedBox(
        height: 290,
        child: Stack(children: [
          Positioned.fill(child: AnimatedBuilder(animation: _loop, builder: (_, _) => CustomPaint(painter: _ArcPainter(p.accent, _loop.value)))),
          Positioned(left: 8, bottom: 10, child: phone(t('ob_you'), p.accent, p.onAccent)),
          Positioned(right: 8, bottom: 10, child: phone('S', st.safe, p.isDark ? Colors.black : Colors.white)),
          Align(
            alignment: const Alignment(0, -0.75),
            child: AnimatedBuilder(
              animation: _loop,
              builder: (_, child) => Transform.translate(offset: Offset(0, _bob(0.2)), child: child),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Sp.l + 2, vertical: Sp.m),
                decoration: BoxDecoration(
                  color: p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFF1D1D1F),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: Elev.island(th.brightness),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(t('ob_code'), style: th.textTheme.labelSmall?.copyWith(color: const Color(0xFFA1A1A6), fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.6)),
                  Text('482 913', style: th.textTheme.headlineSmall?.copyWith(color: const Color(0xFFF5F5F7), fontWeight: FontWeight.w800, letterSpacing: 3)),
                ]),
              ),
            ),
          ),
        ]),
      ),
      Semantics(header: true, child: Text(t('ob3_t'), style: th.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 30))),
      const SizedBox(height: Sp.s),
      Text(t('ob3_b'), style: th.textTheme.bodyLarge?.copyWith(color: p.muted, fontSize: 17, height: 1.45)),
    ]);
  }

  Widget _done(ThemeData th, Pal p, String Function(String, [Map<String, Object?>]) t) {
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    final pr = _prot;
    Widget chip(String text, bool? ok) {
      final c = ok == true ? st.safe : ok == false ? st.suspicious : p.accent;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: Sp.s),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Rad.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ok == true ? Icons.check_rounded : ok == false ? Icons.priority_high_rounded : Icons.schedule_rounded, size: 16, color: c),
          const SizedBox(width: 4),
          Text(text, style: th.textTheme.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      );
    }

    const confetti = [(0.08, 0.12), (0.86, 0.15), (0.16, 0.78), (0.82, 0.74), (0.45, 0.04), (0.04, 0.45), (0.94, 0.44), (0.66, 0.88), (0.3, 0.9), (0.7, 0.06)];
    final colors = [p.accent, st.safe, st.suspicious, st.scam];
    return ListView(padding: const EdgeInsets.symmetric(horizontal: Sp.xl), children: [
      SizedBox(
        height: 240,
        child: LayoutBuilder(
          builder: (context, box) => Stack(alignment: Alignment.center, children: [
            for (var k = 0; k < confetti.length; k++)
              Positioned(
                left: confetti[k].$1 * (box.maxWidth - 14),
                top: confetti[k].$2 * (box.maxHeight - 14),
                child: AnimatedBuilder(
                  animation: _loop,
                  builder: (_, child) => Transform.translate(offset: Offset(0, _bob(k / 10)), child: Transform.rotate(angle: k * 0.7 + _loop.value, child: child)),
                  child: Container(
                    width: 8.0 + (k % 3) * 4,
                    height: 8.0 + (k % 3) * 4,
                    decoration: BoxDecoration(color: colors[k % 4], borderRadius: BorderRadius.circular(k.isOdd ? 99 : 3)),
                  ),
                ),
              ),
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(color: st.safe.withValues(alpha: 0.16), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.3, end: 1),
                duration: const Duration(milliseconds: 650),
                curve: Curves.elasticOut,
                builder: (_, s, child) => Transform.scale(scale: s, child: child),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: st.safe,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: st.safe.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 14))],
                  ),
                  child: Icon(Icons.check_rounded, color: p.isDark ? Colors.black : Colors.white, size: 54),
                ),
              ),
            ),
          ]),
        ),
      ),
      Semantics(
        header: true,
        child: Text(t('ob4_t'), textAlign: TextAlign.center, style: th.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 30)),
      ),
      const SizedBox(height: Sp.s),
      Text(t('ob4_s'), textAlign: TextAlign.center, style: th.textTheme.bodyLarge?.copyWith(color: p.muted, fontSize: 17)),
      const SizedBox(height: Sp.l),
      Wrap(alignment: WrapAlignment.center, spacing: Sp.s, runSpacing: Sp.s, children: [
        chip(t('off_call'), pr?.call),
        chip(t('off_msg'), pr?.messages),
        chip(t('off_notif'), pr?.alerts),
        chip(_paired == true ? t('ob_family_on') : t('ob_family_later'), _paired == true ? true : null),
      ]),
      const SizedBox(height: Sp.l),
      Material(
        color: p.accentTint,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: const Key('onb_profile'),
          borderRadius: BorderRadius.circular(20),
          onTap: () => pushTitled(context, t('ob_profile_title'), const ProfileScreen()),
          child: Padding(
            padding: const EdgeInsets.all(Sp.l),
            child: Row(children: [
              Icon(Icons.auto_awesome_rounded, color: p.accent),
              const SizedBox(width: Sp.m),
              Expanded(child: Text(t('ob4_profile'), style: th.textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.35))),
              Icon(Icons.chevron_right_rounded, color: p.accent),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// Dashed arc between the two phones on the family step; the dashes march with [t].
class _ArcPainter extends CustomPainter {
  _ArcPainter(this.color, this.t);
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.62)
      ..cubicTo(size.width * 0.34, size.height * 0.2, size.width * 0.66, size.height * 0.2, size.width * 0.8, size.height * 0.62);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const dash = 7.0, gap = 7.0;
    for (final m in path.computeMetrics()) {
      var d = (t * (dash + gap) * 4) % (dash + gap);
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.t != t || old.color != color;
}
