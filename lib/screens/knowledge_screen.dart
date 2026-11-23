import 'package:flutter/material.dart';

import '../api/home_api.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../theme/tokens.dart';
import '../widgets/state_message.dart';

/// "What ScamShield knows about me": the on-device knowledge graph as plain cards.
/// Entities only (brands, senders, counts, dates): the graph never holds message text.
class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key, this.api = const HomeApi()});
  final HomeApi api;
  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  bool _loaded = false;
  Map<Object?, Object?>? _g;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loaded = false);
    final g = await widget.api.graph();
    if (mounted) setState(() { _g = g; _loaded = true; });
  }

  List<Map<Object?, Object?>> _list(String k) =>
      ((_g?[k] as List?) ?? const []).map((e) => (e as Map).cast<Object?, Object?>()).toList();

  static String _title(String brand) => brand.isEmpty ? brand : brand[0].toUpperCase() + brand.substring(1);

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    String t(String k, [Map<String, Object?> a = const {}]) => homeT(lang, k, a);
    final th = Theme.of(context);
    final cs = th.colorScheme;
    if (!_loaded) return StateMessage(loading: true, title: t('prot_checking'));
    final g = _g;
    if (g == null) {
      return Center(child: StateMessage(icon: Icons.error_outline, title: t('kn_err'), actionLabel: t('retry'), onAction: _load));
    }
    final brands = _list('brands'), recent = _list('recent'), senders = _list('senders');
    final personal = (g['personalSenders'] as num?)?.toInt() ?? 0, personalMsgs = (g['personalMessages'] as num?)?.toInt() ?? 0;
    final numbers = (g['numbers'] as num?)?.toInt() ?? 0, upi = (g['upiIds'] as num?)?.toInt() ?? 0;
    if (g['empty'] == true && brands.isEmpty && senders.isEmpty && personal == 0) {
      return ListView(padding: const EdgeInsets.all(Sp.l), children: [
        StateMessage(icon: Icons.hub_outlined, title: t('kn_empty_t'), subtitle: t('kn_empty_s')),
        const SizedBox(height: Sp.xl),
        _deleteButton(t, cs),
      ]);
    }

    String ago(Object? ms) => agoIn(lang, (ms as num?)?.toInt() ?? 0);
    Widget card(String title, List<Widget> rows) => Padding(
          padding: const EdgeInsets.only(bottom: Sp.l),
          child: Material(
            color: cs.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.lg), side: BorderSide(color: cs.outline)),
            child: Padding(
              padding: const EdgeInsets.all(Sp.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Semantics(header: true, child: Text(title, style: th.textTheme.titleMedium)),
                const SizedBox(height: Sp.s),
                ...rows,
              ]),
            ),
          ),
        );
    // One column: a side-by-side date would squeeze the text to nothing at large text sizes.
    Widget row(String main, String sub, {String? trailing}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.xs),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(main, style: th.textTheme.bodyLarge),
            if (sub.isNotEmpty) Text(sub, style: th.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            if (trailing != null) Text(trailing, style: th.textTheme.bodySmall?.copyWith(color: cs.primary)),
          ]),
        );

    return ListView(padding: const EdgeInsets.all(Sp.l), children: [
      Padding(
        padding: const EdgeInsets.only(bottom: Sp.l),
        child: Text(t('kn_intro'), style: th.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
      ),
      if (brands.isNotEmpty)
        card(t('kn_brands'), [
          for (final b in brands)
            row(
              _title('${b['brand']}'),
              [
                for (final e in ((b['types'] as Map?) ?? const {}).entries) '${t('ev_${e.key}')} ${e.value}',
              ].join(' · '),
              trailing: ago(b['lastMs']),
            ),
        ]),
      if (recent.isNotEmpty)
        card(t('kn_recent'), [
          for (final e in recent) row(t('ev_${e['type']}'), _title('${e['brand']}'), trailing: ago(e['tsMs'])),
        ]),
      if (senders.isNotEmpty || personal > 0)
        card(t('kn_senders'), [
          for (final s in senders) row('${s['sender']}', t('kn_msgs', {'n': s['count']}), trailing: ago(s['lastMs'])),
          // Personal numbers are only counted, never listed: the native side sends no digits for them.
          if (personal > 0) row(t('kn_personal', {'n': personal, 'm': personalMsgs}), ''),
        ]),
      if (numbers + upi > 0)
        card(t('kn_contacts'), [
          if (numbers > 0) row(t('kn_numbers', {'n': numbers}), ''),
          if (upi > 0) row(t('kn_upi', {'n': upi}), ''),
        ]),
      Text(t('kn_learned', {'n': g['ingested'] ?? 0}),
          textAlign: TextAlign.center, style: th.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: Sp.xl),
      _deleteButton(t, cs),
    ]);
  }

  Widget _deleteButton(String Function(String, [Map<String, Object?>]) t, ColorScheme cs) => OutlinedButton.icon(
        key: const Key('kn_delete'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(kTouch),
          foregroundColor: cs.error,
          side: BorderSide(color: cs.error),
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
