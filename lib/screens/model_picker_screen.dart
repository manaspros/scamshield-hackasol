import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/llm_api.dart';
import '../api/model_api.dart';
import '../api/model_catalog.dart';
import '../api/text_api.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../l10n/strings_profile.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/island.dart';
import '../widgets/premium.dart';

/// Pick which on-device model to download. The list comes from the online models.json (cached, with a built-in
/// fallback), each download link is checked live, and the recommendation follows this phone's RAM and free space.
class ModelPickerScreen extends StatefulWidget {
  const ModelPickerScreen({super.key, this.api = const ModelApi(), this.listenToEvents = true, this.syncOnOpen = true});
  final ModelApi api;

  /// Tests switch the native event stream and the network sync off.
  final bool listenToEvents, syncOnOpen;

  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen> {
  DeviceInfo _dev = const DeviceInfo();
  ModelState _state = const ModelState();
  String? _picked;
  bool _wifiOnly = true;
  Map<Object?, Object?> _dl = const {};
  StreamSubscription<Map<Object?, Object?>>? _sub;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    for (final n in [ModelCatalogStore.models, ModelCatalogStore.links, ModelCatalogStore.updated, ModelCatalogStore.refreshing]) {
      n.addListener(_changed);
    }
    _load();
    if (widget.syncOnOpen) ModelCatalogStore.sync();
    if (widget.listenToEvents) {
      try {
        _sub = TextApi.events.listen((e) {
          if (!mounted) return;
          if (e['type'] == 'download') {
            setState(() => _dl = e);
            if (e['status'] == 'INSTALLED') _load();
          } else if (e['type'] == 'model') {
            _load();
          }
        }, onError: (_) {});
      } on MissingPluginException {
        // tests / non-Android
      }
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final n in [ModelCatalogStore.models, ModelCatalogStore.links, ModelCatalogStore.updated, ModelCatalogStore.refreshing]) {
      n.removeListener(_changed);
    }
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final dev = await widget.api.device();
    final st = await widget.api.state();
    Map<Object?, Object?> settings = const {};
    Map<Object?, Object?> dl = const {};
    try {
      settings = await TextApi.getSettings();
      dl = await TextApi.downloadStatus();
    } on MissingPluginException {
      // keep defaults
    } on PlatformException {
      // keep defaults
    }
    if (!mounted) return;
    LlmStatus.ready.value = st.ready;
    setState(() {
      _dev = dev;
      _state = st;
      _wifiOnly = settings['wifiOnly'] != false;
      _dl = dl;
      _loaded = true;
    });
  }

  String _t(String k, [Map<String, Object?> a = const {}]) => profileT(AppLanguage.of(context), k, a);

  List<ModelSpec> get _catalog => ModelCatalogStore.models.value;

  String get _recId => recommendModelId(_catalog, _dev);

  /// The picked model: the user's choice, else the one in use, else the recommendation.
  ModelSpec get _sel {
    final c = _catalog;
    final id = _picked ?? _state.idIn(c) ?? _recId;
    return c.firstWhere((m) => m.id == id, orElse: () => c.first);
  }

  LinkStatus _link(ModelSpec m) => m.url == null ? LinkStatus.none : ModelCatalogStore.links.value[m.id] ?? LinkStatus.checking;

  bool _inUse(ModelSpec m) => _state.ready && _state.idIn(_catalog) == m.id;

  /// A model can be chosen when it is already on the phone, or its link is not known to be broken.
  bool _selectable(ModelSpec m) =>
      _state.isInstalled(m) || (m.url != null && _link(m) != LinkStatus.broken);

  bool get _downloading => const {'RUNNING', 'PENDING', 'PAUSED'}.contains('${_dl['status']}');

  /// "555 MB · balanced · Hindi support": the note from models.json, else the built-in tier wording.
  String _line(ModelSpec m, String lang) {
    final n = m.noteIn(lang) ?? (const {'fast', 'balanced', 'best'}.contains(m.tier) ? _t('m_${m.tier}') : null);
    return n == null ? m.sizeLabel : '${m.sizeLabel} · $n';
  }

  /// (text, colour) for the live link line.
  (String, Color) _linkLine(ModelSpec m) {
    final p = palOf(context);
    final st = Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
    if (_inUse(m)) return (_t('m_in_use'), st.safe);
    if (_state.isInstalled(m)) return (_t('m_installed'), p.accent);
    return switch (_link(m)) {
      LinkStatus.ok => (_t('m_link_ok'), st.safe),
      LinkStatus.checking => (_t('m_link_checking'), p.muted),
      LinkStatus.broken => (_t('m_link_bad'), st.scam),
      LinkStatus.offline => (_t('m_link_offline'), p.muted),
      LinkStatus.none => (_t('m_link_none'), p.muted),
    };
  }

