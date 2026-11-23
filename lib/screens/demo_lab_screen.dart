import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/verdict.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/section_header.dart';
import '../widgets/state_message.dart';
import '../widgets/status_chip.dart';

Map<String, Object?> _m(Object? o) => o is Map ? {for (final e in o.entries) '${e.key}': e.value} : <String, Object?>{};
List<Map<String, Object?>> _ml(Object? o) => o is List ? [for (final e in o) _m(e)] : <Map<String, Object?>>[];
List<String> _sl(Object? o) => o is List ? [for (final e in o) '$e'] : <String>[];
String _s(Object? o, [String d = '']) => o == null ? d : '$o';

/// Client for the native demo channel (scamshield/demo). Failures come back as null / false,
/// so the screen can show a plain message instead of throwing.
class DemoApi {
  const DemoApi([this.channel = const MethodChannel('scamshield/demo')]);
  final MethodChannel channel;

  Future<Object?> _call(String method, [Object? args]) async {
    try {
      return await channel.invokeMethod<Object?>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// null = the channel is missing or failed; an empty list = no scenarios.
  Future<List<Map<String, Object?>>?> scenarios() async {
    final r = await _call('demo.scenarios');
    return r is List ? _ml(r) : null;
  }

  Future<bool> modelReady() async => await _call('demo.modelReady') == true;

  Future<Map<String, Object?>?> run(String id, {required bool gemma, required bool coldStart}) async {
    final r = await _call('demo.run', {'id': id, 'engine': gemma ? 'gemma' : 'rules', 'coldStart': coldStart});
    return r is Map ? _m(r) : null;
  }

  Future<bool> reset() async {
    try {
      await channel.invokeMethod<void>('demo.reset');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// Screen text in Hindi (default), Chhattisgarhi and English; same keys in all three.
class DemoStrings {
  const DemoStrings(this.m);
  final Map<String, String> m;
  String operator [](String k) => m[k] ?? k;

  static const hi = DemoStrings({
    'title': 'डेमो लैब',
    'about': 'असली जैसी कहानियाँ चलाकर देखें कि ऐप क्या समझता है: संदर्भ ग्राफ़, नियम, Gemma और अंतिम चेतावनी। '
        'जैसे: खाते से पैसे कटने का SMS आया, फिर कॉल आई "पैसे लौटा दो"। ऐप को याद है कि वह SMS बैंक का नहीं, किसी इंसान का लिखा था।',
    'demoNote': 'डेमो सूचनाएँ [DEMO] से शुरू होती हैं। ये असली नहीं हैं।',
    'gemmaOn': 'Gemma चालू',
    'noModel': 'मॉडल तैयार नहीं है, इसलिए सिर्फ़ नियम चलेंगे।',
    'cold': 'Cold start (खाली ग्राफ़)',
    'coldSub': 'पुराना संदर्भ हटाकर शुरू करें',
    'runAll': 'सब चलाएँ',
    'reset': 'डेमो रीसेट करें',
    'resetOk': 'डेमो का डेटा हटा दिया',
    'resetErr': 'रीसेट नहीं हो सका',
    'skip': 'एनीमेशन छोड़ें',
    'run': 'चलाएँ',
    'running': 'चल रहा है…',
    'steps': 'घटनाएँ',
    'event': 'घटना',
    'st1': 'घटना आई',
    'st2': 'ग्राफ़ संदर्भ',
    'st3': 'नियम से मिले संकेत',
    'st4': 'Gemma का जवाब',
    'st5': 'अंतिम फ़ैसला',
    'st6': 'अलर्ट भेजा',
    'noContext': 'कोई पुराना संदर्भ नहीं (खाली ग्राफ़)',
    'noRules': 'कोई नियम नहीं लगा',
    'rulesOnly': 'सिर्फ़ नियम, Gemma नहीं',
    'noAlert': 'कोई अलर्ट नहीं भेजा गया',
    'expected': 'अपेक्षित',
    'got': 'मिला',
    'flagsExp': 'अपेक्षित संकेत',
    'flagsGot': 'मिले संकेत',
    'engine': 'इंजन',
    'note': 'नोट',
    'conf': 'भरोसा',
    'type': 'प्रकार',
    'raisedBy': 'किसने बढ़ाया',
    'now': 'अभी',
    'reportAction': 'रिपोर्ट करें',
    'next': 'अगली घटना आ रही है…',
    'loading': 'लोड हो रहा है…',
    'unavailable': 'डेमो नहीं खुला',
    'unavailableSub': 'फ़ोन का डेमो हिस्सा जवाब नहीं दे रहा',
    'retry': 'फिर कोशिश करें',
    'runErr': 'यह डेमो नहीं चल सका',
  });

  static const hne = DemoStrings({
    'title': 'डेमो लैब',
    'about': 'असली कस कहिनी चला के देखव कि ऐप का समझथे: संदर्भ ग्राफ़, नियम, Gemma अउ आखिरी चेतावनी। '
        'जइसे: खाता ले पइसा कटे के SMS आइस, फेर फोन आइस "पइसा लहुटा दे"। ऐप ल सुरता हे कि वो SMS बैंक के नइ, कोनो मनखे के लिखे रिहिस।',
    'demoNote': 'डेमो सूचना [DEMO] ले सुरू होथे। ये असली नइ हें।',
    'gemmaOn': 'Gemma चालू',
    'noModel': 'मॉडल तियार नइ हे, एकरे सेती सिरिफ नियम चलही।',
    'cold': 'Cold start (खाली ग्राफ़)',
    'coldSub': 'जुन्ना संदर्भ हटा के सुरू करव',
    'runAll': 'सब चलावव',
    'reset': 'डेमो रीसेट करव',
    'resetOk': 'डेमो के डेटा हटा दिस',
    'resetErr': 'रीसेट नइ हो सकिस',
    'skip': 'एनीमेशन छोड़व',
    'run': 'चलावव',
    'running': 'चलत हे…',
    'steps': 'घटना',
    'event': 'घटना',
    'st1': 'घटना आइस',
    'st2': 'ग्राफ़ संदर्भ',
    'st3': 'नियम ले मिले संकेत',
    'st4': 'Gemma के जवाब',
    'st5': 'आखिरी फ़ैसला',
    'st6': 'अलर्ट भेजिस',
    'noContext': 'कोनो जुन्ना संदर्भ नइ हे (खाली ग्राफ़)',
    'noRules': 'कोनो नियम नइ लगिस',
    'rulesOnly': 'सिरिफ नियम, Gemma नइ',
    'noAlert': 'कोनो अलर्ट नइ भेजिस',
    'expected': 'अपेक्षित',
    'got': 'मिलिस',
    'flagsExp': 'अपेक्षित संकेत',
    'flagsGot': 'मिले संकेत',
    'engine': 'इंजन',
    'note': 'नोट',
    'conf': 'भरोसा',
    'type': 'किसम',
    'raisedBy': 'काकर ले बढ़िस',
    'now': 'अभी',
    'reportAction': 'रिपोर्ट करव',
    'next': 'अगली घटना आवत हे…',
    'loading': 'लोड होवत हे…',
    'unavailable': 'डेमो नइ खुलिस',
    'unavailableSub': 'फोन के डेमो हिस्सा जवाब नइ देवत हे',
    'retry': 'फेर कोसिस करव',
    'runErr': 'ये डेमो नइ चलिस',
  });

  static const en = DemoStrings({
    'title': 'Demo Lab',
    'about': 'Run realistic stories and see what the app understands: the context graph, rules, Gemma and the final alert. '
        'Example: an SMS says money was debited, then a call asks you to give it back. The app remembers that SMS was typed by a person, not sent by a bank.',
    'demoNote': 'Demo alerts start with [DEMO]. They are not real.',
    'gemmaOn': 'Gemma on',
    'noModel': 'The model is not ready, so only rules will run.',
    'cold': 'Cold start (empty graph)',
    'coldSub': 'Clear earlier context before each run',
    'runAll': 'Run all',
    'reset': 'Reset demo',
    'resetOk': 'Demo data cleared',
    'resetErr': 'Could not reset',
    'skip': 'Skip animation',
    'run': 'Run',
    'running': 'Running…',
    'steps': 'events',
    'event': 'Event',
    'st1': 'Event ingested',
    'st2': 'Known context',
    'st3': 'Rule hits (masked)',
    'st4': 'Gemma output',
    'st5': 'Fusion',
    'st6': 'Alert fired',
    'noContext': 'No earlier context (empty graph)',
    'noRules': 'No rule matched',
    'rulesOnly': 'Rules only, no Gemma',
    'noAlert': 'No alert fired',
    'expected': 'Expected',
    'got': 'Got',
    'flagsExp': 'Expected flags',
    'flagsGot': 'Actual flags',
    'engine': 'Engine',
    'note': 'Note',
    'conf': 'Confidence',
    'type': 'Type',
    'raisedBy': 'Raised by',
    'now': 'now',
    'reportAction': 'Report',
    'next': 'Next event coming…',
    'loading': 'Loading…',
    'unavailable': 'Demo did not open',
    'unavailableSub': 'The phone side of the demo is not answering',
    'retry': 'Try again',
    'runErr': 'This demo could not run',
  });

  static const all = {'hi': hi, 'hne': hne, 'en': en};
  static DemoStrings of(String lang) => all[lang] ?? hi;
}

const _icons = <String, IconData>{
  'sms': Icons.sms,
  'call': Icons.call,
  'phone_in_talk': Icons.phone_in_talk,
  'account_balance': Icons.account_balance,
  'currency_rupee': Icons.currency_rupee,
  'payments': Icons.payments,
  'warning': Icons.warning,
  'shield': Icons.shield,
  'security': Icons.security,
  'support_agent': Icons.support_agent,
  'qr_code': Icons.qr_code,
  'local_shipping': Icons.local_shipping,
  'chat': Icons.chat,
  'mail': Icons.mail,
  'work': Icons.work,
  'swap_horiz': Icons.swap_horiz,
  'science': Icons.science,
};

/// Longest wait between two timeline events, so a long scripted gap never stalls the demo.
const _maxDelayMs = 1500;

String _headline(RiskLabel l) => switch (l) {
      RiskLabel.safe => 'सुरक्षित',
      RiskLabel.suspicious => 'सावधान',
      RiskLabel.scam => 'धोखाधड़ी!',
    };

String _join(List<String> l) => l.isEmpty ? '—' : l.join(', ');

/// Feature-flagged test bench: runs scripted SMS / call stories through the real pipeline
/// (graph context, rules, Gemma, fusion, alert) and shows every stage with a PASS / FAIL badge.
class DemoLabScreen extends StatefulWidget {
  const DemoLabScreen({super.key, this.initialLang = 'hi', this.api = const DemoApi()});
  final String initialLang;
  final DemoApi api;

  @override
  State<DemoLabScreen> createState() => _DemoLabScreenState();
}

class _DemoLabScreenState extends State<DemoLabScreen> {
  late String _lang = widget.initialLang;
  List<Map<String, Object?>>? _scenarios;
  bool _loading = true, _modelReady = false, _gemma = true, _cold = false, _skip = false;
  String? _busyId; // '*' while Run all is going
  String? _current; // scenario being run right now
  final _results = <String, Map<String, Object?>>{};
  final _shown = <String, int>{};
  Timer? _timer;
  Completer<void>? _wake;

  /// Gemma only when the user wants it and the model is on the phone.
  bool get _useGemma => _gemma && _modelReady;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _skip = true;
    _timer?.cancel();
    final c = _wake;
    if (c != null && !c.isCompleted) c.complete();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await widget.api.scenarios();
    final ready = await widget.api.modelReady();
    if (!mounted) return;
    setState(() {
      _scenarios = list;
      _modelReady = ready;
      _gemma = ready;
      _loading = false;
    });
  }

  void _toast(String msg) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _wait(int ms) {
    final c = _wake = Completer<void>();
    _timer = Timer(Duration(milliseconds: ms > _maxDelayMs ? _maxDelayMs : ms), () {
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  void _skipAnimation() {
    setState(() => _skip = true);
    _timer?.cancel();
    final c = _wake;
    if (c != null && !c.isCompleted) c.complete();
  }

  Future<void> _runOne(String id) async {
    setState(() {
      _current = id;
      _results.remove(id);
      _shown.remove(id);
    });
    final r = await widget.api.run(id, gemma: _useGemma, coldStart: _cold);
    if (!mounted) return;
    if (r == null) {
      _toast(DemoStrings.of(_lang)['runErr']);
      return;
    }
    final steps = _ml(r['steps']);
    setState(() {
      _results[id] = r;
      _shown[id] = 0;
    });
    for (var i = 0; i < steps.length; i++) {
      final ms = (steps[i]['delayMs'] as num?)?.toInt() ?? 0;
      if (!_skip && ms > 0) await _wait(ms);
      if (!mounted) return;
      setState(() => _shown[id] = i + 1);
    }
  }

  Future<void> _start(List<String> ids, String busy) async {
    if (_busyId != null) return;
    setState(() {
      _busyId = busy;
      _skip = false;
    });
    for (final id in ids) {
      await _runOne(id);
      if (!mounted) return;
    }
    setState(() {
      _busyId = null;
      _current = null;
    });
  }

  Future<void> _reset() async {
    if (_busyId != null) return;
    final ok = await widget.api.reset();
    if (!mounted) return;
    setState(() {
      _results.clear();
      _shown.clear();
    });
    final s = DemoStrings.of(_lang);
    _toast(ok ? s['resetOk'] : s['resetErr']);
  }

  Widget _panel(ThemeData t, Widget child) => Container(
        padding: const EdgeInsets.all(Sp.l),
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: BorderRadius.circular(Rad.lg),
          border: Border.all(color: t.colorScheme.outline),
        ),
        child: child,
      );

  Widget _about(ThemeData t, DemoStrings s) => _panel(
        t,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['about'], style: t.textTheme.bodyLarge),
          if (_lang != 'en')
            Padding(
              padding: const EdgeInsets.only(top: Sp.s),
              child: Text(DemoStrings.en['about'], style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ),
          const SizedBox(height: Sp.m),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 24, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(width: Sp.s),
            Expanded(child: Text(s['demoNote'], style: t.textTheme.bodyMedium)),
          ]),
        ]),
      );

  Widget _controls(ThemeData t, DemoStrings s, List<Map<String, Object?>> list) {
    final busy = _busyId != null;
    // Transparent Material so the switch tiles paint their ink on it, not under the panel's DecoratedBox.
    return _panel(
      t,
      Material(
        type: MaterialType.transparency,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile(
          key: const Key('demo_engine'),
          contentPadding: EdgeInsets.zero,
          title: Text(s['gemmaOn']),
          subtitle: Text(!_modelReady
              ? s['noModel']
              : _useGemma
                  ? 'Gemma + नियम · Gemma + rules'
                  : 'सिर्फ़ नियम · Rules only'),
          value: _useGemma,
          onChanged: _modelReady && !busy ? (v) => setState(() => _gemma = v) : null,
        ),
        SwitchListTile(
          key: const Key('demo_cold'),
          contentPadding: EdgeInsets.zero,
          title: Text(s['cold']),
          subtitle: Text(s['coldSub']),
          value: _cold,
          onChanged: busy ? null : (v) => setState(() => _cold = v),
        ),
        const SizedBox(height: Sp.m),
        FilledButton.icon(
          key: const Key('demo_run_all'),
          onPressed: busy || list.isEmpty ? null : () => _start([for (final sc in list) _s(sc['id'])], '*'),
          icon: const Icon(Icons.play_circle),
          label: Text(s['runAll'], textAlign: TextAlign.center),
        ),
        const SizedBox(height: Sp.s),
        OutlinedButton.icon(
          key: const Key('demo_reset'),
          onPressed: busy ? null : _reset,
          icon: const Icon(Icons.restart_alt),
          label: Text(s['reset'], textAlign: TextAlign.center),
        ),
        ]),
      ),
    );
  }

