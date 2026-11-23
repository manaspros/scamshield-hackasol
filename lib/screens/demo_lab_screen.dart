import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/verdict.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/press_scale.dart';
import '../widgets/section_header.dart';
import '../widgets/stat_tile.dart';
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
    'resetAsk': 'डेमो रीसेट करें?',
    'resetBody': 'डेमो का सारा डेटा और अब तक के नतीजे हट जाएँगे।',
    'cancel': 'रहने दें',
    'skip': 'एनीमेशन छोड़ें',
    'run': 'चलाएँ',
    'running': 'चल रहा है…',
    'progress': 'चल रहे हैं',
    'passed': 'सफल',
    'failed': 'विफल',
    'avg': 'औसत समय',
    'more': 'और देखें',
    'less': 'कम दिखाएँ',
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
    'alertYes': 'अलर्ट भेजा गया',
    'expected': 'अपेक्षित',
    'got': 'मिला',
    'flagsExp': 'अपेक्षित संकेत',
    'flagsGot': 'मिले संकेत',
    'engine': 'इंजन',
    'engineGemma': 'Gemma + नियम',
    'engineRules': 'सिर्फ़ नियम',
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
    'emptyTitle': 'अभी कोई डेमो नहीं है',
    'emptySub': 'इस ऐप में डेमो कहानियाँ नहीं मिलीं',
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
    'resetAsk': 'डेमो रीसेट करव?',
    'resetBody': 'डेमो के जम्मो डेटा अउ अब तक के नतीजा हट जाही।',
    'cancel': 'रहन देव',
    'skip': 'एनीमेशन छोड़व',
    'run': 'चलावव',
    'running': 'चलत हे…',
    'progress': 'चलत हें',
    'passed': 'सफल',
    'failed': 'असफल',
    'avg': 'औसत समय',
    'more': 'अउ देखव',
    'less': 'कम देखव',
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
    'alertYes': 'अलर्ट भेजे गिस',
    'expected': 'अपेक्षित',
    'got': 'मिलिस',
    'flagsExp': 'अपेक्षित संकेत',
    'flagsGot': 'मिले संकेत',
    'engine': 'इंजन',
    'engineGemma': 'Gemma + नियम',
    'engineRules': 'सिरिफ नियम',
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
    'emptyTitle': 'अभी कोनो डेमो नइ हे',
    'emptySub': 'ये ऐप म डेमो कहिनी नइ मिलिस',
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
    'resetAsk': 'Reset the demo?',
    'resetBody': 'All demo data and the results so far will be cleared.',
    'cancel': 'Keep it',
    'skip': 'Skip animation',
    'run': 'Run',
    'running': 'Running…',
    'progress': 'running',
    'passed': 'Passed',
    'failed': 'Failed',
    'avg': 'Average time',
    'more': 'See more',
    'less': 'Show less',
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
    'alertYes': 'Alert shown',
    'expected': 'Expected',
    'got': 'Got',
    'flagsExp': 'Expected flags',
    'flagsGot': 'Actual flags',
    'engine': 'Engine',
    'engineGemma': 'Gemma + rules',
    'engineRules': 'Rules only',
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
    'emptyTitle': 'No demos yet',
    'emptySub': 'No demo stories were found in this build',
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

/// Widest the content grows on a tablet or a mirrored screen.
const _maxWidth = 720.0;

String _headline(RiskLabel l) => switch (l) {
      RiskLabel.safe => 'सुरक्षित',
      RiskLabel.suspicious => 'सावधान',
      RiskLabel.scam => 'धोखाधड़ी!',
    };

String _join(List<String> l) => l.isEmpty ? '—' : l.join(', ');

/// Script time of an event as "+2.5 s".
String _offset(int ms) => '+${(ms / 1000).toStringAsFixed(ms % 1000 == 0 ? 0 : 1)} s';

/// Monospace block that shows its first lines and opens on "और देखें". Only long content gets the toggle.
class _MonoBox extends StatefulWidget {
  const _MonoBox({required this.lines, required this.more, required this.less, this.peek = 2});
  final List<String> lines;
  final String more, less;
  final int peek;

