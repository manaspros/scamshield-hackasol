import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/verdict.dart';
import '../theme/app_theme.dart' show StatusColors;
import '../theme/tokens.dart';
import '../widgets/action_tile.dart';
import '../widgets/section_header.dart';
import '../widgets/state_message.dart';
import '../widgets/status_chip.dart';
import 'report_screen.dart';

/// Client for the native recording channel (K/RecordingChannel.kt).
/// Method calls return false instead of throwing, so the screen shows an error, not a crash.
/// Events (EventChannel `scamshield/recording/events`) are maps:
///   {stage: download|decode|stt|classify|done|error|shared, pct: 0..100,
///    segment?: {startMs, text}            (stt),
///    statement?: {startMs, text, label, triggers}   (classify),
///    ready?: true                         (download finished),
///    report?: {overall, risk, statements: [statement...], topTriggers}   (done),
///    code?: failed|noSpeech|download|cancelled      (error)}
class RecordingApi {
  RecordingApi({MethodChannel? channel, Stream<Object?>? events})
      : channel = channel ?? const MethodChannel('scamshield/recording'),
        events = events ?? const EventChannel('scamshield/recording/events').receiveBroadcastStream();
  final MethodChannel channel;
  final Stream<Object?> events;

  Future<bool> _ok(String m) async {
    try {
      return await channel.invokeMethod<bool>(m) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> modelReady() async {
    try {
      final m = await channel.invokeMapMethod<Object?, Object?>('recording.status');
      return m?['modelReady'] == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// True when a file was chosen (or one was shared in) and is waiting for [start].
  Future<bool> pending() => _ok('recording.pending');
  Future<bool> pick() => _ok('recording.pick');
  Future<bool> start() => _ok('recording.start');
  Future<bool> downloadModel() => _ok('recording.downloadModel');
  Future<bool> cancel() => _ok('recording.cancel');
}

/// Screen text in Hindi (default), Chhattisgarhi and English; same keys in all three.
class RecordingStrings {
  const RecordingStrings(this.m);
  final Map<String, String> m;
  String operator [](String k) => m[k] ?? k;

  static const hi = RecordingStrings({
    'title': 'कॉल की रिकॉर्डिंग जाँचें',
    'pick': 'रिकॉर्डिंग चुनें',
    'pickSub': 'फ़ोन में रखी कॉल रिकॉर्डिंग खोलें।',
    'download': 'पहले बोली पहचानने वाला मॉडल लें',
    'downloadSub': 'सिर्फ़ एक बार, लगभग 42 MB। उसके बाद बिना इंटरनेट चलेगा।',
    'cancel': 'रोकें',
    'stage_download': 'मॉडल उतर रहा है',
    'stage_decode': 'आवाज़ खोली जा रही है',
    'stage_stt': 'बात सुनकर लिखी जा रही है',
    'stage_classify': 'हर बात जाँची जा रही है',
    'riskTitle': 'पूरी कॉल का ख़तरा',
    'triggers': 'शक वाले शब्द',
    'timeline': 'कॉल में क्या-क्या कहा गया',
    'report': 'शिकायत दर्ज करें',
    'reportSub': 'सबूत और 1930 की मदद',
    'privacy': 'आवाज़ और लिखा हुआ पाठ सिर्फ़ इस स्क्रीन पर रहता है। ऐप इन्हें सहेजता नहीं।',
    'err_failed': 'रिकॉर्डिंग जाँची नहीं जा सकी। दूसरी फ़ाइल चुनें।',
    'err_noSpeech': 'इसमें बोली नहीं मिली। दूसरी फ़ाइल चुनें।',
    'err_download': 'मॉडल नहीं उतर सका। इंटरनेट देखकर फिर कोशिश करें।',
    'l_safe': 'सामान्य',
    'l_suspicious': 'सावधान',
    'l_scam': 'ठगी',
    'empty': 'कॉल की रिकॉर्डिंग चुनें, हम बताएँगे कि कहीं ठगी तो नहीं',
    'listening': 'सुन रहे हैं… लंबी रिकॉर्डिंग में कुछ मिनट लग सकते हैं',
    'counter': 'जाँची गई बातें: {n}',
    'retry': 'फिर कोशिश करें',
    'sum_safe': 'इस कॉल में ठगी के संकेत नहीं मिले।',
    'sum_suspicious': 'इस कॉल में कुछ बातें शक वाली हैं। सावधान रहें।',
    'sum_scam': 'इस कॉल में ठगी के संकेत हैं। पैसे या OTP न दें।',
    'firstFlag': 'पहली चेतावनी {t} पर आई',
  });

  static const hne = RecordingStrings({
    'title': 'कॉल के रिकॉर्डिंग जांचव',
    'pick': 'रिकॉर्डिंग चुनव',
    'pickSub': 'फोन म रखाय कॉल रिकॉर्डिंग खोलव।',
    'download': 'पहिली बोली चिन्हइया मॉडल लव',
    'downloadSub': 'सिरिफ एक पईंत, लगभग 42 MB। तेकर बाद बिना इंटरनेट चलही।',
    'cancel': 'रोकव',
    'stage_download': 'मॉडल उतरत हे',
    'stage_decode': 'अवाज खोले जात हे',
    'stage_stt': 'गोठ सुन के लिखे जात हे',
    'stage_classify': 'हर गोठ जांचे जात हे',
    'riskTitle': 'पूरा कॉल के खतरा',
    'triggers': 'शक वाले सब्द',
    'timeline': 'कॉल म का-का कहे गिस',
    'report': 'शिकायत दर्ज करव',
    'reportSub': 'सबूत अउ 1930 के मदद',
    'privacy': 'अवाज अउ लिखे पाठ सिरिफ ए स्क्रीन म रहिथे। ऐप ह एला सहेजय नइ।',
    'err_failed': 'रिकॉर्डिंग जांचे नइ जा सकिस। दूसर फाइल चुनव।',
    'err_noSpeech': 'एमा बोली नइ मिलिस। दूसर फाइल चुनव।',
    'err_download': 'मॉडल नइ उतर सकिस। इंटरनेट देख के फेर कोसिस करव।',
    'l_safe': 'सामान्य',
    'l_suspicious': 'सावधान',
    'l_scam': 'ठगी',
    'empty': 'कॉल के रिकॉर्डिंग चुनव, हम बताबो कि कहूँ ठगी तो नइहे',
    'listening': 'सुनत हन… लंबा रिकॉर्डिंग म कुछ मिनट लग सकथे',
    'counter': 'जांचे गोठ: {n}',
    'retry': 'फेर कोसिस करव',
    'sum_safe': 'ए कॉल म ठगी के संकेत नइ मिलिस।',
    'sum_suspicious': 'ए कॉल म कुछ गोठ शक वाले हें। सावधान रहव।',
    'sum_scam': 'ए कॉल म ठगी के संकेत हे। पइसा या OTP झन देव।',
    'firstFlag': 'पहिली चेतावनी {t} म आइस',
  });

  static const en = RecordingStrings({
    'title': 'Check a call recording',
    'pick': 'Pick a recording',
    'pickSub': 'Open a call recording saved on this phone.',
    'download': 'First get the speech model',
    'downloadSub': 'One time, about 42 MB. After that it works offline.',
    'cancel': 'Stop',
    'stage_download': 'Downloading the model',
    'stage_decode': 'Opening the audio',
    'stage_stt': 'Listening and writing it down',
    'stage_classify': 'Checking each statement',
    'riskTitle': 'Risk for the whole call',
    'triggers': 'Suspicious phrases',
    'timeline': 'What was said in the call',
    'report': 'Report a scam',
    'reportSub': 'Evidence and the 1930 helpline',
    'privacy': 'The audio and the text stay on this screen only. The app does not save them.',
    'err_failed': 'Could not check this recording. Pick another file.',
    'err_noSpeech': 'No speech found in this file. Pick another file.',
    'err_download': 'Could not download the model. Check the internet and try again.',
    'l_safe': 'Normal',
    'l_suspicious': 'Be careful',
    'l_scam': 'Scam',
    'empty': 'Pick a call recording and we will tell you if it is a scam',
    'listening': 'Listening… a long recording can take a few minutes',
    'counter': '{n} statements checked',
    'retry': 'Try again',
    'sum_safe': 'No signs of a scam were found in this call.',
    'sum_suspicious': 'Some things in this call look suspicious. Be careful.',
    'sum_scam': 'This call shows signs of a scam. Do not give money or an OTP.',
    'firstFlag': 'First warning came at {t}',
  });

  static const all = {'hi': hi, 'hne': hne, 'en': en};
  static RecordingStrings of(String lang) => all[lang] ?? hi;
}

class _Stmt {
  _Stmt(Map<Object?, Object?> m)
      : startMs = (m['startMs'] as num?)?.toInt() ?? 0,
        text = '${m['text'] ?? ''}',
        label = parseLabel(m['label']),
        triggers = ((m['triggers'] as List?) ?? const []).map((e) => '$e').toList();
  final int startMs;
  final String text;
  final RiskLabel label;
  final List<String> triggers;
}

class _Report {
  _Report(Map<Object?, Object?> m)
      : overall = parseLabel(m['overall']),
        risk = ((m['risk'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
        statements = ((m['statements'] as List?) ?? const []).map((e) => _Stmt((e as Map).cast<Object?, Object?>())).toList(),
        topTriggers = ((m['topTriggers'] as List?) ?? const []).map((e) => '$e').toList();
  final RiskLabel overall;
  final double risk;
  final List<_Stmt> statements;
  final List<String> topTriggers;
}

enum _Phase { idle, working, done, error }

/// Recorded-call screen: pick an audio file (or receive a shared one), watch progress, then read the
/// per-statement timeline and the overall risk. Constructible standalone; T3.11 wires navigation.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key, this.initialLang = 'hi', this.api});
  final String initialLang;

  /// Injected in tests; the default talks to the native channel.
  final RecordingApi? api;
  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  late final RecordingApi _api = widget.api ?? RecordingApi();
  late String _lang = widget.initialLang;
  StreamSubscription<Object?>? _sub;
  _Phase _phase = _Phase.idle;
  bool _modelReady = true; // optimistic until native says otherwise, so the pick tile never flickers
  String _stage = 'decode';
  int _pct = 0;
  String? _heard;
  String _errKey = 'err_failed';
  final List<_Stmt> _live = [];
  _Report? _report;

  @override
  void initState() {
    super.initState();
    _sub = _api.events.listen(_onEvent, onError: (_) {});
    _restore();
  }

  @override
  void dispose() {
    _sub?.cancel();
    // Leaving the screen ends the session: stop work and drop the pending file.
    if (_phase == _Phase.working) _api.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    final ready = await _api.modelReady();
    final pending = await _api.pending(); // a file shared in before this screen existed
    if (!mounted) return;
    setState(() => _modelReady = ready);
    if (pending && ready && _phase == _Phase.idle) _start();
  }

  Future<void> _pick() async {
    if (await _api.pick() && mounted) _start();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.working;
      _stage = 'decode';
      _pct = 0;
      _heard = null;
      _live.clear();
      _report = null;
    });
    if (!await _api.start() && mounted) _fail('err_failed');
  }

  Future<void> _download() async {
    setState(() {
      _phase = _Phase.working;
      _stage = 'download';
      _pct = 0;
    });
    if (!await _api.downloadModel() && mounted) _fail('err_download');
  }

  Future<void> _cancel() async {
    await _api.cancel();
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  void _fail(String key) => setState(() {
        _phase = _Phase.error;
        _errKey = key;
      });

  void _onEvent(Object? raw) {
    if (!mounted || raw is! Map) return;
    final e = raw.cast<Object?, Object?>();
    final stage = '${e['stage']}';
    final pct = (e['pct'] as num?)?.toInt();
    setState(() {
      switch (stage) {
        case 'shared':
          if (_phase != _Phase.working && _modelReady) Future.microtask(_start);
        case 'download':
          if (_phase != _Phase.working) return;
          _stage = stage;
          _pct = pct ?? _pct;
          if (e['ready'] == true) {
            _modelReady = true;
            _phase = _Phase.idle;
          }
        case 'decode' || 'stt' || 'classify':
          if (_phase != _Phase.working) return;
          _stage = stage;
          _pct = pct ?? _pct;
          final seg = e['segment'];
          if (seg is Map) _heard = '${seg['text'] ?? ''}';
          final st = e['statement'];
          if (st is Map) _live.add(_Stmt(st.cast<Object?, Object?>()));
        case 'done':
          final r = e['report'];
          if (r is! Map) {
            _fail('err_failed');
          } else {
            _report = _Report(r.cast<Object?, Object?>());
            _phase = _Phase.done;
          }
        case 'error':
          if (e['code'] == 'cancelled') {
            _phase = _Phase.idle;
          } else {
            _fail(switch ('${e['code']}') {
              'noSpeech' => 'err_noSpeech',
              'download' => 'err_download',
              _ => 'err_failed',
            });
          }
      }
    });
  }

  String _clock(int ms) =>
      '${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';

  String _label(RecordingStrings s, RiskLabel l) => s['l_${l.name}'];

  void _openReport() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(ReportStrings.of(_lang)['title'])),
          body: ReportScreen(initialLang: _lang),
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final s = RecordingStrings.of(_lang);
    final t = Theme.of(context);
    final working = _phase == _Phase.working;
    final timeline = _report?.statements ?? _live;
    final err = _phase == _Phase.error;
    final empty = _phase == _Phase.idle && timeline.isEmpty && _modelReady;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Sp.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title: s['title'], icon: Icons.graphic_eq),
                if (empty) StateMessage(icon: Icons.graphic_eq, title: s['empty'], subtitle: s['pickSub']),
                if (!_modelReady && !working && !err) _downloadStep(t, s),
                if (working) _progress(t, s),
                if (err) _error(t, s),
                if (_report != null) ..._summary(t, s, _report!),
                if (timeline.isNotEmpty) ...[
                  SectionHeader(title: s['timeline'], icon: Icons.timeline),
                  for (final (i, st) in timeline.indexed) _row(t, s, i, st, last: i == timeline.length - 1),
                ],
                if (_report != null && _report!.topTriggers.isNotEmpty) _triggers(t, s, _report!),
                const SizedBox(height: Sp.xl),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.lock, size: 24, color: t.colorScheme.onSurfaceVariant),
                  const SizedBox(width: Sp.s),
                  Expanded(
                    child: Text(s['privacy'],
                        key: const Key('privacy_line'),
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ),
                ]),
                const SizedBox(height: Sp.l),
                Wrap(spacing: Sp.s, runSpacing: Sp.xs, children: [
                  for (final (code, label) in const [('hi', 'हिन्दी'), ('hne', 'छत्तीसगढ़ी'), ('en', 'English')])
                    ChoiceChip(
                      key: Key('lang_$code'),
                      label: Text(label),
                      selected: _lang == code,
                      checkmarkColor: t.colorScheme.primary,
                      onSelected: (_) => setState(() => _lang = code),
                    ),
                ]),
              ],
            ),
          ),
        ),
        // The one primary action stays pinned: pick a file, or get the model first.
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.l),
          child: FilledButton.icon(
            key: Key(_modelReady ? 'btn_pick' : 'btn_download'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
            onPressed: working ? null : (_modelReady ? _pick : _download),
            icon: Icon(_modelReady ? Icons.audio_file : Icons.download, size: 28),
            label: Text(_modelReady ? s['pick'] : s['download'], textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }

  Widget _downloadStep(ThemeData t, RecordingStrings s) => _card(
        t,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.download, size: 40, color: t.colorScheme.primary),
          const SizedBox(width: Sp.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['download'], style: t.textTheme.titleMedium),
              Text(s['downloadSub'], style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]),
      );

  Widget _card(ThemeData t, Widget child, {Color? color, Color? border}) => Container(
        padding: const EdgeInsets.all(Sp.l),
        margin: const EdgeInsets.only(top: Sp.m),
        decoration: BoxDecoration(
          color: color ?? t.colorScheme.surface,
          borderRadius: BorderRadius.circular(Rad.lg),
          border: Border.all(color: border ?? t.colorScheme.outline),
        ),
        child: child,
      );

  Widget _progress(ThemeData t, RecordingStrings s) => _card(
        t,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(_stage == 'download' ? Icons.download : Icons.hearing, size: 32, color: t.colorScheme.primary),
            const SizedBox(width: Sp.m),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text('${s['stage_$_stage']}  $_pct%', key: const Key('progress_stage'), style: t.textTheme.titleMedium),
              ),
            ),
          ]),
          const SizedBox(height: Sp.m),
          ClipRRect(
            borderRadius: BorderRadius.circular(Rad.pill),
            child: LinearProgressIndicator(
              key: const Key('progress_bar'),
              value: _pct > 0 ? _pct / 100 : null,
              minHeight: 12,
            ),
          ),
          const SizedBox(height: Sp.m),
          Text(_stage == 'download' ? s['downloadSub'] : s['listening'],
              key: const Key('progress_hint'),
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          if (_live.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Sp.s),
              child: Text(s['counter'].replaceAll('{n}', '${_live.length}'),
                  key: const Key('progress_counter'), style: t.textTheme.titleSmall),
            ),
          if (_heard != null && _heard!.isNotEmpty) ...[
            const SizedBox(height: Sp.m),
            Text(_heard!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyLarge),
          ],
          const SizedBox(height: Sp.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('btn_cancel'),
              onPressed: _cancel,
              child: Text(s['cancel'], style: t.textTheme.labelLarge),
            ),
          ),
        ]),
      );

  // Download failures retry the download; the rest reopen the file picker.
  Widget _error(ThemeData t, RecordingStrings s) => KeyedSubtree(
        key: const Key('error_text'),
        child: StateMessage(
          icon: Icons.error_outline,
          title: s[_errKey],
          actionLabel: s['retry'],
          onAction: _errKey == 'err_download' ? _download : _pick,
        ),
      );

  List<Widget> _summary(ThemeData t, RecordingStrings s, _Report r) {
    final st = t.extension<StatusColors>() ?? StatusColors.light;
    final solid = st.solid(r.overall);
    final first = r.statements.where((x) => x.label != RiskLabel.safe).firstOrNull;
    return [
      _card(
        t,
        color: st.tintOver(r.overall, t.colorScheme.surface),
        border: solid.withValues(alpha: 0.35),
        Column(key: const Key('risk_card'), crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['riskTitle'], style: t.textTheme.titleMedium),
          const SizedBox(height: Sp.s),
          Row(children: [
            StatusChip(label: r.overall, text: _label(s, r.overall)),
            const SizedBox(width: Sp.m),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text('${(r.risk * 100).round()}%',
                    key: const Key('risk_value'), style: t.textTheme.headlineMedium?.copyWith(color: solid)),
              ),
            ),
          ]),
          const SizedBox(height: Sp.m),
          Text(s['sum_${r.overall.name}'], style: t.textTheme.bodyLarge),
          if (first != null)
            Padding(
              padding: const EdgeInsets.only(top: Sp.xs),
              child: Text(s['firstFlag'].replaceAll('{t}', _clock(first.startMs)), style: t.textTheme.bodySmall),
            ),
        ]),
      ),
      // 1930 and the evidence pack live behind this button (ReportScreen has the dialer).
      if (r.overall != RiskLabel.safe) ...[
        const SizedBox(height: Sp.m),
        ActionTile(
          key: const Key('btn_report'),
          icon: Icons.report_problem,
          label: s['report'],
          caption: s['reportSub'],
          onTap: _openReport,
        ),
      ],
    ];
  }

  // After the story, so the timeline sits right under the summary.
  Widget _triggers(ThemeData t, RecordingStrings s, _Report r) => _card(
        t,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.search, size: 32),
            const SizedBox(width: Sp.m),
            Expanded(child: Text(s['triggers'], style: t.textTheme.titleLarge)),
          ]),
          const SizedBox(height: Sp.s),
          Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
            for (final (i, trig) in r.topTriggers.indexed)
              Container(
                key: Key('trigger_$i'),
                padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: Sp.s),
                decoration: BoxDecoration(
                  color: t.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(Rad.sm),
                ),
                child: Text(trig, style: t.textTheme.titleSmall),
              ),
          ]),
        ]),
      );

  // Story row: a status-coloured rail with a dot, then time, the line said and its verdict.
  // The rail changes colour where the call turns risky. Content stacks so 2.0x text never overflows.
  Widget _row(ThemeData t, RecordingStrings s, int i, _Stmt st, {required bool last}) {
    final sc = t.extension<StatusColors>() ?? StatusColors.light;
    final c = sc.solid(st.label);
    return IntrinsicHeight(
      key: Key('row_$i'),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 20,
          child: Column(children: [
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(top: Sp.xs),
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            if (last)
              const Spacer()
            else
              Expanded(child: Container(width: 3, margin: const EdgeInsets.only(top: Sp.xs), color: c)),
          ]),
        ),
        const SizedBox(width: Sp.m),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Sp.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_clock(st.startMs),
                  key: Key('row_time_$i'),
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              Text(st.text, style: t.textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic)),
              const SizedBox(height: Sp.s),
              StatusChip(label: st.label, text: _label(s, st.label)),
              if (st.label != RiskLabel.safe && st.triggers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Sp.xs),
                  child: Text('${s['triggers']}: ${st.triggers.join(', ')}', style: t.textTheme.bodySmall),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
