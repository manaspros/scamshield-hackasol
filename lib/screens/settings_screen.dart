import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/text_api.dart';
import '../demo/demo_flag.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../l10n/strings_settings.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/section_header.dart';
import '../widgets/state_message.dart';
import '../widgets/island.dart';
import '../api/model_api.dart';
import '../api/model_catalog.dart';
import '../l10n/strings_profile.dart';
import '../theme/theme_controller.dart';
import '../widgets/premium.dart';
import 'model_picker_screen.dart';
import 'page_route.dart';
import 'setup_screen.dart';

/// Chhattisgarh districts, generated from data/districts.json.
/// [VERIFY] list against the official source (same flag as the JSON).
const kDistricts = <String>[
  'Balod',
  'Baloda Bazar',
  'Balrampur',
  'Bastar',
  'Bemetara',
  'Bijapur',
  'Bilaspur',
  'Dantewada',
  'Dhamtari',
  'Durg',
  'Gariaband',
  'Gaurela-Pendra-Marwahi',
  'Janjgir-Champa',
  'Jashpur',
  'Kabirdham',
  'Kanker',
  'Khairagarh-Chhuikhadan-Gandai',
  'Kondagaon',
  'Korba',
  'Korea',
  'Mahasamund',
  'Manendragarh-Chirmiri-Bharatpur',
  'Mohla-Manpur-Ambagarh Chowki',
  'Mungeli',
  'Narayanpur',
  'Raigarh',
  'Raipur',
  'Rajnandgaon',
  'Sakti',
  'Sarangarh-Bilaigarh',
  'Sukma',
  'Surajpur',
  'Surguja',
];

const _trend = MethodChannel('scamshield/trend');
const _prefs = MethodChannel('scamshield/prefs');
const _districtKey = 'district';

