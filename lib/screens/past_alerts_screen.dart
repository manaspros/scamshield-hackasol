import 'package:flutter/material.dart';

import '../api/home_api.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../l10n/strings_shell.dart';
import '../models/verdict.dart';
import '../theme/tokens.dart';
import '../widgets/state_message.dart';
import '../widgets/status_chip.dart';
import 'evidence_screen.dart';
import 'page_route.dart';

/// Past SCAM / SUSPICIOUS verdicts from the on-device log. The log keeps no message text, so a row shows
/// only the type, source, time and the words that matched.
class PastAlertsScreen extends StatefulWidget {
  const PastAlertsScreen({super.key, this.api = const HomeApi()});
  final HomeApi api;
  @override
  State<PastAlertsScreen> createState() => _PastAlertsScreenState();
}

class _PastAlertsScreenState extends State<PastAlertsScreen> {
  bool _loaded = false;
  List<PastAlert>? _all;
  RiskLabel? _only; // null = All
  AlertSort _sort = AlertSort.newest;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loaded = false);
    final a = await widget.api.alerts();
    if (mounted) setState(() { _all = a; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    String t(String k, [Map<String, Object?> a = const {}]) => homeT(lang, k, a);
    if (!_loaded) return StateMessage(loading: true, title: t('prot_checking'));
    final all = _all;
    if (all == null) {
      return Center(child: StateMessage(icon: Icons.error_outline, title: t('kn_err'), actionLabel: t('retry'), onAction: _load));
    }
    if (all.isEmpty) {
      return Center(child: StateMessage(icon: Icons.verified_user_outlined, title: t('al_empty_t'), subtitle: t('al_empty_s')));
    }
    final shown = sortAlerts(filterAlerts(all, only: _only), _sort);
    Widget chip(Key k, String label, bool sel, VoidCallback on) =>
        ChoiceChip(key: k, label: Text(label), selected: sel, onSelected: (_) => on());
    return ListView(padding: const EdgeInsets.all(Sp.l), children: [
      Wrap(spacing: Sp.s, runSpacing: Sp.xs, children: [
        chip(const Key('alerts_f_all'), t('f_all'), _only == null, () => setState(() => _only = null)),
        chip(const Key('alerts_f_scam'), t('f_scam'), _only == RiskLabel.scam, () => setState(() => _only = RiskLabel.scam)),
        chip(const Key('alerts_f_susp'), t('f_susp'), _only == RiskLabel.suspicious, () => setState(() => _only = RiskLabel.suspicious)),
      ]),
      const SizedBox(height: Sp.xs),
      Wrap(spacing: Sp.s, runSpacing: Sp.xs, children: [
        chip(const Key('alerts_s_new'), t('sort_new'), _sort == AlertSort.newest, () => setState(() => _sort = AlertSort.newest)),
        chip(const Key('alerts_s_risk'), t('sort_risk'), _sort == AlertSort.risk, () => setState(() => _sort = AlertSort.risk)),
      ]),
      const SizedBox(height: Sp.m),
      if (shown.isEmpty) StateMessage(icon: Icons.filter_list_off, title: t('al_none')),
      for (final a in shown)
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.m),
          child: _AlertRow(
            key: Key('alert_${a.id}'),
            alert: a,
            lang: lang,
            onTap: () => pushTitled(context, t('al_detail'), AlertDetail(alert: a, api: widget.api)),
          ),
        ),
    ]);
  }
}

String _why(PastAlert a) => a.triggers.take(3).join(' · ');

class _AlertRow extends StatelessWidget {
  const _AlertRow({super.key, required this.alert, required this.lang, required this.onTap});
  final PastAlert alert;
  final String lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final cs = th.colorScheme;
    final why = _why(alert);
    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.lg), side: BorderSide(color: cs.outline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Sp.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            StatusChip(label: alert.label),
            const SizedBox(height: Sp.s),
            Text(scamTypeNameIn(alert.scamType, lang) ?? homeT(lang, 'al_other'), style: th.textTheme.titleMedium),
            Text('${sourceIn(lang, alert.source)} · ${agoIn(lang, alert.tsMs)}',
                style: th.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            if (why.isNotEmpty) ...[
              const SizedBox(height: Sp.xs),
              Text(why, maxLines: 2, overflow: TextOverflow.ellipsis, style: th.textTheme.bodyMedium),
            ],
          ]),
        ),
      ),
    );
  }
}

/// One alert in full, with "Make evidence for this".
class AlertDetail extends StatelessWidget {
  const AlertDetail({super.key, required this.alert, this.api = const HomeApi()});
  final PastAlert alert;
  final HomeApi api;

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    String t(String k, [Map<String, Object?> a = const {}]) => homeT(lang, k, a);
    final th = Theme.of(context);
    final cs = th.colorScheme;
    return ListView(padding: const EdgeInsets.all(Sp.l), children: [
      Align(alignment: Alignment.centerLeft, child: StatusChip(label: alert.label)),
      const SizedBox(height: Sp.m),
      Text(scamTypeNameIn(alert.scamType, lang) ?? t('al_other'), style: th.textTheme.headlineSmall),
      const SizedBox(height: Sp.xs),
      Text('${sourceIn(lang, alert.source)} · ${agoIn(lang, alert.tsMs)}',
          style: th.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
      Text(t('al_conf', {'p': (alert.confidence * 100).round()}),
          style: th.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: Sp.l),
      Text(t('al_why'), style: th.textTheme.titleMedium),
      const SizedBox(height: Sp.xs),
      Text(alert.triggers.isEmpty ? t('al_no_why') : alert.triggers.join(' · '), style: th.textTheme.bodyLarge),
      const SizedBox(height: Sp.s),
      Text(t('al_privacy'), style: th.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: Sp.xl),
      FilledButton.icon(
        key: const Key('alert_make_evidence'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
        onPressed: () => pushTitled(context, t('ev_title'), EvidenceScreen(api: api, alertId: alert.id)),
        icon: const Icon(Icons.inventory_2, size: 28),
        label: Text(t('al_make'), textAlign: TextAlign.center),
      ),
      const SizedBox(height: Sp.m),
      for (final safe in const [true, false])
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.s),
          child: OutlinedButton(
            key: Key(safe ? 'alert_mark_safe' : 'alert_mark_scam'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
            onPressed: () async {
              final ok = await api.markFeedback(alert.tsMs, safe: safe);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t(!ok ? 'fb_none' : safe ? 'fb_safe_ok' : 'fb_scam_ok'))));
            },
            child: Text(t(safe ? 'fb_safe' : 'fb_scam'), textAlign: TextAlign.center),
          ),
        ),
      Text(t('fb_note'), style: th.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
    ]);
  }
}
