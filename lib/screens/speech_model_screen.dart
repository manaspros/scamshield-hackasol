import 'dart:async';

import 'package:flutter/material.dart';

import '../api/model_api.dart';
import '../api/speech_models.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_profile.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/device_card.dart';
import '../widgets/island.dart';
import 'recording_screen.dart' show RecordingApi;

/// Settings › Speech model: pick and download the offline model that turns a call recording into text.
/// Same shape as the AI model picker: this phone, the choices with a recommendation, then one download button.
class SpeechModelScreen extends StatefulWidget {
  const SpeechModelScreen({super.key, this.api, this.models = const ModelApi()});
  final RecordingApi? api;
  final ModelApi models;
  @override
  State<SpeechModelScreen> createState() => _SpeechModelScreenState();
}

class SpeechStrings {
  static const _m = <String, Map<String, String>>{
    'hi': {
      'title': 'बोली का मॉडल',
      'intro': 'कॉल की रिकॉर्डिंग को बिना इंटरनेट के लिखे हुए पाठ में बदलता है। आपके फ़ोन के लिए सही मॉडल पहले से चुना है।',
      'choose': 'मॉडल चुनें',
      'vosk-small-hi': 'हिंदी · छोटा', 'vosk-small-hi_d': 'हिंदी और छत्तीसगढ़ी · तेज़',
      'vosk-small-en-in': 'भारतीय अंग्रेज़ी · छोटा', 'vosk-small-en-in_d': 'अंग्रेज़ी में हुई कॉल के लिए',
      'vosk-hi': 'हिंदी · बड़ा', 'vosk-hi_d': 'सबसे सही · धीमा',
      'rec': 'आपके फ़ोन के लिए सही', 'low_ram': '{n} GB RAM के साथ बेहतर', 'low_storage': '{n} खाली जगह चाहिए',
      'installed': 'डाउनलोड हो चुका', 'download': '{s} डाउनलोड करें', 'replace': 'इसे डाउनलोड करें · {s}',
      'downloading': 'डाउनलोड हो रहा है…', 'ready': 'बोली का मॉडल तैयार है', 'failed': 'डाउनलोड नहीं हो सका। इंटरनेट देखकर फिर कोशिश करें।',
      'started': 'डाउनलोड शुरू हुआ', 'cancel': 'डाउनलोड रोकें', 'one': 'एक बार में एक मॉडल रहता है। नया लेने पर पुराना हट जाएगा।',
      'offline': 'डाउनलोड के बाद बिना इंटरनेट चलता है। आवाज़ फ़ोन से बाहर नहीं जाती।',
    },
    'hne': {
      'title': 'बोली के मॉडल',
      'intro': 'कॉल के रिकॉर्डिंग ल बिना इंटरनेट के लिखे पाठ म बदलथे। तुंहर फ़ोन बर सही मॉडल पहिली ले चुने हे।',
      'choose': 'मॉडल चुनव',
      'vosk-small-hi': 'हिंदी · छोटे', 'vosk-small-hi_d': 'हिंदी अउ छत्तीसगढ़ी · तेज',
      'vosk-small-en-in': 'भारतीय अंग्रेजी · छोटे', 'vosk-small-en-in_d': 'अंग्रेजी म होय कॉल बर',
      'vosk-hi': 'हिंदी · बड़े', 'vosk-hi_d': 'सबले सही · धीरे',
      'rec': 'तुंहर फ़ोन बर सही', 'low_ram': '{n} GB RAM संग बढ़िया', 'low_storage': '{n} खाली जगह चाही',
      'installed': 'डाउनलोड हो गे', 'download': '{s} डाउनलोड करव', 'replace': 'एला डाउनलोड करव · {s}',
      'downloading': 'डाउनलोड होवत हे…', 'ready': 'बोली के मॉडल तइयार हे', 'failed': 'डाउनलोड नइ हो सकिस। इंटरनेट देख के फेर कोसिस करव।',
      'started': 'डाउनलोड सुरू होइस', 'cancel': 'डाउनलोड रोकव', 'one': 'एक बेर म एक मॉडल रहिथे। नवा लेबे त जुन्ना हट जाही।',
      'offline': 'डाउनलोड के बाद बिना इंटरनेट चलथे। अवाज फ़ोन ले बाहिर नइ जाय।',
    },
    'en': {
      'title': 'Speech model',
      'intro': 'Turns a call recording into text, fully offline. We picked the best one for your phone.',
      'choose': 'Choose a model',
      'vosk-small-hi': 'Hindi · Small', 'vosk-small-hi_d': 'Hindi & Chhattisgarhi · fast',
      'vosk-small-en-in': 'Indian English · Small', 'vosk-small-en-in_d': 'For calls in English',
      'vosk-hi': 'Hindi · Large', 'vosk-hi_d': 'Most accurate · slower',
      'rec': 'Recommended for this phone', 'low_ram': 'Best with {n} GB RAM', 'low_storage': 'Needs {n} free',
      'installed': 'Installed', 'download': 'Download {s}', 'replace': 'Switch to this · {s}',
      'downloading': 'Downloading…', 'ready': 'Speech model ready', 'failed': 'Could not download. Check the internet and try again.',
      'started': 'Download started', 'cancel': 'Cancel download', 'one': 'One model is kept at a time. A new one replaces the old.',
      'offline': 'Works offline after the download. Audio never leaves the phone.',
    },
  };