/// Settings: four short groups (appearance, protection, AI model, privacy & more). Debug options live on their
/// own Advanced page and the scam-count export on its own page, so this screen stays simple.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.models = const ModelApi()});
  final ModelApi models;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<Object?, Object?> _s = {};
  String? _district;
  ModelState? _model;
  bool _loaded = false, _failed = false;
  int _versionTaps = 0;

  @override
  void initState() {
    super.initState();
    _load();
    DemoFlag.load();
  }

  String _t(String key, [Map<String, Object?> args = const {}]) => settingsT(AppLanguage.code, key, args);

  Future<void> _load() async {
    setState(() {
      _loaded = false;
      _failed = false;
    });
    try {
      final s = await TextApi.getSettings();
      String? d;
      try {
        d = await _prefs
            .invokeMethod<String>('getString', {'key': _districtKey})
            .timeout(const Duration(seconds: 1), onTimeout: () => null);
      } on MissingPluginException {
        d = null;
      } on PlatformException {
        d = null;
      }
      final m = await widget.models.state().timeout(const Duration(seconds: 2), onTimeout: () => const ModelState());
      if (!mounted) return;
      setState(() {
        _s = s;
        _district = kDistricts.contains(d) ? d : null;
        _model = m;
        _loaded = true;
      });
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    } on MissingPluginException {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _set(String key, Object? value) async {
    setState(() => _s = {..._s, key: value}); // instant feedback; native confirms below
    try {
      final s = await TextApi.setSettings({key: value});
      if (mounted) setState(() => _s = s);
    } on PlatformException {
      // keep the optimistic value
    } on MissingPluginException {
      // keep the optimistic value
    }
  }

  Future<void> _open(String title, Widget page) async {
    await pushTitled(context, title, page);
    if (mounted) _load();
  }

  /// Hidden enable for release builds: 7 taps on the version row turn Demo mode on.
  void _versionTap() {
    if (++_versionTaps < 7) return;
    _versionTaps = 0;
    DemoFlag.set(true);
    showIsland(context, _t('demo_snack'), tone: IslandTone.success);
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    if (_failed) {
      return Center(
        child: StateMessage(icon: Icons.error_outline, title: _t('fail_title'), subtitle: lang == 'en' ? null : _t('fail_sub'), actionLabel: _t('retry'), onAction: _load),
      );
    }
    if (!_loaded) return Center(child: StateMessage(loading: true, title: _t('loading')));
    final th = Theme.of(context);
    final p = palOf(context);
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    final m = _model;
    final cat = ModelCatalogStore.models.value;
    final modelName = m == null ? null : cat.where((c) => c.id == m.idIn(cat)).map((c) => c.name).firstOrNull;
    return ListView(
      padding: EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, MediaQuery.paddingOf(context).bottom + Sp.xl),
      children: [
        _head(_t('sec_appearance')),
        PGroup(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.l, Sp.l, Sp.l, Sp.m),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeController.mode,
              builder: (_, mode, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  IconBadge(icon: Icons.contrast_rounded, color: p.accent, tint: p.accentTint, size: 36, iconSize: 20),
                  const SizedBox(width: Sp.m + 2),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_t('theme'), style: th.textTheme.bodyLarge?.copyWith(fontSize: 17)),
                      Text(_t(mode == ThemeMode.system ? 'theme_hint_sys' : 'theme_hint_pick'),
                          style: th.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: 14)),
                    ]),
                  ),
                ]),
                const SizedBox(height: Sp.m),
                _Segmented(
                  value: mode,
                  onChanged: ThemeController.set,
                  items: [
                    (ThemeMode.system, _t('theme_system'), Icons.smartphone_rounded, const Key('theme_system')),
                    (ThemeMode.light, _t('theme_light'), Icons.light_mode_rounded, const Key('theme_light')),
                    (ThemeMode.dark, _t('theme_dark'), Icons.dark_mode_rounded, const Key('theme_dark')),
                  ],
                ),
              ]),
            ),
          ),
          PRow(
            key: const Key('settings_language_row'),
            label: _t('lang_row'),
            value: _t('lang_$lang'),
            leading: IconBadge(icon: Icons.translate_rounded, color: p.accent, tint: p.accentTint, size: 36, iconSize: 20),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _LanguagePage())),
            last: true,
          ),
        ]),
        _head(_t('sec_protection')),
        PGroup(children: [
          _toggle('overlayEnabled', 'overlay', Icons.chat_bubble_rounded, st.scam),
          _toggle('readAloud', 'read_aloud', Icons.record_voice_over_rounded, st.safe, defaultOn: true),
          _toggle('autoEnableCaptions', 'caps', Icons.closed_caption_rounded, p.accent),
          _toggle('inCallSignals', 'signals', Icons.warning_amber_rounded, st.suspicious, last: true),
        ]),
        _head(_t('sec_ai')),
        PGroup(children: [
          InkWell(
            key: const Key('settings_model'),
            onTap: () => _open(profileT(lang, 'm_title'), const ModelPickerScreen()),
            child: Padding(
              padding: const EdgeInsets.all(Sp.l),
              child: Row(children: [
                IconBadge(icon: Icons.memory_rounded, color: p.onAccent, tint: p.accent, size: 44, iconSize: 24),
                const SizedBox(width: Sp.m + 2),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(modelName ?? _t('model_none'), style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Row(children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: m?.ready == true ? st.safe : p.muted, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(m?.ready == true ? _t('model_ready') : _t('model_get'),
                            style: th.textTheme.bodySmall?.copyWith(color: m?.ready == true ? st.safe : p.muted, fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                    ]),
                  ]),
                ),
                Text(_t('change'), style: th.textTheme.titleSmall?.copyWith(color: p.accent)),
              ]),
            ),
          ),
          Divider(height: 1, color: p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF0F0F2)),
          _toggle('useLlm', 'llm', null, p.accent),
          _toggle('wifiOnly', 'wifi', null, p.accent, last: true),
        ]),
        _head(_t('sec_more')),
        PGroup(children: [
          PRow(
            key: const Key('settings_share'),
            label: _t('trend_title'),
            subtitle: _t('share_d'),
            value: _district,
            leading: IconBadge(icon: Icons.bar_chart_rounded, color: st.safe, tint: st.safe.withValues(alpha: 0.14), size: 36, iconSize: 20),
            onTap: () => _open(_t('trend_title'), const ShareCountsScreen()),
          ),
          PRow(
            key: const Key('settings_setup_row'),
            label: homeT(lang, 'set_setup'),
            subtitle: homeT(lang, 'set_setup_s'),
            leading: IconBadge(icon: Icons.verified_user_rounded, color: st.safe, tint: st.safe.withValues(alpha: 0.14), size: 36, iconSize: 20),
            onTap: () async {
              await openSetupPage(context);
              if (mounted) _load();
            },
          ),
          PRow(
            key: const Key('settings_advanced'),
            label: _t('adv'),
            subtitle: _t('adv_d'),
            leading: IconBadge(icon: Icons.tune_rounded, color: p.muted, size: 36, iconSize: 20),
            onTap: () => _open(_t('adv'), const AdvancedSettingsScreen()),
            last: true,
          ),
        ]),
        const SizedBox(height: Sp.xl),
        Semantics(
          button: true,
          child: InkWell(
            key: const Key('appVersion'),
            borderRadius: BorderRadius.circular(RadX.card),
            onTap: _versionTap,
            child: Padding(
              padding: const EdgeInsets.all(Sp.m),
              child: Column(children: [
                Icon(Icons.shield_rounded, color: p.accent, size: 28),
                const SizedBox(height: Sp.xs),
                Text('ScamShield $kAppVersion', style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(_t('footer'), style: th.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: 14)),
              ]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _head(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.xs, Sp.l + 2, Sp.xs, Sp.s),
        child: Semantics(
          header: true,
          child: Text(s.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: palOf(context).muted, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        ),
      );

  /// One switch row: optional tinted icon, title, one short line, switch. The whole row toggles.
  /// [defaultOn]: what the switch shows before native has ever stored the setting.
  Widget _toggle(String key, String tk, IconData? icon, Color c, {bool last = false, bool defaultOn = false}) => SettingSwitch(
        key: Key('sw_$key'),
        title: _t(tk),
        subtitle: _t('${tk}_short'),
        icon: icon,
        color: c,
        value: _s[key] == null ? defaultOn : _s[key] == true,
        onChanged: (v) => _set(key, v),
        last: last,
      );
}

/// Settings → Advanced: test and developer options, kept off the main Settings page.
class AdvancedSettingsScreen extends StatefulWidget {
  const AdvancedSettingsScreen({super.key});
  @override
  State<AdvancedSettingsScreen> createState() => _AdvancedSettingsState();
}

class _AdvancedSettingsState extends State<AdvancedSettingsScreen> {
  Map<Object?, Object?> _s = {};
  final _pkgCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pkgCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await TextApi.getSettings();
      if (!mounted) return;
      _pkgCtrl.text = '${s['captionPackages'] ?? ''}';
      setState(() => _s = s);
    } on PlatformException {
      // show defaults
    } on MissingPluginException {
      // show defaults
    }
  }

  Future<void> _set(String key, Object? value) async {
    setState(() => _s = {..._s, key: value});
    try {
      final s = await TextApi.setSettings({key: value});
      if (mounted) setState(() => _s = s);
    } on PlatformException {
      // keep the optimistic value
    } on MissingPluginException {
      // keep the optimistic value
    }
  }

  String _t(String key) => settingsT(AppLanguage.code, key);

  @override
  Widget build(BuildContext context) {
    AppLanguage.of(context);
    final p = palOf(context);
    Widget sw(String key, String tk, {bool last = false}) =>
        SettingSwitch(key: Key('sw_$key'), title: _t(tk), subtitle: _t('${tk}_d'), color: p.accent, value: _s[key] == true, onChanged: (v) => _set(key, v), last: last);
    return ListView(
      padding: EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, MediaQuery.paddingOf(context).bottom + Sp.xl),
      children: [
        Text(_t('adv_intro'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: p.muted, fontSize: 16)),
        const SizedBox(height: Sp.m),
        PGroup(children: [
          sw('ocrFallback', 'ocr'),
          sw('micProbe', 'probe'),
          sw('discoveryMode', 'disco', last: true),
        ]),
        const SizedBox(height: Sp.l),
        TextField(
          key: const Key('captionPackages'),
          controller: _pkgCtrl,
          decoration: InputDecoration(labelText: _t('pkg_label'), helperText: _t('pkg_help'), helperMaxLines: 3),
          onSubmitted: (v) => _set('captionPackages', v),
        ),
        const SizedBox(height: Sp.l),
        PGroup(children: [
          ValueListenableBuilder<bool>(
            valueListenable: DemoFlag.enabled,
            builder: (_, on, _) => SettingSwitch(
              key: const Key('demoModeSwitch'),
              title: _t('demo'),
              subtitle: _t('demo_d'),
              icon: Icons.science_rounded,
              color: p.accent,
              value: on,
              onChanged: DemoFlag.set,
              last: true,
            ),
          ),
        ]),
      ],
    );
  }
}