  /// Badge: recommendation, or why it does not suit this phone.
  (String, Color, Color)? _tag(ModelSpec m) {
    final st = Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
    final b = blockFor(m, _dev);
    if (b == ModelBlock.lowRam) return (_t('m_low_ram', {'n': (m.minRamMb / 1000).round()}), st.suspicious, st.suspicious.withValues(alpha: 0.14));
    if (b == ModelBlock.lowStorage) return (_t('m_low_storage', {'n': m.sizeLabel}), st.suspicious, st.suspicious.withValues(alpha: 0.14));
    if (_link(m) == LinkStatus.broken && !_state.isInstalled(m)) return (_t('m_unavailable'), st.scam, st.scam.withValues(alpha: 0.14));
    if (m.id == _recId) return (_t('m_rec'), st.safe, st.safe.withValues(alpha: 0.14));
    return null;
  }

  Future<void> _act() async {
    final m = _sel;
    if (_state.isInstalled(m)) {
      final s = await widget.api.select(m);
      if (!mounted) return;
      setState(() => _state = s);
      LlmStatus.ready.value = s.ready;
      showIsland(context, _t('m_switched'), tone: IslandTone.success);
      return;
    }
    if (blockFor(m, _dev) == ModelBlock.lowRam) {
      final go = await showIslandSheet<bool>(context, builder: (ctx) {
        final th = Theme.of(ctx);
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_t('m_heavy_t'), style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: Sp.s),
          Text(_t('m_heavy_b'), style: th.textTheme.bodyLarge),
          const SizedBox(height: Sp.l),
          FilledButton(key: const Key('mp_heavy_go'), onPressed: () => Navigator.pop(ctx, true), child: Text(_t('m_try'))),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('cancel'))),
        ]);
      });
      if (go != true || !mounted) return;
    }
    final r = await widget.api.download(m);
    if (!mounted) return;
    setState(() => _dl = r);
    if (r['status'] == 'ERROR') {
      showIsland(context, '${r['message']}', tone: IslandTone.danger);
    } else {
      showIsland(context, _t('m_started'), tone: IslandTone.info, icon: Icons.download_rounded);
    }
  }

  Future<void> _import() async {
    try {
      await TextApi.importModel();
    } on PlatformException catch (e) {
      if (mounted) showIsland(context, '${e.message}', tone: IslandTone.danger);
    } on MissingPluginException {
      // not on Android
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final p = palOf(context);
    final lang = AppLanguage.of(context);
    final sel = _sel;
    final installed = _state.isInstalled(sel);
    final inUse = _inUse(sel);
    final canAct = _loaded && !_downloading && !inUse && _selectable(sel);
    final upd = ModelCatalogStore.updated.value;
    final busy = ModelCatalogStore.refreshing.value;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.xl),
      children: [
        Text(_t('m_intro'), style: th.textTheme.bodyLarge?.copyWith(color: p.muted, fontSize: 17)),
        const SizedBox(height: Sp.l),
        _deviceCard(th, p),
        const SizedBox(height: Sp.l + 2),
        Row(children: [
          Expanded(child: Text(_t('m_model'), style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          Flexible(
            child: TextButton.icon(
              key: const Key('mp_refresh'),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 40),
                backgroundColor: p.accentTint,
                padding: const EdgeInsets.symmetric(horizontal: Sp.m),
                textStyle: th.textTheme.labelMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              onPressed: busy ? null : ModelCatalogStore.sync,
              icon: busy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                upd == null ? _t('m_builtin') : _t('m_updated', {'t': agoIn(lang, upd.millisecondsSinceEpoch).toLowerCase()}),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ]),
        const SizedBox(height: Sp.s),
        IslandMenu<String>(
          matchAnchorWidth: true,
          alignEnd: false,
          onSelected: (id) => setState(() => _picked = id),
          items: [
            for (final m in _catalog)
              IslandMenuItem(
                key: Key('mp_opt_${m.id}'),
                value: m.id,
                label: m.isNew ? '${m.name}  ·  ${_t('m_new')}' : m.name,
                caption: '${_line(m, lang)}\n${_linkLine(m).$1}',
                selected: m.id == sel.id,
                enabled: _selectable(m),
                leading: _chipIcon(m, m.id == sel.id),
                trailing: m.id == sel.id ? null : (_tag(m) == null ? null : _tagChip(th, _tag(m)!)),
              ),
          ],
          builder: (context, open, toggle) => Material(
            color: p.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: open ? p.accent : p.hairline, width: open ? 2 : 1),
            ),
            child: InkWell(
              key: const Key('mp_dropdown'),
              borderRadius: BorderRadius.circular(20),
              onTap: toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.m),
                child: Row(children: [
                  _chipIcon(sel, true),
                  const SizedBox(width: Sp.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(sel.name, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      if (_tag(sel) case final tg?) _tagChip(th, tg),
                    ]),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: p.ink, size: 28),
                  ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: Sp.s),
        Text(_line(sel, lang), style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
        const SizedBox(height: 2),
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: _linkLine(sel).$2, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(_linkLine(sel).$1,
                key: const Key('mp_link'), style: th.textTheme.bodySmall?.copyWith(color: _linkLine(sel).$2, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: Sp.l),
        Container(
          padding: const EdgeInsets.all(Sp.m + 2),
          decoration: BoxDecoration(color: p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFEEEEF1), borderRadius: BorderRadius.circular(18)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.public_rounded, color: p.accent, size: 22),
            const SizedBox(width: Sp.m),
            Expanded(child: Text(_t('m_online_note'), style: th.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: 14))),
          ]),
        ),
        const SizedBox(height: Sp.l),
        if (_downloading) _progress(th, p),
        FilledButton.icon(
          key: const Key('mp_action'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
          onPressed: canAct ? _act : null,
          icon: Icon(installed ? Icons.check_circle_rounded : Icons.download_rounded),
          label: Text(inUse
              ? _t('m_in_use')
              : installed
                  ? _t('m_use')
                  : _selectable(sel)
                      ? _t('m_download', {'s': sel.sizeLabel})
                      : _t('m_unavailable')),
        ),
        if (_downloading)
          TextButton(
            key: const Key('mp_cancel'),
            onPressed: () async {
              try {
                await TextApi.cancelDownload();
              } on MissingPluginException {
                // nothing to cancel
              }
              if (mounted) setState(() => _dl = const {});
            },
            child: Text(_t('m_cancel')),
          ),
        const SizedBox(height: Sp.s),
        Row(children: [
          Icon(Icons.wifi_rounded, size: 18, color: p.muted),
          const SizedBox(width: Sp.xs),
          Expanded(child: Text(_t(_wifiOnly ? 'm_wifi' : 'm_any'), style: th.textTheme.bodySmall?.copyWith(color: p.muted))),
          Flexible(child: TextButton(key: const Key('mp_import'), onPressed: _import, child: Text(_t('m_import'), textAlign: TextAlign.end))),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: Sp.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.folder_outlined, size: 18, color: p.muted),
            const SizedBox(width: Sp.xs),
            Expanded(child: Text(_t('m_saved_to'), style: th.textTheme.bodySmall?.copyWith(color: p.muted))),
          ]),
        ),
      ],
    );
  }

  Widget _chipIcon(ModelSpec m, bool on) {
    final p = palOf(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: on ? p.accent : (p.isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF0F0F2)), borderRadius: BorderRadius.circular(12)),
      child: Icon(Icons.memory_rounded, color: on ? p.onAccent : p.ink, size: 22),
    );
  }

  Widget _tagChip(ThemeData th, (String, Color, Color) t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: t.$3, borderRadius: BorderRadius.circular(Rad.pill)),
        child: Text(t.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: th.textTheme.labelSmall?.copyWith(color: t.$2, fontWeight: FontWeight.w700, fontSize: 13)),
      );

  Widget _deviceCard(ThemeData th, Pal p) {
    Widget cell(String v, String k) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(Sp.m),
            decoration: BoxDecoration(color: p.isDark ? const Color(0xFF2C2C2E) : p.page, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              Text(k, style: th.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: 14)),
            ]),
          ),
        );
    return PCard(
      key: const Key('mp_device'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.smartphone_rounded, color: p.accent, size: 28),
          const SizedBox(width: Sp.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_t('m_phone'), style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(_dev.phoneLabel.isEmpty ? _t('m_unknown') : _dev.phoneLabel, style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
            ]),
          ),
        ]),
        const SizedBox(height: Sp.m),
        Row(children: [
          cell(_dev.ramLabel, _t('m_ram')),
          const SizedBox(width: Sp.s),
          cell(_dev.soc.isEmpty ? '—' : _dev.soc, _t('m_chip')),
          const SizedBox(width: Sp.s),
          cell(_dev.storageLabel, _t('m_free')),
        ]),
      ]),
    );
  }

  Widget _progress(ThemeData th, Pal p) {
    final done = (_dl['done'] as num?)?.toDouble() ?? 0;
    final total = (_dl['total'] as num?)?.toDouble() ?? 0;
    String mb(double b) => (b / (1024 * 1024)).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Rad.pill),
          child: LinearProgressIndicator(key: const Key('mp_progress'), value: total > 0 ? done / total : null, minHeight: 8),
        ),
        const SizedBox(height: Sp.xs),
        Text('${total > 0 ? '${mb(done)} / ${mb(total)} MB' : ''} ${_dl['message'] ?? ''}'.trim(),
            style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
      ]),
    );
  }
}
