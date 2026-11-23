import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/text_api.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/action_tile.dart';
import '../widgets/section_header.dart';
import '../widgets/state_message.dart';

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
  String? _hi, _en; // export result message, Hindi first

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
      builder: (ctx) => SafeArea(
        child: ListView.builder(
          key: const Key('districtList'),
          itemCount: kDistricts.length,
          itemBuilder: (_, i) => ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kTouch),
            child: ListTile(
              title: Text(
                kDistricts[i],
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              trailing: kDistricts[i] == _district
                  ? const Icon(Icons.check, size: 32)
                  : null,
              onTap: () => Navigator.pop(ctx, kDistricts[i]),
            ),
          ),
        ),
      ),
    );
    if (d == null || !mounted) return;
    setState(() {
      _district = d;
      _hi = _en = null;
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

  void _msg(bool ok, String hi, String en) => setState(() {
    _ok = ok;
    _hi = hi;
    _en = en;
  });

  Future<void> _export() async {
    final d = _district;
    if (d == null || _busy) return;
    setState(() {
      _busy = true;
      _hi = _en = null;
    });
    try {
      final r = await _trend.invokeMapMethod<Object?, Object?>('trend.export', {
        'district': d,
      });
      final n = (r?['count'] as num?)?.toInt() ?? 0;
      n == 0
          ? _msg(false, 'अभी भेजने के लिए कुछ नहीं है', 'Nothing to share yet')
          : _msg(
              true,
              'शेयर खुल गया: $n गिनती',
              'Share sheet opened: $n counts',
            );
    } on PlatformException {
      _msg(
        false,
        'नहीं भेज सके। फिर कोशिश करें',
        'Could not export. Try again',
      );
    } on MissingPluginException {
      _msg(
        false,
        'नहीं भेज सके। फिर कोशिश करें',
        'Could not export. Try again',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          const SectionHeader(
            icon: Icons.bar_chart,
            title: 'ठगी की गिनती भेजें',
            subtitle: 'Share scam counts (optional)',
          ),
          Container(
            padding: const EdgeInsets.all(Sp.l),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(Rad.lg),
              border: Border.all(color: cs.outline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock, size: 32, color: cs.primary),
                const SizedBox(width: Sp.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'सिर्फ़ 3 चीज़ें फ़ोन से बाहर जाती हैं: ज़िला, ठगी का प्रकार, तारीख़। मैसेज या नंबर नहीं।',
                        style: t.textTheme.bodyLarge,
                      ),
                      Text(
                        'Only 3 things leave your phone: district, scam type, date. No message text, no numbers.',
                        style: t.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.m),
          ActionTile(
            key: const Key('districtPicker'),
            icon: Icons.location_on,
            label: d ?? 'अपना ज़िला चुनें',
            caption: d == null
                ? 'Choose your district'
                : 'ज़िला बदलें · Change',
            onTap: _pickDistrict,
          ),
          const SizedBox(height: Sp.m),
          ActionTile(
            key: const Key('exportButton'),
            icon: Icons.ios_share,
            label: _busy ? 'तैयार हो रहा है…' : 'गिनती भेजें (गुमनाम)',
            caption: d == null
                ? 'पहले ज़िला चुनें · Choose a district first'
                : 'Export anonymised counts',
            onTap: d == null || _busy ? null : _export,
          ),
          if (_hi != null)
            Padding(
              padding: const EdgeInsets.only(top: Sp.m),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _ok ? Icons.check_circle : Icons.error,
                    size: 32,
                    color: _ok ? st.safe : cs.error,
                  ),
                  const SizedBox(width: Sp.m),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _hi!,
                            style: t.textTheme.bodyLarge?.copyWith(
                              color: _ok ? st.safe : cs.error,
                            ),
                          ),
                          Text(
                            _en!,
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

  Future<void> _set(String key, Object? value) async {
    final s = await TextApi.setSettings({key: value});
    if (mounted) setState(() => _s = s);
  }

  Widget _switch(String key, String title, String subtitle) => SwitchListTile(
    title: Text(title),
    subtitle: Text(subtitle),
    value: _s[key] == true,
    onChanged: (v) => _set(key, v),
  );

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: StateMessage(
          icon: Icons.error_outline,
          title: 'सेटिंग नहीं खुलीं',
          subtitle: 'Could not load settings',
          actionLabel: 'फिर कोशिश करें',
          onAction: _load,
        ),
      );
    }
    if (!_loaded) {
      return const Center(
        child: StateMessage(
          loading: true,
          title: 'लोड हो रहा है…',
          subtitle: 'Loading…',
        ),
      );
    }
    return ListView(
      children: [
        _switch(
          'useLlm',
          'Use on-device Gemma',
          'Off = rules only (fastest, for low-end phones)',
        ),
        _switch(
          'overlayEnabled',
          'Show warning bubble',
          'Floating "This statement is…" widget during calls',
        ),
        _switch(
          'autoEnableCaptions',
          'Auto-turn-on Live Caption',
          'If no captions appear 6 s into a call',
        ),
        _switch(
          'ocrFallback',
          'Screen-reading fallback (OCR)',
          'If the caption window hides its text, read it from a screenshot (Android 11+)',
        ),
        _switch(
          'inCallSignals',
          'In-call scam signals',
          'Warn if an OTP arrives, or a UPI/bank/AnyDesk app is opened, during a call',
        ),
        _switch(
          'micProbe',
          'Call audio test on next call (experimental)',
          'Tests 3 s from every mic source at the start of the next call, then switches itself off',
        ),
        _switch(
          'wifiOnly',
          'Download model on Wi-Fi only',
          'The model is ~555 MB',
        ),
        _switch(
          'discoveryMode',
          'Discovery mode (debug)',
          'Log text of every window to the Live tab to find your phone\'s caption package',
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _pkgCtrl,
            decoration: const InputDecoration(
              labelText: 'Caption source packages (comma separated)',
              helperText: 'Found with discovery mode. Packages containing "caption" are always included.',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => _set('captionPackages', v),
          ),
        ),
        _trendSection(context),
      ],
    );
  }
}