/// A settings row with a switch; the whole row is the tap target.
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    super.key,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.value,
    required this.onChanged,
    this.icon,
    this.last = false,
  });
  final String title, subtitle;
  final IconData? icon;
  final Color color;
  final bool value, last;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final p = palOf(context);
    return Semantics(
      toggled: value,
      button: true,
      label: title,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Container(
          constraints: const BoxConstraints(minHeight: kTouch + 8),
          padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.m),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF0F0F2)))),
          child: Row(children: [
            if (icon != null) ...[IconBadge(icon: icon!, color: color, size: 36, iconSize: 20), const SizedBox(width: Sp.m + 2)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: th.textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.3)),
                Text(subtitle, style: th.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: 14, height: 1.3)),
              ]),
            ),
            const SizedBox(width: Sp.s),
            Switch(value: value, onChanged: onChanged),
          ]),
        ),
      ),
    );
  }
}

/// iOS-style segmented control (theme picker).
class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.value, required this.onChanged, required this.items});
  final T value;
  final ValueChanged<T> onChanged;
  final List<(T, String, IconData, Key)> items;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    final th = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFEEEEF1), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        for (final (v, label, icon, key) in items)
          Expanded(
            child: Semantics(
              selected: v == value,
              button: true,
              child: GestureDetector(
                key: key,
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  constraints: const BoxConstraints(minHeight: 44),
                  decoration: BoxDecoration(
                    color: v == value ? (p.isDark ? const Color(0xFF48484A) : Colors.white) : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: v == value ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 3, offset: Offset(0, 1))] : null,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: Sp.xs, vertical: Sp.s),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, size: 16, color: v == value ? p.ink : p.muted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: th.textTheme.labelMedium?.copyWith(fontSize: 15, color: v == value ? p.ink : p.muted, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Settings → Share scam counts: district, what is shared, and the export.
class ShareCountsScreen extends StatefulWidget {
  const ShareCountsScreen({super.key});
  @override
  State<ShareCountsScreen> createState() => _ShareCountsState();
}

class _ShareCountsState extends State<ShareCountsScreen> {
  String? _district;
  bool _loaded = false, _failed = false, _busy = false, _ok = true;
  String? _msgKey; // export result message (string key), shown in the app language
  int _msgN = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Text in the app language; works in callbacks (the build-time dependency comes from [build]).
  String _t(String key, [Map<String, Object?> args = const {}]) => settingsT(AppLanguage.code, key, args);

  /// The muted English second line: only in Hindi / Chhattisgarhi mode.
  String? _sub(String key) => AppLanguage.code == 'en' ? null : _t(key);

  /// Settings and the saved district load together so no default flashes on screen.
  Future<void> _load() async {
    setState(() {
      _loaded = false;
      _failed = false;
    });
    try {
      await TextApi.getSettings(); // proves the native side is reachable (else the retry state)
      final d = await _readDistrict();
      if (!mounted) return;
      setState(() {
        _district = d;
        _loaded = true;
      });
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    } on MissingPluginException {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<String?> _readDistrict() async {
    try {
      // The district is optional: never let a slow or silent prefs channel block the screen.
      final d = await _prefs
          .invokeMethod<String>('getString', {'key': _districtKey})
          .timeout(const Duration(seconds: 1), onTimeout: () => null);
      return kDistricts.contains(d) ? d : null;
    } on MissingPluginException {
      return null; // native prefs not wired: the choice lasts for this session only
    } on PlatformException {
      return null;
    }
  }

  Future<void> _pickDistrict() async {
    final d = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.s),
              child: Semantics(
                header: true,
                child: Text(_t('district_sheet'), style: Theme.of(ctx).textTheme.titleLarge),
              ),
            ),
            Expanded(
              child: ListView.builder(
                key: const Key('districtList'),
                itemCount: kDistricts.length,
                itemBuilder: (_, i) => ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kTouch),
                  child: ListTile(
                    // shortcut: English names only, no Hindi district list in the repo; add one when it exists.
                    title: Text(
                      kDistricts[i],
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    trailing: kDistricts[i] == _district
                        ? const Icon(Icons.check, size: 32)
                        : null,
                    onTap: () => Navigator.pop(ctx, kDistricts[i]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (d == null || !mounted) return;
    setState(() {
      _district = d;
      _msgKey = null;
    });
    try {
      await _prefs.invokeMethod<void>('setString', {
        'key': _districtKey,
        'value': d,
      });
    } on MissingPluginException {
      // session only
    } on PlatformException {
      // session only
    }
  }

  /// Result of the last export; [info] is a neutral outcome (not a failure).
  bool _info = false;

  void _msg(bool ok, String key, {bool info = false, int n = 0}) => setState(() {
    _ok = ok;
    _info = info;
    _msgKey = key;
    _msgN = n;
  });

  Future<void> _export() async {
    final d = _district;
    if (d == null || _busy) return;
    setState(() {
      _busy = true;
      _msgKey = null;
    });
    try {
      final r = await _trend.invokeMapMethod<Object?, Object?>('trend.export', {
        'district': d,
      });
      final n = (r?['count'] as num?)?.toInt() ?? 0;
      n == 0 ? _msg(false, 'm_none', info: true) : _msg(true, 'm_ok', n: n);
    } on PlatformException {
      _msg(false, 'm_fail');
    } on MissingPluginException {
      _msg(false, 'm_fail');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One 56dp+ row: location icon, label, current value, chevron.
  Widget _districtRow(ThemeData t, String? d) {
    final cs = t.colorScheme;
    return Semantics(
      button: true,
      child: Material(
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.lg),
          side: BorderSide(color: cs.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('districtPicker'),
          onTap: _pickDistrict,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Sp.l,
                vertical: Sp.m,
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on, size: 28, color: cs.primary),
                  const SizedBox(width: Sp.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t('district_label'),
                          style: t.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          d ?? _t('district_pick'),
                          style: t.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 32,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// What is shared, and what never leaves the phone.
  Widget _trustCard(ThemeData t, StatusColors st) {
    final cs = t.colorScheme;
    Widget item(IconData icon, String word) => Padding(
      padding: const EdgeInsets.only(top: Sp.s),
      child: Row(
        children: [
          Icon(icon, size: 24, color: cs.onSurfaceVariant),
          const SizedBox(width: Sp.m),
          Expanded(child: Text(word, style: t.textTheme.bodyLarge)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(Sp.l),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _t('trust_title'),
            style: t.textTheme.titleMedium,
          ),
          item(Icons.location_on, _t('trust_district')),
          item(Icons.category, _t('trust_type')),
          item(Icons.event, _t('trust_date')),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Sp.m),
            child: Divider(),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock, size: 28, color: st.safe),
              const SizedBox(width: Sp.m),
              Expanded(
                child: Text(
                  _t('trust_private'),
                  style: t.textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trendSection(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final st = t.extension<StatusColors>() ?? StatusColors.light;
    final d = _district;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            icon: Icons.bar_chart,
            title: _t('trend_title'),
            subtitle: _sub('trend_s'),
          ),
          _districtRow(t, d),
          const SizedBox(height: Sp.l),
          _trustCard(t, st),
          const SizedBox(height: Sp.l),
          // Secondary on purpose: settings has no single primary action.
          OutlinedButton(
            key: const Key('exportButton'),
            onPressed: d == null || _busy ? null : _export,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _t(_busy ? 'export_busy' : 'export'),
                  textAlign: TextAlign.center,
                ),
                if (_sub('export_s') case final sub?)
                  Text(
                    sub,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
                  ),
              ],
            ),
          ),
          if (d == null)
            Padding(
              padding: const EdgeInsets.only(top: Sp.s),
              child: Text(
                [_t('pick_first'), ?_sub('pick_first_s')].join(' · '),
                textAlign: TextAlign.center,
                style: t.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          if (_msgKey case final mk?)
            Padding(
              padding: const EdgeInsets.only(top: Sp.m),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _ok ? Icons.check_circle : (_info ? Icons.info_outline : Icons.error),
                    size: 32,
                    color: _ok ? st.safe : (_info ? cs.onSurfaceVariant : cs.error),
                  ),
                  const SizedBox(width: Sp.m),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(mk, {'n': _msgN}),
                            style: t.textTheme.bodyLarge?.copyWith(
                              color: _ok ? st.safe : (_info ? cs.onSurfaceVariant : cs.error),
                            ),
                          ),
                          if (_sub('${mk}_s') case final sub?)
                            Text(
                              sub.replaceAll('{n}', '$_msgN'),
                              style: t.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.of(context); // rebuild when the language changes; strings read it via _t
    if (_failed) {
      return Center(child: StateMessage(icon: Icons.error_outline, title: _t('fail_title'), subtitle: _sub('fail_sub'), actionLabel: _t('retry'), onAction: _load));
    }
    if (!_loaded) return Center(child: StateMessage(loading: true, title: _t('loading'), subtitle: _sub('loading_s')));
    return ListView(
      padding: EdgeInsets.only(top: Sp.s, bottom: MediaQuery.paddingOf(context).bottom + Sp.l),
      children: [_trendSection(context)],
    );
  }
}

/// Language choice page: picking a language saves it and returns to Settings.
class _LanguagePage extends StatelessWidget {
  const _LanguagePage();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(settingsT(AppLanguage.of(context), 'lang_title'))),
        body: LanguagePicker(
          selected: AppLanguage.code,
          showPrompt: false,
          onPicked: (c) {
            AppLanguage.set(c);
            Navigator.pop(context);
          },
        ),
      );
}
