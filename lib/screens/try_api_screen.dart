import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/text_api.dart';
import '../models/verdict.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/action_tile.dart';
import '../widgets/status_chip.dart';
import '../widgets/verdict_card.dart';
import 'report_screen.dart' show HandoffApi, ReportStrings;

/// Paste any SMS / WhatsApp message / call sentence and run the on-device Text API.
class TryApiScreen extends StatefulWidget {
  const TryApiScreen({super.key});
  @override
  State<TryApiScreen> createState() => _TryApiScreenState();
}

class _TryApiScreenState extends State<TryApiScreen> {
  final _ctrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _history = <Verdict>[];
  bool _busy = false;
  String? _error;
  bool _upiOpen = false;
  Map<Object?, Object?>? _upi; // last `upi.check` result (Kotlin: TextApi.upiCheck)

  static const _api = MethodChannel('scamshield/api');
  // The whole link goes to Kotlin UpiQr.parse (single implementation); Dart only finds it in pasted text.
  static final _upiLink = RegExp(r'upi://\S+', caseSensitive: false);

  // Same lines as the live feed (live_feed_screen.dart _advice), Hindi first.
  static const _adviceTitle = 'घबराएँ नहीं। अभी यह करें:';
  static const _payAdvice = ['पैसे न भेजें, कॉल काट दें', 'OTP या PIN किसी को न बताएँ'];
  static const _advice = <RiskLabel, List<String>>{
    RiskLabel.scam: _payAdvice,
    RiskLabel.suspicious: ['जल्दबाज़ी न करें, कॉल काट दें', 'पहले अपने परिवार से पूछें'],
  };

