import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/home_api.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/a11y.dart';
import '../widgets/premium.dart';
import '../widgets/state_message.dart';

/// "What ScamShield knows about me": the on-device knowledge graph as plain cards, under an animated hero.
/// Entities only (brands, senders, counts, dates): the graph never holds message text.
class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key, this.api = const HomeApi()});
  final HomeApi api;
  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> with SingleTickerProviderStateMixin {
  bool _loaded = false;
  Map<Object?, Object?>? _g;
  late final _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void initState() {
    super.initState();
    _load();
    // Gentle float and pulse; still when the system asks for reduced motion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) _loop.repeat(count: 6);
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loaded = false);
    final g = await widget.api.graph();
    if (mounted) setState(() { _g = g; _loaded = true; });
  }

  List<Map<Object?, Object?>> _list(String k) =>
      ((_g?[k] as List?) ?? const []).map((e) => (e as Map).cast<Object?, Object?>()).toList();

  static String _title(String brand) => brand.isEmpty ? brand : brand[0].toUpperCase() + brand.substring(1);

  /// A stable, readable colour per brand for its avatar.
  static Color _brandColor(String brand) {
    const c = [Color(0xFF1A4D9E), Color(0xFFB45309), Color(0xFF0F7B3A), Color(0xFF7C3AED), Color(0xFFBE185D), Color(0xFF0E7490)];
    return c[brand.codeUnits.fold<int>(0, (a, b) => a + b) % c.length];
  }

  double _bob(double phase) => math.sin((_loop.value + phase) * 2 * math.pi) * 5;

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    String t(String k, [Map<String, Object?> a = const {}]) => homeT(lang, k, a);
    final th = Theme.of(context);
    final p = palOf(context);
    final cs = th.colorScheme;
    if (!_loaded) return StateMessage(loading: true, title: t('prot_checking'));
    final g = _g;
    if (g == null) {
      return Center(child: StateMessage(icon: Icons.error_outline, title: t('kn_err'), actionLabel: t('retry'), onAction: _load));
    }
    final brands = _list('brands'), recent = _list('recent'), senders = _list('senders');
    final personal = (g['personalSenders'] as num?)?.toInt() ?? 0, personalMsgs = (g['personalMessages'] as num?)?.toInt() ?? 0;
    final numbers = (g['numbers'] as num?)?.toInt() ?? 0, upi = (g['upiIds'] as num?)?.toInt() ?? 0;
    final learned = (g['ingested'] as num?)?.toInt() ?? 0;
    if (g['empty'] == true && brands.isEmpty && senders.isEmpty && personal == 0) {
      return ListView(padding: const EdgeInsets.all(Sp.l), children: [
        _hero(th, p, const []),
        StateMessage(icon: Icons.hub_outlined, title: t('kn_empty_t'), subtitle: t('kn_empty_s')),
        const SizedBox(height: Sp.xl),
        _deleteButton(t, cs),
      ]);
    }

    String ago(Object? ms) => agoIn(lang, (ms as num?)?.toInt() ?? 0);
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    var order = 0;
    Widget card(String title, IconData icon, Color c, List<Widget> rows) => _Enter(
          delay: 120 + 90 * order++,
          child: Padding(
            padding: const EdgeInsets.only(bottom: Sp.m + 2),
            child: PCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  IconBadge(icon: icon, color: c, tint: c.withValues(alpha: p.isDark ? 0.2 : 0.12), size: 34, iconSize: 19),
                  const SizedBox(width: Sp.m),
                  Expanded(child: Semantics(header: true, child: Text(title, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)))),
                ]),
                const SizedBox(height: Sp.s),
                for (final (i, r) in rows.indexed) ...[
                  if (i > 0) Divider(height: 1, color: p.hairline),
                  r,
                ],
              ]),
            ),
          ),
        );
    // One column: a side-by-side date would squeeze the text to nothing at large text sizes.
    Widget row(String main, String sub, {String? trailing, Widget? leading}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.s),
          child: Row(children: [
            if (leading != null) ...[leading, const SizedBox(width: Sp.m)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(main, style: th.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                if (sub.isNotEmpty) Text(sub, style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
                if (trailing != null) Text(trailing, style: th.textTheme.bodySmall?.copyWith(color: p.accent, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        );
    Widget avatar(String brand) => CircleAvatar(
          radius: 19,
          backgroundColor: _brandColor(brand),
          child: Text(brand.isEmpty ? '•' : brand[0].toUpperCase(), style: th.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
        );

    return ListView(padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.xl), children: [
      _hero(th, p, [for (final b in brands.take(3)) _title('${b['brand']}')]),
      _Enter(
        child: Column(children: [
          Semantics(header: true, child: Text(t('kn_hero'), textAlign: TextAlign.center, style: th.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
          const SizedBox(height: Sp.xs),
          Text(t('kn_intro'), textAlign: TextAlign.center, style: th.textTheme.bodyLarge?.copyWith(color: p.muted, height: 1.4)),
        ]),
      ),
      const SizedBox(height: Sp.l),
      _Enter(
        delay: 60,
        child: Row(children: [
          _stat(th, p, learned, t('kn_s_msgs'), p.accent),
          const SizedBox(width: Sp.s),
          _stat(th, p, brands.length, t('kn_s_brands'), st.safe),
          const SizedBox(width: Sp.s),
          _stat(th, p, senders.length + personal, t('kn_s_senders'), st.suspicious),
        ]),
      ),
      const SizedBox(height: Sp.l),
      if (brands.isNotEmpty)
        card(t('kn_brands'), Icons.account_balance_rounded, p.accent, [
          for (final b in brands)
            row(
              _title('${b['brand']}'),
              [
                for (final e in ((b['types'] as Map?) ?? const {}).entries) '${t('ev_${e.key}')} ${e.value}',
              ].join(' · '),
              trailing: ago(b['lastMs']),
              leading: avatar('${b['brand']}'),
            ),
        ]),
      if (recent.isNotEmpty)
        card(t('kn_recent'), Icons.history_rounded, st.safe, [
          for (final e in recent) row(t('ev_${e['type']}'), _title('${e['brand']}'), trailing: ago(e['tsMs'])),
        ]),
      if (senders.isNotEmpty || personal > 0)
        card(t('kn_senders'), Icons.forum_rounded, st.suspicious, [
          for (final s in senders) row('${s['sender']}', t('kn_msgs', {'n': s['count']}), trailing: ago(s['lastMs'])),
          // Personal numbers are only counted, never listed: the native side sends no digits for them.
          if (personal > 0) row(t('kn_personal', {'n': personal, 'm': personalMsgs}), ''),
        ]),
      if (numbers + upi > 0)
        card(t('kn_contacts'), Icons.contact_phone_rounded, p.accent, [
          if (numbers > 0) row(t('kn_numbers', {'n': numbers}), ''),
          if (upi > 0) row(t('kn_upi', {'n': upi}), ''),
        ]),
      Text(t('kn_learned', {'n': learned}), textAlign: TextAlign.center, style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
      const SizedBox(height: Sp.xl),
      _deleteButton(t, cs),
    ]);
  }

  Widget _stat(ThemeData th, Pal p, int n, String label, Color c) => Expanded(
        child: PCard(
          padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: Sp.m + 2),
          radius: 20,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: n),
              duration: motion(context, const Duration(milliseconds: 1400)),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('$v', style: th.textTheme.headlineSmall?.copyWith(color: c, fontWeight: FontWeight.w800)),
              ),
            ),
            Text(label, maxLines: 2, style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
          ]),
        ),
      );

  /// Rings, an expanding pulse, a hub tile and up to three floating brand chips (like onboarding's welcome).
  Widget _hero(ThemeData th, Pal p, List<String> chips) {
    Widget chip(String text, double phase) => AnimatedBuilder(
          animation: _loop,
          builder: (_, child) => Transform.translate(offset: Offset(0, _bob(phase)), child: child),
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 6, Sp.m, 6),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16), boxShadow: Elev.island(th.brightness)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: _brandColor(text.toLowerCase()),
                child: Text(text[0].toUpperCase(), style: th.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(text, overflow: TextOverflow.ellipsis, style: th.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        );
    return ExcludeSemantics(
      child: SizedBox(
        height: 250,
        child: Stack(alignment: Alignment.center, children: [
          Container(width: 228, height: 228, decoration: BoxDecoration(color: p.accent.withValues(alpha: p.isDark ? 0.10 : 0.06), shape: BoxShape.circle)),
          Container(width: 172, height: 172, decoration: BoxDecoration(color: p.accent.withValues(alpha: p.isDark ? 0.18 : 0.10), shape: BoxShape.circle)),
          AnimatedBuilder(
            animation: _loop,
            builder: (_, _) {
              final v = (_loop.value * 1.3) % 1.0;
              return Opacity(
                opacity: (1 - v) * 0.6,
                child: Transform.scale(
                  scale: 0.85 + v * 0.55,
                  child: Container(width: 140, height: 140, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.accent, width: 2))),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _loop,
            builder: (_, child) => Transform.rotate(angle: _loop.value * 2 * math.pi, child: child),
            child: SizedBox(
              width: 200,
              height: 200,
              child: Stack(children: [
                Positioned(top: 0, left: 96, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle))),
                Positioned(bottom: 0, left: 97, child: Container(width: 6, height: 6, decoration: BoxDecoration(color: (th.extension<StatusColors>() ?? StatusColors.light).safe, shape: BoxShape.circle))),
              ]),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: motion(context, const Duration(milliseconds: 700)),
            curve: Curves.elasticOut,
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: p.accent,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.38), blurRadius: 36, offset: const Offset(0, 16))],
              ),
              child: Icon(Icons.hub_rounded, color: p.onAccent, size: 54),
            ),
          ),
          if (chips.isNotEmpty) Positioned(left: 0, top: 26, child: chip(chips[0], 0)),
          if (chips.length > 1) Positioned(right: 0, top: 96, child: chip(chips[1], 0.33)),
          if (chips.length > 2) Positioned(left: 14, bottom: 18, child: chip(chips[2], 0.66)),
        ]),
      ),
    );
  }

  Widget _deleteButton(String Function(String, [Map<String, Object?>]) t, ColorScheme cs) => OutlinedButton.icon(
        key: const Key('kn_delete'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(kTouch),
          foregroundColor: cs.error,
          side: BorderSide(color: cs.error),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: () => _confirmDelete(t),
        icon: const Icon(Icons.delete_outline),
        label: Text(t('kn_del'), textAlign: TextAlign.center),
      );

  Future<void> _confirmDelete(String Function(String, [Map<String, Object?>]) t) async {
    var alerts = false;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(t('kn_del_t')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('kn_del_b')),
            CheckboxListTile(
              key: const Key('kn_del_alerts'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: alerts,
              onChanged: (v) => setD(() => alerts = v ?? false),
              title: Text(t('kn_del_alerts')),
            ),
          ]),
          actions: [
            TextButton(key: const Key('kn_del_cancel'), onPressed: () => Navigator.pop(ctx, false), child: Text(t('kn_cancel'))),
            TextButton(
              key: const Key('kn_del_confirm'),
              style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('kn_del_ok')),
            ),
          ],
        ),
      ),
    );
    if (yes != true) return;
    final ok = await widget.api.deleteData(alerts: alerts);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(ok ? 'kn_deleted' : 'kn_del_err'))));
    if (ok) await _load();
  }
}

/// Fades and slides a card in once, [delay] ms after it first builds.
class _Enter extends StatelessWidget {
  const _Enter({required this.child, this.delay = 0});
  final Widget child;
  final int delay;

  @override
  Widget build(BuildContext context) {
    final total = motion(context, Duration(milliseconds: 450 + delay));
    final start = total.inMilliseconds == 0 ? 0.0 : delay / (450 + delay);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      builder: (_, v, child) {
        final k = Curves.easeOutCubic.transform(((v - start) / (1 - start)).clamp(0.0, 1.0));
        return Opacity(opacity: k, child: Transform.translate(offset: Offset(0, 18 * (1 - k)), child: child));
      },
      child: child,
    );
  }
}