  @override
  State<_MonoBox> createState() => _MonoBoxState();
}

class _MonoBoxState extends State<_MonoBox> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final style = t.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', color: t.colorScheme.onSurface);
    final long = widget.lines.length > widget.peek || widget.lines.any((l) => l.length > 90);
    final shown = _open ? widget.lines : widget.lines.take(widget.peek).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(Sp.m),
        decoration: BoxDecoration(
          color: t.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Rad.md),
          border: Border.all(color: t.colorScheme.outline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final l in shown) Text(l, style: style, maxLines: _open ? null : 2, overflow: _open ? null : TextOverflow.ellipsis),
        ]),
      ),
      if (long)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
            label: Text(_open ? widget.less : widget.more),
          ),
        ),
    ]);
  }
}

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
  int _runTotal = 0, _runDone = 0;
  final _results = <String, Map<String, Object?>>{};
  final _shown = <String, int>{};
  final _open = <String>{}; // cards whose timeline is expanded
  final _cardKeys = <String, GlobalKey>{};
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
      _open
        ..clear()
        ..add(id);
    });
    if (_runTotal > 1) {
      // Run all: bring the card that is running to the top so a long list never hides it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _cardKeys[id]?.currentContext;
        if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, duration: Duration.zero);
      });
    }
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
      _runTotal = ids.length;
      _runDone = 0;
    });
    for (final id in ids) {
      await _runOne(id);
      if (!mounted) return;
      setState(() => _runDone++);
    }
    setState(() {
      _busyId = null;
      _current = null;
      // After a batch, open only the scenarios that failed, so the one to look at is on screen.
      if (ids.length > 1) {
        _open
          ..clear()
          ..addAll(ids.where((i) => _results[i] != null && _results[i]!['pass'] != true));
      }
    });
  }

  Future<void> _reset() async {
    if (_busyId != null) return;
    final s = DemoStrings.of(_lang);
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s['resetAsk']),
        content: Text(s['resetBody']),
        actions: [
          TextButton(key: const Key('demo_reset_cancel'), onPressed: () => Navigator.pop(c, false), child: Text(s['cancel'])),
          FilledButton(key: const Key('demo_reset_confirm'), onPressed: () => Navigator.pop(c, true), child: Text(s['reset'])),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final ok = await widget.api.reset();
    if (!mounted) return;
    setState(() {
      _results.clear();
      _shown.clear();
      _open.clear();
    });
    _toast(ok ? s['resetOk'] : s['resetErr']);
  }

  /// Hindi first, English after a slash, so a judge who cannot read Hindi still knows the action.
  String _bi(DemoStrings s, String k) => _lang == 'en' ? s[k] : '${s[k]} / ${DemoStrings.en[k]}';

  String _engineName(DemoStrings s, String used) => used.toLowerCase().contains('gemma') ? s['engineGemma'] : s['engineRules'];

  Widget _panel(ThemeData t, Widget child, {Key? key}) => Container(
        key: key,
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

  Widget _controls(ThemeData t, DemoStrings s) {
    final busy = _busyId != null;
    // Transparent Material so the switch tiles paint their ink on it, not under the panel's DecoratedBox.
    return _panel(
      t,
      Material(
        type: MaterialType.transparency,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.tune, size: 24, color: t.colorScheme.primary),
            const SizedBox(width: Sp.s),
            Expanded(child: Text(_bi(s, 'engine'), style: t.textTheme.titleMedium)),
          ]),
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
        ]),
      ),
    );
  }

  /// Passed / failed / average time over every scenario that has finished.
  Widget _summary(ThemeData t, DemoStrings s) {
    final done = [
      for (final e in _results.entries)
        if ((_shown[e.key] ?? 0) >= _ml(e.value['steps']).length) e.value
    ];
    final passed = done.where((r) => r['pass'] == true).length;
    final lat = [
      for (final r in done)
        for (final st in _ml(r['steps']))
          if (st['latencyMs'] is num) (st['latencyMs'] as num).toDouble()
    ];
    final tiles = <Widget>[
      StatTile(key: const Key('demo_sum_pass'), valueKey: const Key('demo_sum_pass_value'), icon: Icons.check_circle, value: '$passed', caption: _bi(s, 'passed')),
      StatTile(key: const Key('demo_sum_fail'), valueKey: const Key('demo_sum_fail_value'), icon: Icons.cancel, value: '${done.length - passed}', caption: _bi(s, 'failed')),
      if (lat.isNotEmpty)
        StatTile(
            key: const Key('demo_sum_avg'),
            valueKey: const Key('demo_sum_avg_value'),
            icon: Icons.timer,
            value: '${(lat.reduce((a, b) => a + b) / lat.length).round()} ms',
            caption: _bi(s, 'avg')),
    ];
    return LayoutBuilder(builder: (c, box) {
      // Two to a row on a phone (a third wraps full width), all in one row on a wide screen.
      final cols = box.maxWidth >= 560 ? tiles.length : 2;
      final w = (box.maxWidth - Sp.m * (cols - 1)) / cols;
      return Wrap(spacing: Sp.m, runSpacing: Sp.m, children: [
        for (final (i, tile) in tiles.indexed) SizedBox(width: cols == 2 && i == tiles.length - 1 && tiles.length.isOdd ? box.maxWidth : w, child: tile),
      ]);
    });
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

  /// One row of the six-stage rail: icon dot on a thin line, bilingual stage title, then the stage body.
  Widget _stage(ThemeData t, DemoStrings s, int n, IconData icon, List<Widget> body, {bool last = false, Color? tone}) {
    final cs = t.colorScheme;
    final c = tone ?? cs.primary;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 32,
          child: Column(children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surface, border: Border.all(color: c, width: 2)),
              child: Icon(icon, size: 18, color: c),
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

  Widget _step(ThemeData t, StatusColors st, DemoStrings s, Map<String, Object?> step, int n, int offsetMs, String engineUsed) {
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
    final source = _s(step['source']);
    final expLabel = _s(step['expectedLabel']);
    final flagStyle = pass ? muted : muted?.copyWith(color: st.scam);
    final srcIcon = switch (source) {
      'call' => Icons.call,
      'notification' => Icons.notifications,
      _ => Icons.sms,
    };
    return Column(
      key: Key('demo_step_$n'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: Sp.xl),
        Row(children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${s['event']} $n'),
              TextSpan(text: '  ${_offset(offsetMs)}', style: muted),
            ]), style: t.textTheme.titleMedium),
          ),
          const SizedBox(width: Sp.s),
          _badge(t, st, pass, key: Key('demo_step_badge_$n')),
        ]),
        const SizedBox(height: Sp.xs),
        Text('${s['expected']}: $expLabel · ${s['got']}: ${fusedLabel.title}', style: flagStyle),
        Text('${s['flagsExp']}: ${_join(_sl(step['expectedFlags']))}', style: flagStyle),
        Text('${s['flagsGot']}: ${_join(_sl(step['actualFlags']))}', style: flagStyle),
        const SizedBox(height: Sp.l),
        _stage(t, s, 1, srcIcon, [
          Wrap(spacing: Sp.s, runSpacing: Sp.xs, children: [
            if (source.isNotEmpty) _tag(t, source),
            if (sender.isNotEmpty) _tag(t, sender),
          ]),
          const SizedBox(height: Sp.s),
          _box(t, Text(_s(step['text']), style: t.textTheme.bodyLarge)),
        ]),
        _stage(t, s, 2, Icons.account_tree, [
          if (ctx.isEmpty) Text(s['noContext'], style: muted) else _MonoBox(lines: ctx, more: _bi(s, 'more'), less: _bi(s, 'less')),
        ]),
        _stage(t, s, 3, Icons.rule, [
          if (rules.isEmpty)
            Text(s['noRules'], style: muted)
          else
            Wrap(spacing: Sp.s, runSpacing: Sp.xs, children: [for (final r in rules) _tag(t, r)]),
        ]),
        _stage(t, s, 4, Icons.psychology, [
          if (gemma == null)
            Text(s['rulesOnly'], style: muted)
          else ...[
            Align(alignment: Alignment.centerLeft, child: _chip(parseLabel(gemma['label']))),
            const SizedBox(height: Sp.s),
            _MonoBox(
              lines: [
                'label: ${parseLabel(gemma['label']).title}',
                if (gemmaType.isNotEmpty) 'type: $gemmaType',
                if (gemmaReason.isNotEmpty) 'reason: $gemmaReason',
              ],
              more: _bi(s, 'more'),
              less: _bi(s, 'less'),
              peek: 3,
            ),
          ],
        ]),
        _stage(t, s, 5, Icons.gavel, tone: st.solid(fusedLabel), [
          Align(alignment: Alignment.centerLeft, child: _chip(fusedLabel)),
          const SizedBox(height: Sp.xs),
          Text('${s['engine']}: ${_engineName(s, engineUsed)}', style: t.textTheme.bodyMedium),
          if (confText != null) Text('${s['conf']}: $confText', style: t.textTheme.bodyMedium),
          if (fusedType.isNotEmpty) Text('${s['type']}: $fusedType', style: t.textTheme.bodyMedium),
          if (raised.isNotEmpty) Text('${s['raisedBy']}: ${raised.join(', ')}', style: t.textTheme.bodyMedium),
        ]),
        _stage(t, s, 6, alert == null ? Icons.notifications_off : Icons.notifications_active, [
          if (alert == null)
            Text(s['noAlert'], style: muted)
          else ...[
            Text(fusedType.isEmpty ? s['alertYes'] : '${s['alertYes']} · $fusedType', style: t.textTheme.bodyMedium),
            const SizedBox(height: Sp.s),
            _alertCard(t, s, alert),
          ],
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
    final open = res != null && _open.contains(id);
    // The scenario can state its expected verdict; otherwise take the most severe step expectation of the last run.
    final expected = sc['expectedLabel'] != null
        ? parseLabel(sc['expectedLabel'])
        : steps.isEmpty
            ? null
            : steps.map((e) => parseLabel(e['expectedLabel'])).reduce((a, b) => a.index >= b.index ? a : b);
    var offset = 0;
    final offsets = [for (final e in steps) offset += (e['delayMs'] as num?)?.toInt() ?? 0];
    final engineUsed = res == null ? '' : _s(res['engineUsed']);
    final header = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surfaceContainerHigh),
        child: Icon(_icons[_s(sc['icon'])] ?? Icons.science, size: 28, color: cs.primary),
      ),
      const SizedBox(width: Sp.m),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_s(sc['titleHi']), style: t.textTheme.titleMedium),
          Text(_s(sc['titleEn']), style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
      if (res != null) Padding(padding: const EdgeInsets.only(left: Sp.s), child: Icon(open ? Icons.expand_less : Icons.expand_more, size: 28, color: cs.onSurfaceVariant)),
    ]);
    return _panel(
      t,
      key: _cardKeys.putIfAbsent(id, GlobalKey.new),
      Column(key: Key('demo_card_$id'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (res == null)
          header
        else
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              key: Key('demo_toggle_$id'),
              borderRadius: BorderRadius.circular(Rad.md),
              onTap: () => setState(() => open ? _open.remove(id) : _open.add(id)),
              child: ConstrainedBox(constraints: const BoxConstraints(minHeight: kTouch), child: header),
            ),
          ),
        const SizedBox(height: Sp.s),
        Text(_lang == 'en' ? _s(sc['storyEn']) : _s(sc['storyHi']), style: t.textTheme.bodyMedium),
        const SizedBox(height: Sp.s),
        Wrap(spacing: Sp.m, runSpacing: Sp.s, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (expected != null) StatusChip(key: Key('demo_expected_$id'), label: expected, text: '${s['expected']}: ${_headline(expected)}'),
          if (res != null && done) _badge(t, st, res['pass'] == true, key: Key('demo_badge_$id')),
          if (res != null && done) Text('$passed/${steps.length}', style: t.textTheme.labelMedium),
          Text('${(sc['steps'] as num?)?.toInt() ?? steps.length} ${s['steps']}', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
        const SizedBox(height: Sp.m),
        OutlinedButton.icon(
          key: Key('demo_run_$id'),
          onPressed: busy ? null : () => _start([id], id),
          icon: Icon(_current == id ? Icons.hourglass_top : Icons.play_arrow),
          label: Text(_current == id ? _bi(s, 'running') : _bi(s, 'run'), textAlign: TextAlign.center),
        ),
        if (res != null) ...[
          const SizedBox(height: Sp.m),
          Row(children: [
            Icon(engineUsed.toLowerCase().contains('gemma') ? Icons.psychology : Icons.rule, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: Sp.s),
            Expanded(child: Text('${s['engine']}: ${_engineName(s, engineUsed)}', key: Key('demo_engine_used_$id'), style: t.textTheme.labelMedium)),
          ]),
          if (note.isNotEmpty) Text('${s['note']}: $note', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          if (open) ...[
            for (var i = 0; i < steps.length && i < shown; i++) _step(t, st, s, steps[i], i + 1, offsets[i], engineUsed),
            if (!done)
              Padding(
                padding: const EdgeInsets.only(top: Sp.m),
                child: Text(s['next'], style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
          ],
        ],
      ]),
    );
  }

  /// Run all pill, with a progress line and Skip while a run is going. Pinned under the list.
  Widget _bottomBar(ThemeData t, DemoStrings s, List<Map<String, Object?>> list) {
    final busy = _busyId != null;
    final n = _runDone + 1 > _runTotal ? _runTotal : _runDone + 1;
    return DecoratedBox(
      decoration: BoxDecoration(color: t.colorScheme.surface, border: Border(top: BorderSide(color: t.colorScheme.outline))),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Sp.l, Sp.m, Sp.l, Sp.m),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (busy) ...[
                Semantics(
                  liveRegion: true,
                  child: Text('$n / $_runTotal ${s['progress']}', key: const Key('demo_progress'), style: t.textTheme.labelMedium),
                ),
                const SizedBox(height: Sp.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Rad.pill),
                  child: LinearProgressIndicator(value: _runTotal == 0 ? null : _runDone / _runTotal, minHeight: 6),
                ),
                const SizedBox(height: Sp.m),
              ],
              PressScale(
                enabled: !busy && list.isNotEmpty,
                child: FilledButton.icon(
                  key: const Key('demo_run_all'),
                  onPressed: busy || list.isEmpty ? null : () => _start([for (final sc in list) _s(sc['id'])], '*'),
                  icon: const Icon(Icons.play_circle),
                  label: Text(_bi(s, 'runAll'), textAlign: TextAlign.center),
                ),
              ),
              if (busy)
                TextButton.icon(
                  key: const Key('demo_skip'),
                  onPressed: _skipAnimation,
                  icon: const Icon(Icons.skip_next),
                  label: Text(s['skip'], textAlign: TextAlign.center),
                ),
            ]),
          ),
        ),
      ),
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
    if (list.isEmpty) {
      return Center(child: StateMessage(icon: Icons.science_outlined, title: s['emptyTitle'], subtitle: s['emptySub']));
    }
    final anyDone = _results.entries.any((e) => (_shown[e.key] ?? 0) >= _ml(e.value['steps']).length);
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Sp.l),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
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
                _controls(t, s),
                if (anyDone && _busyId == null) ...[
                  const SizedBox(height: Sp.l),
                  _summary(t, s),
                ],
                for (final sc in list) ...[
                  const SizedBox(height: Sp.l),
                  _card(t, st, s, sc),
                ],
                const SizedBox(height: Sp.l),
                TextButton.icon(
                  key: const Key('demo_reset'),
                  onPressed: _busyId != null ? null : _reset,
                  icon: const Icon(Icons.restart_alt),
                  label: Text(_bi(s, 'reset'), textAlign: TextAlign.center),
                ),
              ]),
            ),
          ),
        ),
      ),
      _bottomBar(t, s, list),
    ]);
  }
}