  @override
  void dispose() {
    _ctrl.dispose();
    _upiCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  static const samples = [
    'Sir aapke phone pe OTP aaya hoga, woh bata dijiye',
    'मैं सीबीआई से बोल रहा हूं, आप डिजिटल अरेस्ट में हैं, किसी को मत बताना',
    'Your FedEx parcel has illegal drugs, press 1 to talk to customs',
    'SBI se bol raha hoon, aapka KYC update pending hai',
    'Beta khana kha liya? Kal shaam ko milte hain',
    'Please install AnyDesk so I can process your refund',
  ];

  Future<void> _run() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final v = await TextApi.classify(text);
      setState(() => _history.insert(0, v));
      final link = _upiLink.firstMatch(text)?.group(0);
      if (link != null) await _checkUpi(link);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkUpi(String link) async {
    try {
      final m = await _api.invokeMapMethod<Object?, Object?>(
          'upi.check', {'link': link, 'expectedName': _nameCtrl.text.trim()});
      if (mounted) setState(() => _upi = m ?? const {'valid': false});
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _dial() async {
    final ok = await const HandoffApi().dial('1930'); // ACTION_DIAL only; the user presses the green button
    if (!ok && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(ReportStrings.hi['openErr'])));
    }
  }

  // Under every SUSPICIOUS/SCAM result and under the UPI warning card (UX_AUDIT 2.5 P1 #3).
  Widget _helpline() => ActionTile(
        key: const Key('helpline_1930'),
        icon: Icons.call,
        label: '1930 पर कॉल करें',
        caption: 'साइबर ठगी की मुफ़्त हेल्पलाइन। डायल खुलेगा, हरा बटन आप खुद दबाएँ।',
        onTap: _dial,
      );

  // showDebug:false (UX audit #3): Hindi headline, advice + 1930 row, reasons behind 'क्यों?'. No % on this screen.
  List<Widget> _result(Verdict v) {
    final warn = v.label != RiskLabel.safe;
    return [
      if (v.scamTypeLabel != null && warn)
        Padding(
          padding: const EdgeInsets.only(top: Sp.m),
          child: Align(alignment: Alignment.centerLeft, child: StatusChip(label: v.label, text: v.scamTypeLabel)),
        ),
      VerdictCard(
        verdict: v,
        showDebug: false,
        adviceTitle: warn ? _adviceTitle : null,
        advice: _advice[v.label] ?? const [],
        footer: warn ? _helpline() : null,
      ),
    ];
  }

  // Toggle sits beside Analyse (no extra height), so the Analyse button keeps its place at 2.0x and the shared QA
  // reveal helper never has to scroll it mid-animation. The fields below are built only while open.
  Widget _upiToggle() => IconButton.outlined(
        key: const Key('upi_section'),
        tooltip: 'UPI लिंक / QR जाँचें · Check a UPI link',
        constraints: const BoxConstraints(minWidth: kTouch, minHeight: kTouch),
        onPressed: () => setState(() => _upiOpen = !_upiOpen),
        icon: Icon(_upiOpen ? Icons.expand_less : Icons.qr_code_2, size: 32),
      );

  Widget _upiTile() {
    if (!_upiOpen) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: Sp.s),
          TextField(
            key: const Key('upi_link_field'),
            controller: _upiCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
                labelText: 'UPI लिंक / QR टेक्स्ट · UPI link / QR text', border: OutlineInputBorder()),
          ),
          const SizedBox(height: Sp.m),
          TextField(
            key: const Key('upi_name_field'),
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: 'आपको बताया गया नाम (चाहें तो) · Name I was told', border: OutlineInputBorder()),
          ),
          const SizedBox(height: Sp.m),
          OutlinedButton.icon(
            key: const Key('btn_upi_check'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
            onPressed: () {
              final link = _upiCtrl.text.trim();
              if (link.isNotEmpty) _checkUpi(link);
            },
            icon: const Icon(Icons.verified_user),
            label: const Text('लिंक जाँचें · Check link', textAlign: TextAlign.center),
          ),
          const SizedBox(height: Sp.m),
    ]);
  }

  // Result of `upi.check` {valid, payeeName, payeeVpa (already masked), amount, isCollect, mismatch, framing, framingHi}.
  Widget _upiCard() {
    final u = _upi!;
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final tt = t.textTheme;
    final st = t.extension<StatusColors>() ?? StatusColors.light;
    if (u['valid'] != true) {
      return Padding(
        padding: const EdgeInsets.only(top: Sp.m),
        child: Row(key: const Key('upi_invalid'), crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 28, color: cs.onSurfaceVariant),
          const SizedBox(width: Sp.s),
          Expanded(
              child: Text('यह UPI लिंक सही नहीं लगता। upi://pay?pa=... वाला पूरा लिंक डालें।\nNot a valid UPI link.',
                  style: tt.bodyLarge)),
        ]),
      );
    }
    final mismatch = u['mismatch'] == true;
    final collect = u['isCollect'] == true;
    final label = mismatch ? RiskLabel.scam : (collect ? RiskLabel.suspicious : RiskLabel.safe);
    final solid = st.solid(label);
    Widget warn(Key k, Color c, IconData icon, String hi, String en) => Padding(
          padding: const EdgeInsets.only(top: Sp.m),
          child: Row(key: k, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 32, color: c),
            const SizedBox(width: Sp.s),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hi, style: tt.titleMedium?.copyWith(color: c)),
                Text(en, style: tt.bodyLarge),
              ]),
            ),
          ]),
        );
    return Container(
      key: const Key('upi_card'),
      margin: const EdgeInsets.only(top: Sp.m),
      padding: const EdgeInsets.all(Sp.xl),
      decoration: BoxDecoration(
        color: st.tintOver(label, cs.surface),
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: solid.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.payments, size: 40, color: solid),
          const SizedBox(width: Sp.m),
          Expanded(child: Text('${u['framingHi']}', key: const Key('upi_framing_hi'), style: tt.titleLarge?.copyWith(color: solid))),
        ]),
        const SizedBox(height: Sp.xs),
        Text('${u['framing']}', key: const Key('upi_framing_en'), style: tt.titleMedium),
        if (u['payeeVpa'] != null) ...[
          const SizedBox(height: Sp.m),
          Row(children: [
            Icon(Icons.account_circle_outlined, size: 28, color: cs.onSurfaceVariant),
            const SizedBox(width: Sp.s),
            Expanded(child: Text('UPI ID: ${u['payeeVpa']}', key: const Key('upi_vpa'), style: tt.bodyLarge)),
          ]),
        ],
        if (mismatch)
          warn(const Key('upi_mismatch'), st.scam, Icons.error,
              'नाम मेल नहीं खाता। यह खाता उस नाम का नहीं है जो आपको बताया गया।', 'Name does not match this UPI ID'),
        if (collect)
          warn(const Key('upi_collect'), st.suspicious, Icons.warning_amber_rounded,
              'यह QR पैसे माँगता है। इसे स्कैन करने से पैसे जाते हैं, आते नहीं।',
              'This QR requests money; scanning it sends money, it never receives money.'),
        if (mismatch || collect) ...[
          const SizedBox(height: Sp.m),
          Text(_adviceTitle, style: tt.titleMedium),
          for (final line in _payAdvice)
            Padding(
              padding: const EdgeInsets.only(top: Sp.s),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.task_alt, size: 28, color: solid),
                const SizedBox(width: Sp.s),
                Expanded(child: Text(line, style: tt.titleMedium)),
              ]),
            ),
          const SizedBox(height: Sp.m),
          _helpline(),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
        controller: _ctrl,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'संदेश यहाँ चिपकाएँ · Paste a message',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final s in samples)
          ActionChip(
            label: Text(s.length > 20 ? '${s.substring(0, 20)}…' : s, maxLines: 1, overflow: TextOverflow.ellipsis),
            onPressed: () => _ctrl.text = s,
          ),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.shield),
            label: Text(_busy ? 'Analysing on device…' : 'Analyse'),
          ),
        ),
        const SizedBox(width: Sp.s),
        _upiToggle(),
      ]),
      if (_error != null) Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
      const SizedBox(height: 12),
      _upiTile(),
      if (_upi != null) _upiCard(),
      for (final v in _history) ..._result(v),
    ]);
  }
}
