import 'package:flutter/material.dart';

import '../api/home_api.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../l10n/strings_shell.dart';
import '../models/verdict.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/state_message.dart';

/// "Make evidence": builds the evidence pack as soon as it opens, then shows what went in.
/// [alertId] limits it to one past alert; null packs every flagged event of the last 24 hours.
class EvidenceScreen extends StatefulWidget {
  const EvidenceScreen({super.key, this.api = const HomeApi(), this.alertId});
  final HomeApi api;
  final int? alertId;
  @override
  State<EvidenceScreen> createState() => _EvidenceScreenState();
}

enum _Phase { working, empty, failed, done }

class _EvidenceScreenState extends State<EvidenceScreen> {
  _Phase _phase = _Phase.working;
  EvidenceResult? _result;

  @override
  void initState() {
    super.initState();
    _make();
  }

  Future<void> _make() async {
    setState(() => _phase = _Phase.working);
    final r = await widget.api.makeEvidence(id: widget.alertId);
    if (!mounted) return;
    setState(() {
      _result = r;
      _phase = r == null ? _Phase.failed : (r.items.isEmpty ? _Phase.empty : _Phase.done);
    });
  }

  void _toast(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    String t(String k, [Map<String, Object?> a = const {}]) => homeT(lang, k, a);
    return switch (_phase) {
      _Phase.working => StateMessage(loading: true, title: t('ev_working')),
      _Phase.empty => Center(
          child: StateMessage(icon: Icons.inventory_2_outlined, title: t('ev_empty_t'), subtitle: t('ev_empty_s'))),
      _Phase.failed => Center(
          child: StateMessage(icon: Icons.error_outline, title: t('ev_err'), actionLabel: t('retry'), onAction: _make)),
      _Phase.done => _done(context, lang, t),
    };
  }

  Widget _done(BuildContext context, String lang, String Function(String, [Map<String, Object?>]) t) {
    final th = Theme.of(context);
    final cs = th.colorScheme;
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    final items = _result!.items;
    return ListView(padding: const EdgeInsets.all(Sp.l), children: [
      Row(children: [
        Icon(Icons.check_circle, size: 40, color: st.safe),
        const SizedBox(width: Sp.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('ev_done'), key: const Key('evidence_done'), style: th.textTheme.titleLarge),
            Text(t('ev_done_s', {'n': items.length}), style: th.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
      const SizedBox(height: Sp.l),
      FilledButton.icon(
        key: const Key('evidence_share'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
        onPressed: () async {
          if (!await widget.api.shareEvidence()) _toast(t('ev_share_err'));
        },
        icon: const Icon(Icons.ios_share, size: 28),
        label: Text(t('ev_share'), textAlign: TextAlign.center),
      ),
      const SizedBox(height: Sp.l),
      Text(t('ev_included'), style: th.textTheme.titleMedium),
      const SizedBox(height: Sp.s),
      Material(
        color: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.lg), side: BorderSide(color: cs.outline)),
        child: Padding(
          padding: const EdgeInsets.all(Sp.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final a in items)
              Padding(
                padding: const EdgeInsets.only(bottom: Sp.m),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(a.label.icon, size: 28, color: st.solid(a.label)),
                  const SizedBox(width: Sp.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(scamTypeNameIn(a.scamType, lang) ?? t('al_other'), style: th.textTheme.titleSmall),
                      Text('${sourceIn(lang, a.source)} · ${agoIn(lang, a.tsMs)}',
                          style: th.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                ]),
              ),
            Text(t('ev_note'), style: th.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ),
      const SizedBox(height: Sp.l),
      OutlinedButton.icon(
        key: const Key('evidence_dial'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
        onPressed: widget.api.dial1930,
        icon: const Icon(Icons.phone, size: 28),
        label: Text(t('ev_dial'), textAlign: TextAlign.center),
      ),
      const SizedBox(height: Sp.xs),
      Text(t('ev_dial_note'), textAlign: TextAlign.center, style: th.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
    ]);
  }
}
