import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/home_api.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../l10n/strings_shell.dart';
import '../lessons/prefs_store.dart';
import '../lessons/quiz_engine.dart';
import '../models/verdict.dart';
import '../profile/user_profile.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/family_code_card.dart';
import '../widgets/premium.dart';
import 'evidence_screen.dart';
import 'family_screen.dart';
import 'knowledge_screen.dart';
import 'live_feed_screen.dart';
import 'page_route.dart';
import 'past_alerts_screen.dart';
import 'recording_screen.dart';
import 'setup_screen.dart';
import 'try_api_screen.dart';

/// The built-in lessons (assets/lessons/*.json); Home averages their best scores without loading the files.
const kLessonIds = [
  'otp', 'upi_pin', 'atm_pin', 'qr', 'digital_arrest', 'kyc', 'courier', 'loan_app', //
  'electricity_bill', 'sim_swap', 'customer_care', 'upi_collect', 'task_job', 'sextortion', 'lottery', //
  'family_emergency', 'phishing_link',
];

/// Home: greeting, protection status, this week's numbers, recent attacker attempts, quick actions and a daily tip.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.api = const HomeApi(), this.store, this.onOpenLearn, this.now});
  final HomeApi api;
  final QuizStore? store;
  final VoidCallback? onOpenLearn;

  /// Tests only: a fixed clock for the greeting and "this week".
  final DateTime Function()? now;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Protection? _prot;
  List<PastAlert>? _alerts;
  int? _score;
  int _familyEpoch = 0; // bumped after the Family screen closes so the card re-reads the pairing
  late final QuizStore _store = widget.store ?? PrefsQuizStore();

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final p = await widget.api.protection();
    if (mounted) setState(() => _prot = p);
    final a = await widget.api.alerts();
    if (mounted) setState(() => _alerts = a);
    final best = await _store.loadBest();
    final sum = kLessonIds.fold<int>(0, (s, id) => s + (best[id] ?? 0).clamp(0, 100));
    if (mounted) setState(() => _score = (sum / kLessonIds.length).round());
  }

  /// Opens [page] and re-reads status on return (the user may have changed a permission there).
  Future<void> _open(String title, Widget page) async {
    await pushTitled(context, title, page);
    if (!mounted) return;
    setState(() => _familyEpoch++);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    String t(String k, [Map<String, Object?> a = const {}]) => homeT(lang, k, a);
    final th = Theme.of(context);
    final p = palOf(context);
    final now = _now;
    final weekAgo = now.millisecondsSinceEpoch - 7 * 86400000;
    final alerts = sortAlerts(_alerts ?? const [], AlertSort.newest);
    final week = alerts.where((a) => a.tsMs >= weekAgo).toList();
    final top = _topType(alerts, lang);
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.xl),
        children: [
          ValueListenableBuilder<UserProfile>(
            valueListenable: ProfileStore.profile,
            builder: (_, prof, _) => _greeting(th, p, lang, now, prof.firstName),
          ),
          const SizedBox(height: Sp.l),
          _hero(th, lang),
          PSection(title: t('week')),
          _row(big, [
            _stat(th, p, '${week.length}', t('st_blocked'), week.isEmpty ? p.ink : _st(context).scam, const Key('home_stat_blocked')),
            _stat(th, p, top ?? '—', t('st_top'), p.ink, const Key('home_stat_top')),
            _stat(th, p, _score == null ? '—' : '$_score', t('st_score'), p.accent, const Key('home_stat_score')),
          ]),
          PSection(
            title: t('recent'),
            action: t('see_all'),
            actionKey: const Key('home_see_all'),
            onAction: () => _open(t('al_title'), PastAlertsScreen(api: widget.api)),
          ),
          _recent(th, p, lang, alerts.take(3).toList()),
          PSection(title: t('quick')),
          ..._grid(big, [
            _Quick(key: const Key('home_check'), icon: Icons.fact_check_rounded, label: t('qa_check'),
                onTap: () => _open(shellT(lang, 'tab_check'), const TryApiScreen())),
            _Quick(key: const Key('home_live'), icon: Icons.graphic_eq_rounded, label: t('qa_live'),
                onTap: () => _open(shellT(lang, 'tab_live'), const LiveFeedScreen())),
            _Quick(key: const Key('home_recording'), icon: Icons.mic_rounded, label: t('qa_rec'),
                onTap: () => _open(shellT(lang, 'recording_title'), const RecordingScreen())),
            _Quick(key: const Key('home_make_evidence'), icon: Icons.inventory_2_rounded, label: t('act_evidence'),
                onTap: () => _open(t('ev_title'), EvidenceScreen(api: widget.api))),
            _Quick(key: const Key('home_about_me'), icon: Icons.hub_rounded, label: t('qa_know'),
                onTap: () => _open(t('kn_title'), KnowledgeScreen(api: widget.api))),
            _Quick(key: const Key('home_past_alerts'), icon: Icons.history_rounded, label: t('qa_alerts'),
                onTap: () => _open(t('al_title'), PastAlertsScreen(api: widget.api))),
          ]),
          const SizedBox(height: Sp.l),
          _tip(th, p, lang, now),
          const SizedBox(height: Sp.l),
          FamilyCodeCard(
            key: ValueKey(_familyEpoch),
            api: widget.api,
            onOpen: () => _open(t('fam_title'), const FamilyScreen()),
          ),
        ],
      ),
    );
  }

  StatusColors _st(BuildContext c) => Theme.of(c).extension<StatusColors>() ?? StatusColors.light;

  /// Most frequent scam type among all logged alerts, as a short chip label.
  String? _topType(List<PastAlert> all, String lang) {
    final n = <String, int>{};
    for (final a in all) {
      if (a.scamType != null) n[a.scamType!] = (n[a.scamType!] ?? 0) + 1;
    }
    if (n.isEmpty) return null;
    final k = n.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    return k == 'KYC' || k == 'OTP' || k == 'QR' ? k : scamTypeNameIn(k, lang);
  }

  Widget _greeting(ThemeData th, Pal p, String lang, DateTime now, String? name) {
    final g = homeT(lang, greetingKey(now));
    final hello = name == null ? g : homeT(lang, 'greet_name', {'g': g, 'name': name});
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(longDateIn(lang, now), style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
      const SizedBox(height: 2),
      Semantics(
        header: true,
        child: Text(hello,
            key: const Key('home_greeting'),
            style: th.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 30, height: 1.2)),
      ),
      const SizedBox(height: 2),
      Text(homeT(lang, 'home_sub'), style: th.textTheme.bodyMedium?.copyWith(color: p.muted, fontSize: 17)),
    ]);
  }

  Widget _row(bool big, List<Widget> tiles) {
    if (big) {
      return Column(children: [
        for (final w in tiles) Padding(padding: const EdgeInsets.only(bottom: Sp.s + 2), child: w),
      ]);
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: Sp.s + 2),
          Expanded(child: tiles[i]),
        ],
      ]),
    );
  }

  List<Widget> _grid(bool big, List<Widget> tiles) {
    final per = big ? 1 : 2;
    return [
      for (var i = 0; i < tiles.length; i += per)
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.s + 2),
          child: _row(false, [for (var k = i; k < math.min(i + per, tiles.length); k++) tiles[k]]),
        ),
    ];
  }

  Widget _stat(ThemeData th, Pal p, String v, String label, Color c, Key key) => PCard(
        key: key,
        padding: const EdgeInsets.all(Sp.m + 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(v, style: th.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: c, height: 1.1)),
          ),
          const SizedBox(height: Sp.xs),
          Text(label, style: th.textTheme.bodySmall?.copyWith(color: p.muted, height: 1.25)),
        ]),
      );

  Widget _recent(ThemeData th, Pal p, String lang, List<PastAlert> list) {
    final st = _st(context);
    if (list.isEmpty) {
      return PCard(
        key: const Key('home_recent_empty'),
        child: Row(children: [
          IconBadge(icon: Icons.verified_rounded, color: st.safe),
          const SizedBox(width: Sp.m),
          Expanded(child: Text(homeT(lang, 'no_attempts'), style: th.textTheme.bodyLarge?.copyWith(fontSize: 17))),
        ]),
      );
    }
    return PGroup(children: [
      for (var i = 0; i < list.length; i++)
        Builder(builder: (context) {
          final a = list[i];
          final scam = a.label == RiskLabel.scam;
          final c = st.solid(a.label);
          final title = scamTypeNameIn(a.scamType, lang) ?? homeT(lang, 'al_other');
          final sub = '${sourceIn(lang, a.source)} · ${agoIn(lang, a.tsMs, nowMs: _now.millisecondsSinceEpoch)}';
          return InkWell(
            key: Key('home_attempt_${a.id}'),
            onTap: () => _open(homeT(lang, 'al_detail'), AlertDetail(alert: a, api: widget.api)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.m + 2),
              decoration: BoxDecoration(
                border: i == list.length - 1 ? null : Border(bottom: BorderSide(color: p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF0F0F2))),
              ),
              child: Row(children: [
                IconBadge(icon: _sourceIcon(a.source), color: c, tint: st.tint(a.label)),
                const SizedBox(width: Sp.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: th.textTheme.titleSmall?.copyWith(fontSize: 17)),
                    Text(sub, style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
                  ]),
                ),
                const SizedBox(width: Sp.s),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: st.tint(a.label), borderRadius: BorderRadius.circular(Rad.pill)),
                  child: Text(homeT(lang, scam ? 'chip_scam' : 'chip_susp'),
                      style: th.textTheme.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ]),
            ),
          );
        }),
    ]);
  }

  IconData _sourceIcon(String s) => switch (s) {
        'caption' || 'signal' => Icons.call_rounded,
        'recording' => Icons.mic_rounded,
        'whatsapp' => Icons.forum_rounded,
        _ => Icons.sms_rounded,
      };

  Widget _tip(ThemeData th, Pal p, String lang, DateTime now) {
    final day = now.difference(DateTime(2024)).inDays;
    final tip = homeT(lang, 'tip_${day % kTipCount}');
    return Material(
      color: p.accentTint,
      borderRadius: BorderRadius.circular(RadX.card),
      child: InkWell(
        key: const Key('home_tip'),
        borderRadius: BorderRadius.circular(RadX.card),
        onTap: widget.onOpenLearn,
        child: Padding(
          padding: const EdgeInsets.all(Sp.l + 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lightbulb_rounded, color: p.accent, size: 28),
            const SizedBox(width: Sp.m + 2),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(homeT(lang, 'tip'), style: th.textTheme.labelMedium?.copyWith(color: p.accent, fontWeight: FontWeight.w700)),
                const SizedBox(height: Sp.xs),
                Text(tip, style: th.textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.35)),
                if (widget.onOpenLearn != null) ...[
                  const SizedBox(height: Sp.s),
                  Text('${homeT(lang, 'tip_link')} →', style: th.textTheme.titleSmall?.copyWith(color: p.accent)),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// "You're protected", or amber with the first thing that is off and one Fix button.
  Widget _hero(ThemeData th, String lang) {
    final st = _st(context);
    final p = palOf(context);
    final prot = _prot;
    final off = prot?.firstOff;
    final ok = prot != null && prot.known && off == null;
    final label = off != null ? RiskLabel.suspicious : RiskLabel.safe;
    final color = st.solid(label);
    final text = prot == null || (off == null && !ok)
        ? homeT(lang, 'prot_checking')
        : off != null
            ? homeT(lang, 'prot_off', {'what': homeT(lang, off)})
            : homeT(lang, 'prot_ok');
    final flags = [prot?.call, prot?.messages, prot?.alerts];
    final fix = off == null
        ? null
        : TextButton(
            key: const Key('home_fix'),
            style: TextButton.styleFrom(minimumSize: const Size(kTouch, kTouch), foregroundColor: color),
            onPressed: () async {
              await openSetupPage(context);
              _refresh();
            },
            child: Text(homeT(lang, 'fix')),
          );
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Semantics(
      container: true,
      liveRegion: true,
      child: PCard(
        key: const Key('home_hero'),
        padding: const EdgeInsets.all(Sp.l + 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconBadge(
              icon: off != null ? Icons.gpp_maybe_rounded : Icons.verified_user_rounded,
              color: color,
              tint: st.tint(label),
              size: 60,
              iconSize: 34,
            ),
            const SizedBox(width: Sp.l),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text, key: const Key('home_hero_text'), style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: off != null ? color : null)),
                if (ok) Text(homeT(lang, 'checks_on0'), style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
              ]),
            ),
            if (!big && fix != null) fix,
          ]),
          if (big && fix != null) Align(alignment: Alignment.centerRight, child: fix),
          const SizedBox(height: Sp.l),
          Row(children: [
            for (var i = 0; i < flags.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 6,
                  decoration: BoxDecoration(
                    color: flags[i] == null ? p.hairline : flags[i]! ? st.safe : st.suspicious,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

/// One quick-action tile: tinted icon over a short label.
class _Quick extends StatelessWidget {
  const _Quick({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    final th = Theme.of(context);
    return Semantics(
      button: true,
      child: PCard(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBadge(icon: icon, color: p.accent, tint: p.accentTint, size: 42, iconSize: 22),
          const SizedBox(height: Sp.s + 2),
          Text(label, style: th.textTheme.titleSmall?.copyWith(fontSize: 17, height: 1.25)),
        ]),
      ),
    );
  }
}