  static String t(String lang, String k, [Map<String, Object?> a = const {}]) {
    var s = _m[lang]?[k] ?? _m['en']![k] ?? k;
    a.forEach((key, v) => s = s.replaceAll('{$key}', '$v'));
    return s;
  }
}

class _SpeechModelScreenState extends State<SpeechModelScreen> {
  late final RecordingApi _api = widget.api ?? RecordingApi();
  StreamSubscription<Object?>? _sub;
  DeviceInfo _dev = const DeviceInfo();
  bool _ready = false, _loaded = false, _downloading = false;
  String? _installed, _picked;
  int _pct = 0;

  @override
  void initState() {
    super.initState();
    _sub = _api.events.listen(_onEvent, onError: (_) {});
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final dev = await widget.models.device();
    final st = await _api.status();
    if (!mounted) return;
    setState(() {
      _dev = dev;
      _ready = st.ready;
      _installed = st.ready ? (st.sttId ?? kSttModels.first.id) : null;
      _loaded = true;
    });
  }

  String _t(String k, [Map<String, Object?> a = const {}]) => SpeechStrings.t(AppLanguage.of(context), k, a);

  SttModel get _sel => sttById(_picked ?? _installed ?? recommendSttId(AppLanguage.of(context)));

  void _onEvent(Object? raw) {
    if (!mounted || raw is! Map || raw['stage'] != 'download') {
      if (mounted && raw is Map && raw['stage'] == 'error' && _downloading) {
        setState(() => _downloading = false);
        showIsland(context, _t('failed'), tone: IslandTone.danger);
      }
      return;
    }
    setState(() {
      _pct = (raw['pct'] as num?)?.toInt() ?? _pct;
      if (raw['ready'] == true) {
        _downloading = false;
        _ready = true;
        _installed = _sel.id;
        _picked = null;
      }
    });
    if (raw['ready'] == true) showIsland(context, _t('ready'), tone: IslandTone.success);
  }

  Future<void> _download() async {
    final m = _sel;
    setState(() {
      _downloading = true;
      _pct = 0;
    });
    final ok = await _api.downloadModel(m.id);
    if (!mounted) return;
    if (!ok) {
      setState(() => _downloading = false);
      showIsland(context, _t('failed'), tone: IslandTone.danger);
    } else {
      showIsland(context, _t('started'), tone: IslandTone.info, icon: Icons.download_rounded);
    }
  }

  Future<void> _cancel() async {
    await _api.cancel();
    if (mounted) setState(() => _downloading = false);
  }

