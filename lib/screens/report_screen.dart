import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_language.dart';
import '../models/verdict.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/action_tile.dart';
import '../widgets/section_header.dart';
import '../widgets/state_message.dart';

/// Client for the native handoff channel (K/HandoffChannel.kt).
/// Every call returns null/false instead of throwing, so the screen still works
/// (1930 button included) when the native side is missing or fails.
class HandoffApi {
  const HandoffApi([this.channel = const MethodChannel('scamshield/handoff')]);
  final MethodChannel channel;

  Future<Map<Object?, Object?>?> _map(String m, [Object? args]) async {
    try {
      return await channel.invokeMapMethod<Object?, Object?>(m, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> _ok(String m, Map<String, Object?> args) async {
    try {
      return await channel.invokeMethod<bool>(m, args) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<Map<Object?, Object?>?> pack({required bool moneyLost}) => _map('report.pack', {'moneyLost': moneyLost});
  Future<Map<Object?, Object?>?> goldenStatus() => _map('golden.status');
  Future<Map<Object?, Object?>?> goldenStart({bool restart = false}) => _map('golden.start', {'restart': restart});
  Future<bool> goldenShare(Map<String, String> fields) => _ok('golden.share', {'fields': fields});
  Future<bool> dial(String number) => _ok('dial', {'number': number});
  Future<bool> open(String url) => _ok('open', {'url': url});
}

const _hiLabels = <String, String>{
  't_OTP': 'OTP',
  't_KYC': 'KYC',
  't_DIGITAL_ARREST': 'डिजिटल अरेस्ट',
  't_COURIER_CUSTOMS': 'कूरियर / कस्टम',
  't_FAKE_QR': 'नकली QR',
  't_LOAN_APP': 'लोन ऐप',
  't_INVESTMENT': 'निवेश',
  't_JOB': 'नौकरी',
  't_MISTAKEN_TRANSFER': 'गलत ट्रांसफ़र',
  't_OTHER': 'अन्य',
  's_caption': 'फ़ोन कॉल',
  's_sms': 'SMS',
  's_whatsapp': 'WhatsApp',
  's_paste': 'चिपकाया संदेश',
  's_share': 'शेयर किया संदेश',
  's_notification': 'नोटिफ़िकेशन',
  's_recording': 'रिकॉर्डिंग',
  's_signal': 'संकेत',
};

/// Screen text in Hindi (default), Chhattisgarhi and English; same keys in all three.
class ReportStrings {
  const ReportStrings(this.m);
  final Map<String, String> m;
  String operator [](String k) => m[k] ?? k;

  static const hi = ReportStrings({
    ..._hiLabels,
    'title': 'शिकायत दर्ज करें',
    'pathLost': 'मेरे पैसे कट गए',
    'pathLostSub': 'अभी 1930 पर कॉल करें',
    'pathNot': 'अभी पैसे नहीं गए',
    'pathNotSub': 'ठग के नंबर की शिकायत करें',
    'start': 'मैं ठगा गया: 60 मिनट शुरू करें',
    'startSub': 'पहले घंटे में बताने पर बैंक पैसे रोक सकता है।',
    'goldenTitle': 'सुनहरा घंटा',
    'goldenHint': 'पहले घंटे में शिकायत करने से पैसा वापस मिलने की संभावना सबसे ज़्यादा',
    'expired': 'समय पूरा हुआ। फिर भी 1930 पर कॉल करें।',
    'restart': 'नया मामला शुरू करें',
    'calm': 'घबराएँ नहीं। ये कदम अभी उठाएँ।',
    'loading': 'तैयार हो रहा है…',
    'dialCta': '1930 पर कॉल करें',
    'step1': 'सबसे पहले 1930 पर कॉल करें',
    'stepPortal': 'cybercrime.gov.in पर शिकायत दर्ज करें',
    'stepChakshu': 'चक्षु पर शक वाला नंबर बताएँ',
    'stepShots': 'स्क्रीनशॉट सँभालकर रखें',
    'dialHint': 'डायल खुलेगा। हरा बटन आप खुद दबाएँ।',
    'portal': 'साइबर क्राइम पोर्टल खोलें',
    'chakshu': 'चक्षु: शक वाला नंबर बताएँ',
    'evidence': 'सबूत की सूची',
    'evidenceAuto': 'ऐप ने ये अपने आप जोड़े हैं।',
    'evidenceNone': 'कोई चेतावनी नहीं मिली। नीचे खुद लिखें।',
    'yours': 'आप खुद भरें',
    'f_scammer_number': 'ठग का फ़ोन नंबर या UPI ID',
    'f_amount': 'कितने रुपये गए',
    'more': 'अधिक जानकारी',
    'f_utr': 'बैंक मैसेज वाला लेन-देन नंबर',
    'f_screenshots': 'स्क्रीनशॉट के बारे में लिखें (चाहें तो)',
    'share': 'सबूत की फ़ाइल बनाकर भेजें',
    'openErr': 'यह नहीं खुल सका। 1930 खुद डायल करें।',
    'shareErr': 'सबूत नहीं बन सका। फिर कोशिश करें।',
    'startErr': 'घड़ी शुरू नहीं हो सकी। 1930 पर कॉल करें।',
    'minLeft': '{n} मिनट बाकी',
  });

  static const hne = ReportStrings({
    ..._hiLabels,
    'title': 'शिकायत दर्ज करव',
    'pathLost': 'मोर पइसा कट गे',
    'pathLostSub': 'अभी 1930 म फोन करव',
    'pathNot': 'अभी पइसा नइ गे हे',
    'pathNotSub': 'ठग के नंबर के शिकायत करव',
    'start': 'मंय ठगाय गेंव: 60 मिनट सुरू करव',
    'startSub': 'पहिली घंटा म बताहू त बैंक पइसा रोक सकथे।',
    'goldenTitle': 'सोना कस घंटा',
    'goldenHint': 'पहिली घंटा म शिकायत करे ले पइसा लहुटे के संभावना सबले जादा',
    'expired': 'समे पूरा होगे। तभो ले 1930 म फोन करव।',
    'restart': 'नवा मामला सुरू करव',
    'calm': 'घबरावव झन। ए कदम अभी उठावव।',
    'loading': 'तियार होवत हे…',
    'dialCta': '1930 म फोन करव',
    'step1': 'सबले पहिली 1930 म फोन करव',
    'stepPortal': 'cybercrime.gov.in म शिकायत दर्ज करव',
    'stepChakshu': 'चक्षु म शक वाले नंबर बतावव',
    'stepShots': 'स्क्रीनशॉट सम्हाल के राखव',
    'dialHint': 'डायल खुलही। हरियर बटन तुमन खुद दबावव।',
    'portal': 'साइबर क्राइम पोर्टल खोलव',
    'chakshu': 'चक्षु: शक वाले नंबर बतावव',
    'evidence': 'सबूत के सूची',
    'evidenceAuto': 'ऐप ह ए मन ल अपने जोड़े हे।',
    'evidenceNone': 'कोनो चेतावनी नइ मिलिस। तल म खुद लिखव।',
    'yours': 'तुमन खुद भरव',
    'f_scammer_number': 'ठग के फोन नंबर या UPI ID',
    'f_amount': 'कतका रुपिया गे',
    'more': 'अउ जानकारी',
    'f_utr': 'बैंक मैसेज वाले लेन-देन नंबर',
    'f_screenshots': 'स्क्रीनशॉट के बारे म लिखव (मन होवय त)',
    'share': 'सबूत के फाइल बनाके भेजव',
    'openErr': 'ए नइ खुल सकिस। 1930 खुद डायल करव।',
    'shareErr': 'सबूत नइ बन सकिस। फेर कोसिस करव।',
    'startErr': 'घड़ी सुरू नइ हो सकिस। 1930 म फोन करव।',
    'minLeft': '{n} मिनट बाकी',
  });

  static const en = ReportStrings({
    't_OTP': 'OTP',
    't_KYC': 'KYC',
    't_DIGITAL_ARREST': 'Digital arrest',
    't_COURIER_CUSTOMS': 'Courier / customs',
    't_FAKE_QR': 'Fake QR',
    't_LOAN_APP': 'Loan app',
    't_INVESTMENT': 'Investment',
    't_JOB': 'Job offer',
    't_MISTAKEN_TRANSFER': 'Mistaken transfer',
    't_OTHER': 'Other',
    's_caption': 'Phone call',
    's_sms': 'SMS',
    's_whatsapp': 'WhatsApp',
    's_paste': 'Pasted message',
    's_share': 'Shared message',
    's_notification': 'Notification',
    's_recording': 'Recording',
    's_signal': 'Signal',
    'title': 'Report a scam',
    'pathLost': 'I lost money',
    'pathLostSub': 'Call 1930 now',
    'pathNot': 'No money lost yet',
    'pathNotSub': 'Report the scammer\'s number',
    'start': 'I got scammed: start 60 minutes',
    'startSub': 'Report in the first hour and the bank may be able to freeze the money.',
    'goldenTitle': 'Golden hour',
    'goldenHint': 'Reporting in the first hour gives the best chance of getting your money back.',
    'expired': 'Time is up. Still call 1930.',
    'restart': 'Start a new case',
    'calm': 'Don\'t panic. Take these steps now.',
    'loading': 'Getting ready…',
    'dialCta': 'Call 1930',
    'step1': 'Call 1930 first',
    'stepPortal': 'Report at cybercrime.gov.in',
    'stepChakshu': 'Report the suspect number on Chakshu',
    'stepShots': 'Keep your screenshots',
    'dialHint': 'The dialer opens. You press the green button.',
    'portal': 'Open the cybercrime portal',
    'chakshu': 'Chakshu: report the suspect number',
    'evidence': 'Evidence checklist',
    'evidenceAuto': 'The app added these for you.',
    'evidenceNone': 'No warnings found. Write the details below.',
    'yours': 'You fill in',
    'f_scammer_number': 'Scammer phone number or UPI ID',
    'f_amount': 'Amount lost (INR)',
    'more': 'More details',
    'f_utr': 'Transaction number from the bank message',
    'f_screenshots': 'Notes about your screenshots (optional)',
    'share': 'Make and send evidence file',
    'openErr': 'Could not open this. Dial 1930 yourself.',
    'shareErr': 'Could not build the evidence file. Try again.',
    'startErr': 'Could not start the clock. Call 1930.',
    'minLeft': '{n} minutes left',
  });

  static const all = {'hi': hi, 'hne': hne, 'en': en};
  static ReportStrings of(String lang) => all[lang] ?? hi;
}

const _fieldKeys = ['scammer_number', 'amount', 'utr', 'screenshots'];
const _lostOnlyFields = {'amount', 'utr'};
const _goldenMs = 60 * 60 * 1000;

class _Pack {
  _Pack(this.m);
  // Shown when native cannot build a pack: the helpline must always be one tap away.
  factory _Pack.fallback() => _Pack({
        'targets': [
          {'phone': '1930'}
        ],
      });
  final Map<Object?, Object?> m;
  List<Map<Object?, Object?>> _list(String k) =>
      ((m[k] as List?) ?? const []).map((e) => (e as Map).cast<Object?, Object?>()).toList();
  late final targets = _list('targets');
  late final evidence = _list('evidence');
}

/// Report screen. Path 1 "I lost money" (1930 + portal, golden-hour clock, evidence ZIP);
/// path 2 "no money lost yet" (Chakshu + 1930). Constructible standalone; T3.11 wires navigation.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, this.initialLang, this.api = const HandoffApi()});
  final String? initialLang; // null: follow the app-wide language
  final HandoffApi api;
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  // The language chips are a TEMPORARY per-view override: _lang starts from the app-wide language
  // (an explicit initialLang wins for the first read) and re-syncs whenever the global value changes.
  late String _lang = widget.initialLang ?? AppLanguage.code;
  String? _lastGlobal;
  final _detailKey = GlobalKey();
  bool? _lost; // null until the user picks a path
  _Pack? _pack;
  bool _loading = false;
  int? _remainingMs; // non-null once the golden hour has started
  Timer? _timer;
  final _ctrl = {for (final k in _fieldKeys) k: TextEditingController()};

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final g = AppLanguage.of(context);
    if (_lastGlobal == null) {
      if (widget.initialLang == null) _lang = g;
    } else if (g != _lastGlobal) {
      _lang = g;
    }
    _lastGlobal = g;
  }

  // Bring the chosen path's detail into view; the tiles alone show no change above the fold.
  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _detailKey.currentContext;
        if (mounted && c != null) {
          Scrollable.ensureVisible(c, alignment: 0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // The start time lives natively, so a rebuilt screen picks the clock up again.
  Future<void> _restore() async {
    final g = await widget.api.goldenStatus();
    if (!mounted || g == null || g['started'] != true) return;
    _applyGolden(g);
  }

  void _applyGolden(Map<Object?, Object?> g) {
    final left = (g['remainingMs'] as num).toInt();
    setState(() {
      _lost = true;
      _pack = _Pack((g['pack'] as Map).cast<Object?, Object?>());
      _remainingMs = left;
    });
    _timer?.cancel();
    // shortcut: counts down by ticks, not wall clock; resyncs from native on the next rebuild.
    if (left > 0) _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  void _tick(Timer t) {
    final left = (_remainingMs! - 1000).clamp(0, _goldenMs).toInt();
    setState(() => _remainingMs = left);
    if (left == 0) t.cancel();
  }

  Future<void> _choose(bool lost) async {
    setState(() {
      _lost = lost;
      _pack = null;
      _loading = true;
    });
    final m = await widget.api.pack(moneyLost: lost);
    if (!mounted || _lost != lost) return;
    setState(() {
      _pack = m == null ? _Pack.fallback() : _Pack(m);
      _loading = false;
    });
    _reveal();
  }

  Future<void> _startGolden() async {
    final g = await widget.api.goldenStart(restart: _remainingMs == 0);
    if (!mounted) return;
    if (g == null || g['started'] != true) {
      _toast(ReportStrings.of(_lang)['startErr']);
    } else {
      _applyGolden(g);
    }
  }

  Future<void> _run(Future<bool> call, String errKey) async {
    final ok = await call;
    if (mounted && !ok) _toast(ReportStrings.of(_lang)[errKey]);
  }

  void _toast(String msg) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));

  String _clock(int ms) =>
      '${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = ReportStrings.of(_lang);
    final t = Theme.of(context);
    // 1930 stays pinned under the scroll area so it is one tap away at any text size.
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Sp.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              if (_lost == true && _remainingMs != null) _golden(t, s),
              SectionHeader(title: s['title'], icon: Icons.report_problem, subtitle: s['calm']),
              _path(const Key('path_lost'), true, Icons.currency_rupee, s['pathLost'], s['pathLostSub']),
              const SizedBox(height: Sp.m),
              _path(const Key('path_notyet'), false, Icons.shield, s['pathNot'], s['pathNotSub']),
              Column(key: _detailKey, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_loading)
                  StateMessage(loading: true, title: s['loading'])
                else if (_pack != null) ..._detail(t, s, _pack!),
              ]),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.l),
        child: FilledButton.icon(
          key: Key('btn_dial_$_phone'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
          onPressed: () => _run(widget.api.dial(_phone), 'openErr'),
          icon: const Icon(Icons.phone, size: 28),
          label: Text(s['dialCta'], textAlign: TextAlign.center),
        ),
      ),
    ]);
  }

  // The helpline comes from the pack; 1930 is the fallback so the button works before a path is chosen.
  String get _phone => _pack?.targets.map((e) => e['phone']).whereType<String>().firstOrNull ?? '1930';

  // The chosen path gets a primary-colour outline around the shared ActionTile.
  Widget _path(Key key, bool lost, IconData icon, String title, String sub) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: _lost == lost ? cs.primary : cs.outline.withValues(alpha: 0), width: 3),
      ),
      child: ActionTile(key: key, icon: icon, label: title, caption: sub, onTap: () => _choose(lost)),
    );
  }

  List<Widget> _detail(ThemeData t, ReportStrings s, _Pack pack) {
    final lost = _lost == true;
    final urls = [for (final x in pack.targets) if (x['url'] is String) x['url'] as String];
    final portal = urls.any((u) => Uri.parse(u).host.contains('cybercrime'));
    return [
      if (lost && _remainingMs == null)
        Padding(
          padding: const EdgeInsets.only(top: Sp.m),
          child: ActionTile(
              key: const Key('golden_start'),
              icon: Icons.timer,
              label: s['start'],
              caption: s['startSub'],
              onTap: _startGolden),
        ),
      const SizedBox(height: Sp.l),
      _steps(t, s, [
        (Icons.phone_in_talk, s['step1'], s['dialHint']),
        if (urls.isNotEmpty) (portal ? Icons.language : Icons.report, s[portal ? 'stepPortal' : 'stepChakshu'], null),
        (Icons.photo_library, s['stepShots'], null),
      ]),
      const SizedBox(height: Sp.l),
      for (final target in pack.targets) ..._target(s, target),
      _evidence(t, s, pack),
      _fields(t, s, lost),
      if (lost && _remainingMs != null) ...[
        const SizedBox(height: Sp.m),
        _secondary(const Key('btn_share'), Icons.ios_share, s, 'share',
            () => _run(widget.api.goldenShare({for (final e in _ctrl.entries) e.key: e.value.text}), 'shareErr')),
      ],
    ];
  }

  // Numbered next steps: badge, icon, one Hindi line (and an optional caption).
  Widget _steps(ThemeData t, ReportStrings s, List<(IconData, String, String?)> steps) {
    final cs = t.colorScheme;
    return _card(
      t,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, (icon, text, caption)) in steps.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : Sp.l),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cs.primary, width: 2)),
                child: Text('${i + 1}', style: t.textTheme.titleSmall?.copyWith(color: cs.primary)),
              ),
              const SizedBox(width: Sp.m),
              Icon(icon, size: 28, color: cs.onSurface),
              const SizedBox(width: Sp.s),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(text, style: t.textTheme.titleMedium),
                  if (caption != null)
                    Text(caption, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }

  // Secondary action: Hindi (or chosen language) label, with a smaller English line when the screen is not in English.
  Widget _secondary(Key key, IconData icon, ReportStrings s, String k, VoidCallback onTap) {
    final t = Theme.of(context);
    return OutlinedButton.icon(
      key: key,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
      onPressed: onTap,
      icon: Icon(icon, size: 28),
      label: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(s[k], textAlign: TextAlign.center),
        if (_lang != 'en')
          Text(ReportStrings.en[k], textAlign: TextAlign.center, style: t.textTheme.bodySmall),
      ]),
    );
  }

  Widget _card(ThemeData t, Widget child, {Color? color}) => Container(
        padding: const EdgeInsets.all(Sp.l),
        decoration: BoxDecoration(
          color: color ?? t.colorScheme.surface,
          borderRadius: BorderRadius.circular(Rad.lg),
          border: Border.all(color: t.colorScheme.outline),
        ),
        child: child,
      );

  Widget _golden(ThemeData t, ReportStrings s) {
    final ms = _remainingMs!;
    final st = t.extension<StatusColors>() ?? StatusColors.light;
    final expired = ms == 0;
    // Quiet hero: tinted surface, hairline in the scam colour, a thin bar instead of a loud ring.
    return Padding(
      padding: const EdgeInsets.only(top: Sp.l),
      child: _card(
        t,
        color: st.tintOver(RiskLabel.scam, t.colorScheme.surface),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.timer_outlined, size: 28, color: st.scam),
            const SizedBox(width: Sp.s),
            Expanded(child: Text(s['goldenTitle'], style: t.textTheme.titleMedium?.copyWith(color: st.scam))),
          ]),
          const SizedBox(height: Sp.m),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(_clock(ms),
                key: const Key('golden_timer'),
                style: t.textTheme.displayLarge?.copyWith(
                    color: st.scam, fontSize: 64, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(height: Sp.m),
          LinearProgressIndicator(
              value: ms / _goldenMs,
              // semanticsValue must be numeric in Flutter, so the unit lives in the label.
              semanticsLabel: s['minLeft'].replaceFirst('{n}', '${(ms / 60000).ceil()}'),
              color: st.scam,
              backgroundColor: t.colorScheme.surface),
          const SizedBox(height: Sp.m),
          Text(expired ? s['expired'] : s['goldenHint'], key: const Key('golden_hint'), style: t.textTheme.titleMedium),
          if (expired) ...[
            const SizedBox(height: Sp.m),
            OutlinedButton(
              key: const Key('golden_restart'),
              onPressed: _startGolden,
              child: Text(s['restart'], textAlign: TextAlign.center),
            ),
          ],
        ]),
      ),
    );
  }

  // The helpline is the pinned button; only url targets (portal, Chakshu) are listed here.
  List<Widget> _target(ReportStrings s, Map<Object?, Object?> target) {
    final url = target['url'] as String?;
    if (url == null) return const [];
    final host = Uri.parse(url).host;
    final portal = host.contains('cybercrime');
    return [
      _secondary(Key('btn_open_$host'), portal ? Icons.language : Icons.report, s, portal ? 'portal' : 'chakshu',
          () => _run(widget.api.open(url), 'openErr')),
      const SizedBox(height: Sp.m),
    ];
  }

  Widget _evidence(ThemeData t, ReportStrings s, _Pack pack) {
    final st = t.extension<StatusColors>() ?? StatusColors.light;
    return _card(
      t,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.fact_check, size: 32),
          const SizedBox(width: Sp.m),
          Expanded(child: Text(s['evidence'], style: t.textTheme.titleLarge)),
        ]),
        const SizedBox(height: Sp.xs),
        if (pack.evidence.isEmpty)
          StateMessage(icon: Icons.info_outline, title: s['evidenceNone'])
        else ...[
          Text(s['evidenceAuto'], style: t.textTheme.bodyLarge),
          for (final e in pack.evidence) _evidenceTile(t, s, st, e),
        ],
      ]),
    );
  }

  Widget _evidenceTile(ThemeData t, ReportStrings s, StatusColors st, Map<Object?, Object?> e) {
    final type = e['scamType'] as String?;
    final src = e['source'] as String? ?? '';
    final triggers = ((e['triggers'] as List?) ?? const []).cast<Object?>();
    return Padding(
      padding: const EdgeInsets.only(top: Sp.m),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.check_box, size: 32, color: st.safe),
        const SizedBox(width: Sp.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e['time']}', style: t.textTheme.titleMedium),
            Text('${type == null ? '' : '${s['t_$type']} · '}${s['s_$src']}', style: t.textTheme.bodyLarge),
            if (triggers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Sp.xs),
                child: Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
                  for (final trig in triggers)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: Sp.s, vertical: Sp.xs),
                      decoration: BoxDecoration(
                        color: t.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(Rad.sm),
                      ),
                      child: Text('$trig', style: t.textTheme.bodySmall),
                    ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _fields(ThemeData t, ReportStrings s, bool lost) => Padding(
        padding: const EdgeInsets.only(top: Sp.m),
        child: _card(
          t,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.edit_note, size: 32),
              const SizedBox(width: Sp.m),
              Expanded(child: Text(s['yours'], style: t.textTheme.titleLarge)),
            ]),
            for (final k in _fieldKeys)
              if (k != 'screenshots' && (lost || !_lostOnlyFields.contains(k))) ..._field(t, s, k),
            // Rarely needed, so it stays out of the way until the user asks for it.
            ExpansionTile(
              key: const Key('more_details'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(s['more'], style: t.textTheme.titleMedium),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: _field(t, s, 'screenshots'),
            ),
          ]),
        ),
      );

  List<Widget> _field(ThemeData t, ReportStrings s, String k) => [
        const SizedBox(height: Sp.m),
        Text(s['f_$k'], style: t.textTheme.titleMedium),
        const SizedBox(height: Sp.xs),
        TextField(
          key: Key('field_$k'),
          controller: _ctrl[k],
          keyboardType: k == 'amount' ? TextInputType.number : TextInputType.text,
          style: t.textTheme.bodyLarge,
        ),
      ];
}
