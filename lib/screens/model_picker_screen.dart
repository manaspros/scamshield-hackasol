import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/llm_api.dart';
import '../api/model_api.dart';
import '../api/text_api.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_profile.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/island.dart';
import '../widgets/premium.dart';

/// Pick which on-device model to download, with a recommendation from this phone's RAM, chip and free space.
class ModelPickerScreen extends StatefulWidget {
  const ModelPickerScreen({super.key, this.api = const ModelApi(), this.listenToEvents = true});
  final ModelApi api;

  /// Tests switch the native event stream off.
  final bool listenToEvents;

  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen> {
  List<ModelSpec> _catalog = kFallbackCatalog;
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
    _load();
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

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final cat = await widget.api.catalog();
    final dev = await widget.api.device();
    final st = await widget.api.state();
    Map<Object?, Object?> settings = const {};
    try {
      settings = await TextApi.getSettings();
    } on MissingPluginException {
      // keep defaults
    } on PlatformException {
      // keep defaults
    }
    Map<Object?, Object?> dl = const {};
    try {
      dl = await TextApi.downloadStatus();
    } on MissingPluginException {
      // no download
    } on PlatformException {
      // no download
    }
    if (!mounted) return;
    final rec = dev.recommendedId ?? recommendModelId(cat, dev);
    LlmStatus.ready.value = st.ready;
    setState(() {
      _catalog = cat;
      _dev = dev;
      _state = st;
      _picked ??= st.modelId ?? rec;
      _wifiOnly = settings['wifiOnly'] != false;
      _dl = dl;
      _loaded = true;
    });
  }

  String _t(String k, [Map<String, Object?> a = const {}]) => profileT(AppLanguage.of(context), k, a);

  String get _recId => _dev.recommendedId ?? recommendModelId(_catalog, _dev);

  ModelSpec get _sel => _catalog.firstWhere((m) => m.id == _picked, orElse: () => _catalog.first);

  bool get _downloading => const {'RUNNING', 'PENDING', 'PAUSED'}.contains('${_dl['status']}');

  String _tierLine(ModelSpec m) => '${m.sizeLabel} · ${_t('m_${m.tier}')}';

  /// Badge text and colours for one model row.
  (String, Color, Color) _tag(ModelSpec m) {
    final p = palOf(context);
    final st = Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
    if (m.id == _state.modelId && _state.ready) return (_t('m_in_use'), st.safe, st.safe.withValues(alpha: 0.14));
    if (_state.installed.contains(m.id)) return (_t('m_installed'), p.accent, p.accentTint);
    final b = blockFor(m, _dev);
    if (b == ModelBlock.notHosted) return (_t('m_soon'), p.muted, p.isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF0F0F2));
    if (b == ModelBlock.lowRam) return (_t('m_low_ram', {'n': (m.minRamMb / 1000).round()}), st.suspicious, st.suspicious.withValues(alpha: 0.14));
    if (b == ModelBlock.lowStorage) {
      return (_t('m_low_storage', {'n': ModelSpec(id: '', name: '', file: '', sizeMb: m.sizeMb + kModelHeadroomMb, minRamMb: 0, tier: '').sizeLabel}),
          st.suspicious, st.suspicious.withValues(alpha: 0.14));
    }
    if (m.id == _recId) return (_t('m_rec'), st.safe, st.safe.withValues(alpha: 0.14));
    return (_t('m_${m.tier}').split(' · ').first, p.ink, p.isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF0F0F2));
  }

  Future<void> _act() async {
    final m = _sel;
    if (_state.installed.contains(m.id)) {
      final s = await widget.api.select(m.id);
      if (!mounted) return;
      setState(() => _state = s);
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
    final r = await widget.api.download(m.id);
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
    final sel = _sel;
    final installed = _state.installed.contains(sel.id);
    final inUse = installed && sel.id == _state.modelId && _state.ready;
    final canAct = _loaded && !_downloading && !inUse && (sel.available || installed);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.xl),
      children: [
        Text(_t('m_intro'), style: th.textTheme.bodyLarge?.copyWith(color: p.muted, fontSize: 17)),
        const SizedBox(height: Sp.l),
        _deviceCard(th, p),
        const SizedBox(height: Sp.l + 2),
        Text(_t('m_model'), style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
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
                label: m.name,
                caption: _tierLine(m),
                selected: m.id == _picked,
                enabled: m.available || _state.installed.contains(m.id),
                leading: _chipIcon(m),
                trailing: m.id == _picked ? null : _tagChip(th, _tag(m)),
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
                  _chipIcon(sel),
                  const SizedBox(width: Sp.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(sel.name, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      _tagChip(th, _tag(sel)),
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
        Text(_tierLine(sel), style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
        const SizedBox(height: Sp.xl),
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
                  : sel.available
                      ? _t('m_download', {'s': sel.sizeLabel})
                      : _t('m_soon')),
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
          TextButton(key: const Key('mp_import'), onPressed: _import, child: Text(_t('m_import'))),
        ]),
      ],
    );
  }

  Widget _chipIcon(ModelSpec m) {
    final p = palOf(context);
    final on = m.id == _picked;
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
        child: Text(t.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: th.textTheme.labelSmall?.copyWith(color: t.$2, fontWeight: FontWeight.w700, fontSize: 14)),
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
    final chip = _dev.soc.isEmpty ? '—' : _dev.soc;
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
          cell(chip, _t('m_chip')),
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