  (String, Color, Color)? _tag(SttModel m) {
    final st = Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
    if (_installed == m.id && _ready) return (_t('installed'), palOf(context).accent, palOf(context).accentTint);
    return switch (sttBlockFor(m, _dev)) {
      SttBlock.lowRam => (_t('low_ram', {'n': (m.minRamMb / 1000).round()}), st.suspicious, st.suspicious.withValues(alpha: 0.14)),
      SttBlock.lowStorage => (_t('low_storage', {'n': '${(m.neededMb / 1000).toStringAsFixed(1)} GB'}), st.suspicious, st.suspicious.withValues(alpha: 0.14)),
      null => m.id == recommendSttId(AppLanguage.of(context)) ? (_t('rec'), st.safe, st.safe.withValues(alpha: 0.14)) : null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final p = palOf(context);
    final lang = AppLanguage.of(context);
    final sel = _sel;
    final isInstalled = _ready && _installed == sel.id;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.xl),
      children: [
        Text(_t('intro'), style: th.textTheme.bodyLarge?.copyWith(color: p.muted, fontSize: 17)),
        const SizedBox(height: Sp.l),
        DeviceCard(key: const Key('sm_device'), dev: _dev, t: (k) => profileT(lang, k)),
        const SizedBox(height: Sp.l + 2),
        Semantics(header: true, child: Text(_t('choose'), style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
        const SizedBox(height: Sp.s),
        for (final m in kSttModels) ...[_option(th, p, m, m.id == sel.id), const SizedBox(height: Sp.s)],
        const SizedBox(height: Sp.s),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: _downloading
              ? Padding(
                  padding: const EdgeInsets.only(bottom: Sp.m),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Rad.pill),
                      child: LinearProgressIndicator(key: const Key('sm_progress'), value: _pct > 0 ? _pct / 100 : null, minHeight: 8),
                    ),
                    const SizedBox(height: Sp.xs),
                    Text('${_t('downloading')} $_pct%', style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
                  ]),
                )
              : const SizedBox(width: double.infinity),
        ),
        FilledButton.icon(
          key: const Key('sm_action'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
          onPressed: !_loaded || _downloading || isInstalled ? null : _download,
          icon: Icon(isInstalled ? Icons.check_circle_rounded : Icons.download_rounded),
          label: Text(isInstalled
              ? _t('installed')
              : _downloading
                  ? _t('downloading')
                  : _t(_ready ? 'replace' : 'download', {'s': sel.sizeLabel})),
        ),
        if (_downloading) TextButton(key: const Key('sm_cancel'), onPressed: _cancel, child: Text(_t('cancel'))),
        const SizedBox(height: Sp.m),
        _note(th, p, Icons.wifi_off_rounded, _t('offline')),
        const SizedBox(height: Sp.xs),
        _note(th, p, Icons.swap_horiz_rounded, _t('one')),
      ],
    );
  }

  Widget _note(ThemeData th, Pal p, IconData icon, String text) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: p.muted),
        const SizedBox(width: Sp.s),
        Expanded(child: Text(text, style: th.textTheme.bodySmall?.copyWith(color: p.muted))),
      ]);

  Widget _option(ThemeData th, Pal p, SttModel m, bool on) {
    final tag = _tag(m);
    return Semantics(
      selected: on,
      button: true,
      child: Material(
        color: on ? p.accentTint : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: on ? p.accent : p.hairline, width: on ? 2 : 1),
        ),
        child: InkWell(
          key: Key('sm_opt_${m.id}'),
          borderRadius: BorderRadius.circular(18),
          onTap: _downloading ? null : () => setState(() => _picked = m.id),
          child: Padding(
            padding: const EdgeInsets.all(Sp.m + 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: on ? p.accent : (p.isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF0F0F2)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.graphic_eq_rounded, color: on ? p.onAccent : p.ink, size: 22),
              ),
              const SizedBox(width: Sp.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_t(m.id), style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text('${m.sizeLabel} · ${_t('${m.id}_d')}', style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
                  if (tag != null)
                    Container(
                      margin: const EdgeInsets.only(top: Sp.xs),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: tag.$3, borderRadius: BorderRadius.circular(Sp.m)),
                      child: Text(tag.$1, style: th.textTheme.labelSmall?.copyWith(color: tag.$2, fontWeight: FontWeight.w700)),
                    ),
                ]),
              ),
              if (on) Icon(Icons.check_circle_rounded, color: p.accent),
            ]),
          ),
        ),
      ),
    );
  }
}