  Widget _badge(ThemeData t, StatusColors st, bool pass, {Key? key}) {
    final l = pass ? RiskLabel.safe : RiskLabel.scam;
    final c = st.solid(l);
    return Container(
      key: key,
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: Sp.xs),
      decoration: ShapeDecoration(color: st.tintOver(l, t.colorScheme.surface), shape: const StadiumBorder()),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(pass ? Icons.check_circle : Icons.cancel, size: 20, color: c),
        const SizedBox(width: Sp.xs),
        Text(pass ? 'PASS' : 'FAIL', style: t.textTheme.labelMedium?.copyWith(color: c)),
      ]),
    );
  }

  Widget _chip(RiskLabel l) => StatusChip(label: l, text: '${_headline(l)} · ${l.title}');

  Widget _tag(ThemeData t, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: Sp.xs),
        decoration: ShapeDecoration(color: t.colorScheme.surfaceContainerHigh, shape: const StadiumBorder()),
        child: Text(text, style: t.textTheme.labelMedium),
      );

  Widget _box(ThemeData t, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Sp.m),
        decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(Rad.md)),
        child: child,
      );

  /// One row of the six-stage rail: numbered node, bilingual stage title, then the stage body.
  Widget _stage(ThemeData t, DemoStrings s, int n, List<Widget> body, {bool last = false}) {
    final cs = t.colorScheme;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 32,
          child: Column(children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cs.primary, width: 2)),
              child: Text('$n', textScaler: TextScaler.noScaling, style: t.textTheme.labelMedium?.copyWith(color: cs.primary)),
            ),
            if (!last) Expanded(child: Container(width: 2, color: cs.outline)),
          ]),
        ),
        const SizedBox(width: Sp.m),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : Sp.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(header: true, child: Text(s['st$n'], style: t.textTheme.titleSmall)),
              if (_lang != 'en') Text(DemoStrings.en['st$n'], style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: Sp.s),
              ...body,
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _alertCard(ThemeData t, DemoStrings s, Map<String, Object?> a) {
    final cs = t.colorScheme;
    final hasAction = _s(a['reportAction']).isNotEmpty;
    return Container(
      key: const Key('demo_alert_preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(Sp.m),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: cs.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.shield, size: 20, color: cs.primary),
          const SizedBox(width: Sp.s),
          Expanded(child: Text('ScamShield · ${s['now']}', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
        ]),
        const SizedBox(height: Sp.s),
        Text(_s(a['title']), style: t.textTheme.titleSmall),
        Text(_s(a['text']), style: t.textTheme.bodyMedium),
        if (hasAction) ...[
          const SizedBox(height: Sp.s),
          Row(key: const Key('demo_alert_report'), children: [
            Icon(Icons.flag, size: 20, color: cs.primary),
            const SizedBox(width: Sp.xs),
            Expanded(child: Text(s['reportAction'], style: t.textTheme.labelMedium?.copyWith(color: cs.primary))),
          ]),
        ],
      ]),
    );
  }

  Widget _step(ThemeData t, StatusColors st, DemoStrings s, Map<String, Object?> step, int n) {
    final cs = t.colorScheme;
    final muted = t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final pass = step['pass'] == true;
    final fused = _m(step['fused']);
    final fusedLabel = parseLabel(fused['label']);
    final gemma = step['gemma'] is Map ? _m(step['gemma']) : null;
    final alert = step['alert'] is Map ? _m(step['alert']) : null;
    final ctx = _sl(step['contextLines']);
    final rules = _sl(step['ruleTriggers']);
    final conf = (fused['confidence'] as num?)?.toDouble();
    final confText = conf == null ? null : '${(conf <= 1 ? conf * 100 : conf).round()}%';
    final raised = _sl(fused['raisedBy']);
    final fusedType = _s(fused['scamType']);
    final gemmaType = gemma == null ? '' : _s(gemma['scamType']);
    final gemmaReason = gemma == null ? '' : _s(gemma['reason']);
    final sender = _s(step['sender']);
    final expLabel = _s(step['expectedLabel']);
    final flagStyle = pass ? muted : muted?.copyWith(color: st.scam);
    return Column(
      key: Key('demo_step_$n'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: Sp.xl),
        Row(children: [
          Expanded(child: Text('${s['event']} $n', style: t.textTheme.titleMedium)),
          _badge(t, st, pass, key: Key('demo_step_badge_$n')),
        ]),
        const SizedBox(height: Sp.xs),
        Text('${s['expected']}: $expLabel · ${s['got']}: ${fusedLabel.title}', style: flagStyle),
        Text('${s['flagsExp']}: ${_join(_sl(step['expectedFlags']))}', style: flagStyle),
        Text('${s['flagsGot']}: ${_join(_sl(step['actualFlags']))}', style: flagStyle),
        const SizedBox(height: Sp.l),
        _stage(t, s, 1, [
          Wrap(spacing: Sp.s, runSpacing: Sp.xs, children: [
            _tag(t, _s(step['source'])),
            if (sender.isNotEmpty) _tag(t, sender),
          ]),
          const SizedBox(height: Sp.s),
          _box(t, Text(_s(step['text']), style: t.textTheme.bodyLarge)),
        ]),
        _stage(t, s, 2, [
          if (ctx.isEmpty)
            Text(s['noContext'], style: muted)
          else
            _box(t, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final line in ctx) Text(line, style: t.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')),
            ])),
        ]),
        _stage(t, s, 3, [
          if (rules.isEmpty)
            Text(s['noRules'], style: muted)
          else
            Wrap(spacing: Sp.s, runSpacing: Sp.xs, children: [for (final r in rules) _tag(t, r)]),
        ]),
        _stage(t, s, 4, [
          if (gemma == null)
            Text(s['rulesOnly'], style: muted)
          else ...[
            Align(alignment: Alignment.centerLeft, child: _chip(parseLabel(gemma['label']))),
            if (gemmaType.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Sp.xs), child: Text('${s['type']}: $gemmaType', style: t.textTheme.bodyMedium)),
            if (gemmaReason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Sp.xs), child: Text(gemmaReason, style: t.textTheme.bodyMedium)),
          ],
        ]),
        _stage(t, s, 5, [
          Align(alignment: Alignment.centerLeft, child: _chip(fusedLabel)),
          if (confText != null) Padding(padding: const EdgeInsets.only(top: Sp.xs), child: Text('${s['conf']}: $confText', style: t.textTheme.bodyMedium)),
          if (fusedType.isNotEmpty) Text('${s['type']}: $fusedType', style: t.textTheme.bodyMedium),
          if (raised.isNotEmpty) Text('${s['raisedBy']}: ${raised.join(', ')}', style: t.textTheme.bodyMedium),
        ]),
        _stage(t, s, 6, [
          if (alert == null) Text(s['noAlert'], style: muted) else _alertCard(t, s, alert),
        ], last: true),
      ],
    );
  }

  Widget _card(ThemeData t, StatusColors st, DemoStrings s, Map<String, Object?> sc) {
    final cs = t.colorScheme;
    final id = _s(sc['id']);
    final res = _results[id];
    final steps = res == null ? <Map<String, Object?>>[] : _ml(res['steps']);
    final shown = _shown[id] ?? 0;
    final done = res != null && shown >= steps.length;
    final passed = steps.where((e) => e['pass'] == true).length;
    final note = res == null ? '' : _s(res['note']);
    final busy = _busyId != null;
    return _panel(
      t,
      Column(key: Key('demo_card_$id'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(_icons[_s(sc['icon'])] ?? Icons.science, size: 32, color: cs.primary),
          const SizedBox(width: Sp.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_s(sc['titleHi']), style: t.textTheme.titleMedium),
              Text(_s(sc['titleEn']), style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ]),
        const SizedBox(height: Sp.s),
        Text(_lang == 'en' ? _s(sc['storyEn']) : _s(sc['storyHi']), style: t.textTheme.bodyMedium),
        const SizedBox(height: Sp.s),
        Wrap(spacing: Sp.m, runSpacing: Sp.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${(sc['steps'] as num?)?.toInt() ?? steps.length} ${s['steps']}', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          if (res != null && done) _badge(t, st, res['pass'] == true, key: Key('demo_badge_$id')),
          if (res != null && done) Text('$passed/${steps.length}', style: t.textTheme.labelMedium),
        ]),
        const SizedBox(height: Sp.m),
        FilledButton.icon(
          key: Key('demo_run_$id'),
          onPressed: busy ? null : () => _start([id], id),
          icon: Icon(_current == id ? Icons.hourglass_top : Icons.play_arrow),
          label: Text(_current == id ? s['running'] : s['run'], textAlign: TextAlign.center),
        ),
        if (res != null) ...[
          const SizedBox(height: Sp.m),
          Text('${s['engine']}: ${_s(res['engineUsed'])}', key: Key('demo_engine_used_$id'), style: t.textTheme.labelMedium),
          if (note.isNotEmpty) Text('${s['note']}: $note', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          for (var i = 0; i < steps.length && i < shown; i++) _step(t, st, s, steps[i], i + 1),
          if (!done)
            Padding(
              padding: const EdgeInsets.only(top: Sp.m),
              child: Text(s['next'], style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = DemoStrings.of(_lang);
    final t = Theme.of(context);
    final st = t.extension<StatusColors>() ?? StatusColors.light;
    final list = _scenarios;
    if (_loading) return Center(child: StateMessage(loading: true, title: s['loading']));
    if (list == null) {
      return Center(
        child: StateMessage(
          icon: Icons.science_outlined,
          title: s['unavailable'],
          subtitle: s['unavailableSub'],
          actionLabel: s['retry'],
          onAction: _load,
        ),
      );
    }
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Sp.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
            SectionHeader(title: s['title'], icon: Icons.science, subtitle: 'Demo Lab'),
            _about(t, s),
            const SizedBox(height: Sp.l),
            _controls(t, s, list),
            for (final sc in list) ...[
              const SizedBox(height: Sp.l),
              _card(t, st, s, sc),
            ],
          ]),
        ),
      ),
      // Pinned so it stays one tap away however far the timeline has scrolled.
      if (_busyId != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.l),
          child: OutlinedButton.icon(
            key: const Key('demo_skip'),
            onPressed: _skipAnimation,
            icon: const Icon(Icons.skip_next),
            label: Text(s['skip'], textAlign: TextAlign.center),
          ),
        ),
    ]);
  }
}
