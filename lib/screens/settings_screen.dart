import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/text_api.dart';
import '../demo/demo_flag.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
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
  int _versionTaps = 0;

  @override
  void initState() {
    super.initState();
    _load();
    DemoFlag.load();
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
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.s),
              child: Semantics(
                header: true,
                child: Text('अपना ज़िला चुनें', style: Theme.of(ctx).textTheme.titleLarge),
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

  bool _advancedOpen = false;

  /// Result of the last export; [info] is a neutral outcome (not a failure).
  bool _info = false;

  void _msg(bool ok, String hi, String en, {bool info = false}) => setState(() {
    _ok = ok;
    _info = info;
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
          ? _msg(false, 'अभी भेजने के लिए कुछ नहीं है', 'Nothing to share yet', info: true)
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
                          'आपका ज़िला',
                          style: t.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          d ?? 'ज़िला चुनें',
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
            'सिर्फ़ ज़िला, ठगी का प्रकार और तारीख',
            style: t.textTheme.titleMedium,
          ),
          item(Icons.location_on, 'ज़िला'),
          item(Icons.category, 'ठगी का प्रकार'),
          item(Icons.event, 'तारीख'),
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
                  'आपके मैसेज, कॉल, नंबर और नाम कभी फ़ोन से बाहर नहीं जाते',
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
          const SectionHeader(
            icon: Icons.bar_chart,
            title: 'ठगी की गिनती भेजें',
            subtitle: 'Share scam counts (optional)',
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
                  _busy ? 'तैयार हो रहा है…' : 'गिनती साझा करें',
                  textAlign: TextAlign.center,
                ),
                const Text(
                  'Export anonymised counts',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
          if (d == null)
            Padding(
              padding: const EdgeInsets.only(top: Sp.s),
              child: Text(
                'पहले ज़िला चुनें · Choose a district first',
                textAlign: TextAlign.center,
                style: t.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          if (_hi != null)
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
                            _hi!,
                            style: t.textTheme.bodyLarge?.copyWith(
                              color: _ok ? st.safe : (_info ? cs.onSurfaceVariant : cs.error),
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

  /// Hidden enable for release builds: 7 taps on the version row turn Demo mode on.
  void _versionTap() {
    if (++_versionTaps < 7) return;
    _versionTaps = 0;
    DemoFlag.set(true);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('डेमो मोड चालू · Demo mode on')),
    );
  }

  Future<void> _set(String key, Object? value) async {
    final s = await TextApi.setSettings({key: value});
    if (mounted) setState(() => _s = s);
  }

  /// Hindi title first; the English title stays as a secondary line, then the detail.
  Widget _switch(String key, String hi, String en, String detail) => SwitchListTile(
    title: Text(hi),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(en), Text(detail)],
    ),
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
      // Keep the last row clear of the gesture bar.
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + Sp.l),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: Sp.l),
          child: SectionHeader(
            icon: Icons.shield,
            title: 'चेतावनी की सेटिंग',
            subtitle: 'Warning settings',
            muted: true,
          ),
        ),
        _switch('overlayEnabled', 'चेतावनी बबल दिखाएँ', 'Show warning bubble',
            'कॉल के दौरान स्क्रीन पर तैरती चेतावनी'),
        _switch('autoEnableCaptions', 'लाइव कैप्शन अपने आप चालू करें', 'Auto-turn-on Live Caption',
            'कॉल के 6 सेकंड बाद तक कैप्शन न दिखें तो'),
        _switch('inCallSignals', 'कॉल के दौरान ठगी के संकेत', 'In-call scam signals',
            'कॉल में OTP आए या UPI/बैंक/AnyDesk ऐप खुले तो चेतावनी'),
        _switch('wifiOnly', 'मॉडल सिर्फ़ Wi-Fi पर डाउनलोड करें', 'Download model on Wi-Fi only',
            'मॉडल लगभग 555 MB का है'),
        _trendSection(context),
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
            title: const Text('उन्नत सेटिंग'),
            subtitle: const Text('Advanced settings'),
            children: [
              _switch('useLlm', 'फ़ोन पर चलने वाला Gemma इस्तेमाल करें', 'Use on-device Gemma',
                  'बंद हो तो सिर्फ़ नियम चलते हैं (कम क्षमता वाले फ़ोन पर तेज़)'),
              _switch('ocrFallback', 'स्क्रीन पढ़कर देखें (OCR)', 'Screen-reading fallback (OCR)',
                  'कैप्शन का टेक्स्ट छिपा हो तो स्क्रीनशॉट से पढ़ता है (Android 11+)'),
              _switch('micProbe', 'अगली कॉल पर ऑडियो जाँच (प्रयोगात्मक)', 'Call audio test on next call (experimental)',
                  'अगली कॉल की शुरुआत में हर माइक से 3 सेकंड जाँचता है, फिर खुद बंद हो जाता है'),
              _switch('discoveryMode', 'खोज मोड (डिबग)', 'Discovery mode (debug)',
                  'आपके फ़ोन का कैप्शन पैकेज ढूँढने के लिए हर विंडो का टेक्स्ट लाइव टैब में दिखाता है'),
              Padding(
                padding: const EdgeInsets.all(Sp.l),
                child: TextField(
                  controller: _pkgCtrl,
                  decoration: const InputDecoration(
                    labelText: 'कैप्शन स्रोत पैकेज (कॉमा से अलग) · Caption source packages',
                    helperText: 'खोज मोड से मिलते हैं। जिनमें "caption" है वे हमेशा शामिल हैं।',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) => _set('captionPackages', v),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: DemoFlag.enabled,
                builder: (_, on, _) => SwitchListTile(
                  key: const Key('demoModeSwitch'),
                  title: const Text('डेमो मोड'),
                  subtitle: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text('Demo mode'), Text('मदद टैब में "डेमो लैब" दिखाएँ')],
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
