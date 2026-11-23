import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/text_api.dart';
import '../demo/demo_flag.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../l10n/strings_settings.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/action_tile.dart';
import '../widgets/section_header.dart';
import '../widgets/state_message.dart';
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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<Object?, Object?> _s = {};
  final _pkgCtrl = TextEditingController();

  String? _district;
  bool _loaded = false, _failed = false, _busy = false, _ok = true;
  String? _msgKey; // export result message (string key), shown in the app language
  int _msgN = 0;
  int _versionTaps = 0;

  @override
  void initState() {
    super.initState();
    _load();
    DemoFlag.load();
  }

  /// Text in the app language; works in callbacks (the build-time dependency comes from [build]).
  String _t(String key, [Map<String, Object?> args = const {}]) => settingsT(AppLanguage.code, key, args);

  /// The muted English second line: only in Hindi / Chhattisgarhi mode.
  String? _sub(String key) => AppLanguage.code == 'en' ? null : _t(key);

  @override
  void dispose() {
    _pkgCtrl.dispose();
    super.dispose();
  }

  /// Settings and the saved district load together so no default flashes on screen.
  Future<void> _load() async {
    setState(() {
      _loaded = false;
      _failed = false;
    });
    try {
      final s = await TextApi.getSettings();
      final d = await _readDistrict();
      if (!mounted) return;
      _pkgCtrl.text = '${s['captionPackages'] ?? ''}';
      setState(() {
        _s = s;
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

  bool _advancedOpen = false;

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

  /// Top row: current language name; opens the picker page.
  Widget _languageRow(ThemeData t) {
    final cs = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.l, Sp.l, Sp.l, 0),
      child: Semantics(
        button: true,
        child: Material(
          color: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rad.lg),
            side: BorderSide(color: cs.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('settings_language_row'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _LanguagePage())),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kTouch),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.m),
                child: Row(
                  children: [
                    Icon(Icons.translate, size: 28, color: cs.primary),
                    const SizedBox(width: Sp.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_t('lang_label'), style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          Text(_t('lang_${AppLanguage.code}'), style: t.textTheme.titleMedium),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 32, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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

  /// Hidden enable for release builds: 7 taps on the version row turn Demo mode on.
  void _versionTap() {
    if (++_versionTaps < 7) return;
    _versionTaps = 0;
    DemoFlag.set(true);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(_t('demo_snack'))),
    );
  }

  Future<void> _set(String key, Object? value) async {
    final s = await TextApi.setSettings({key: value});
    if (mounted) setState(() => _s = s);
  }

  Widget _enLine(String t) => Text(t, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));

  // Title and detail lead in the app language; in hi/hne the English name is the muted last line.
  Widget _switch(String key, String tk, {bool defaultOn = false}) => SwitchListTile(
    title: Text(_t(tk)),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(_t('${tk}_d')), if (_sub('${tk}_s') case final en?) _enLine(en)],
    ),
    value: _s[key] == null ? defaultOn : _s[key] == true,
    onChanged: (v) => _set(key, v),
  );

  @override
  Widget build(BuildContext context) {
    AppLanguage.of(context); // rebuild when the language changes; strings read it via _t
    if (_failed) {
      return Center(
        child: StateMessage(
          icon: Icons.error_outline,
          title: _t('fail_title'),
          subtitle: _sub('fail_sub'),
          actionLabel: _t('retry'),
          onAction: _load,
        ),
      );
    }
    if (!_loaded) {
      return Center(
        child: StateMessage(
          loading: true,
          title: _t('loading'),
          subtitle: _sub('loading_s'),
        ),
      );
    }
    return ListView(
      // Keep the last row clear of the gesture bar.
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + Sp.l),
      children: [
        _languageRow(Theme.of(context)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.l),
          child: SectionHeader(
            icon: Icons.shield,
            title: _t('warn_title'),
            subtitle: _sub('warn_s'),
            muted: true,
          ),
        ),
        _switch('overlayEnabled', 'overlay'),
        _switch('readAloud', 'read_aloud', defaultOn: true),
        _switch('autoEnableCaptions', 'caps'),
        _switch('inCallSignals', 'signals'),
        _switch('wifiOnly', 'wifi'),
        _trendSection(context),
        Padding(
          padding: const EdgeInsets.all(Sp.l),
          child: ActionTile(
            key: const Key('settings_setup_row'),
            icon: Icons.checklist,
            label: homeT(AppLanguage.code, 'set_setup'),
            caption: homeT(AppLanguage.code, 'set_setup_s'),
            onTap: () => openSetupPage(context),
          ),
        ),
        const Divider(),
        // Developer controls: closed by default so the first screen is for the user.
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('settings_advanced'),
            // Kept in state: the lazy list drops the tile when scrolled away and would collapse it.
            initiallyExpanded: _advancedOpen,
            onExpansionChanged: (v) => _advancedOpen = v,
            leading: Icon(Icons.tune, size: 28, color: Theme.of(context).colorScheme.onSurfaceVariant),
            title: Text(_t('adv')),
            subtitle: AppLanguage.code == 'en' ? null : Text(_t('adv_s')),
            children: [
              _switch('useLlm', 'llm'),
              _switch('ocrFallback', 'ocr'),
              _switch('micProbe', 'probe'),
              _switch('discoveryMode', 'disco'),
              Padding(
                padding: const EdgeInsets.all(Sp.l),
                child: TextField(
                  controller: _pkgCtrl,
                  decoration: InputDecoration(
                    labelText: _t('pkg_label'),
                    helperText: _t('pkg_help'),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (v) => _set('captionPackages', v),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: DemoFlag.enabled,
                builder: (_, on, _) => SwitchListTile(
                  key: const Key('demoModeSwitch'),
                  title: Text(_t('demo')),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text(_t('demo_d')), if (_sub('demo_s') case final en?) _enLine(en)],
                  ),
                  value: on,
                  onChanged: DemoFlag.set,
                ),
              ),
            ],
          ),
        ),
        ListTile(
          key: const Key('appVersion'),
          title: const Text('ScamShield'),
          subtitle: const Text('Version $kAppVersion'),
          onTap: _versionTap,
        ),
      ],
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
