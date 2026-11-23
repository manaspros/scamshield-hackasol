import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/text_api.dart';
import '../models/verdict.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/action_tile.dart';
import '../widgets/press_scale.dart';
import '../widgets/section_header.dart';
import '../widgets/state_message.dart';
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
  final _history = <({Verdict v, DateTime at})>[]; // newest first
  bool _busy = false;
  String? _error; // friendly, fixed copy only (QR scanner unavailable); never raw exception text
  VoidCallback? _retry; // non-null while the last attempt failed: shows the retry state
  String? _inputError; // shown under the field when the primary is tapped with nothing typed
  bool _upiOpen = false;
  String _toldName = ''; // name typed when upi.check last ran, shown beside the QR's name on a mismatch
  Map<Object?, Object?>? _upi; // last `upi.check` result (Kotlin: TextApi.upiCheck)

  static const _api = MethodChannel('scamshield/api');
  static const _qr = MethodChannel('scamshield/qr'); // Kotlin QrChannel: ML Kit code scanner (Play services UI)
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

  static const _example = 'SBI se bol raha hoon, aapka KYC update pending hai'; // kept from the old sample chips

  Future<void> _run() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _inputError = 'पहले मैसेज डालें');
      return;
    }
    setState(() { _busy = true; _error = null; _retry = null; _inputError = null; });
    try {
      final v = await TextApi.classify(text);
      setState(() => _history.insert(0, (v: v, at: DateTime.now())));
      final link = _upiLink.firstMatch(text)?.group(0);
      if (link != null) await _checkUpi(link);
    } catch (e) {
      _fail(e, _run);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Raw detail goes to the log only; the user sees one fixed message and a retry.
  void _fail(Object e, VoidCallback retry) {
    debugPrint('try_api: $e');
    if (mounted) setState(() { _error = null; _retry = retry; });
  }

  Future<void> _checkUpi(String link) async {
    if (mounted) setState(() { _error = null; _retry = null; });
    try {
      final told = _nameCtrl.text.trim();
      final m = await _api.invokeMapMethod<Object?, Object?>('upi.check', {'link': link, 'expectedName': told});
      if (mounted) setState(() { _toldName = told; _upi = m ?? const {'valid': false}; });
    } catch (e) {
      _fail(e, () => _checkUpi(link));
    }
  }

  // Scanner value goes through the SAME path as a pasted link: fill the field, then upi.check -> UpiQr.
  Future<void> _scanQr() async {
    if (mounted) setState(() { _error = null; _retry = null; });
    try {
      final raw = (await _qr.invokeMethod<String>('qr.scan'))?.trim();
      if (raw == null || raw.isEmpty) return; // cancelled
      _upiCtrl.text = raw;
      await _checkUpi(raw);
    } on PlatformException catch (e) {
      if (e.code == 'UNAVAILABLE') {
        debugPrint('try_api: $e');
        if (mounted) {
          setState(() =>
              _error = 'QR स्कैनर उपलब्ध नहीं है। लिंक चिपकाएँ। · QR scanner not available; paste the link instead.');
        }
      } else {
        _fail(e, _scanQr);
      }
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

  // Scan QR: the secondary action. Same key and same qr.scan -> upi.check path as before. It sits after the toggle
  // because ensureVisible(toggle) in the QA tests aligns the toggle to the top of the lazy list.
  Widget _scanButton() => PressScale(
        child: OutlinedButton.icon(
          key: const Key('btn_upi_scan'),
          onPressed: _scanQr,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('QR स्कैन करें', textAlign: TextAlign.center),
        ),
      );

  // Text-style disclosure for the paste-a-link fields, right under the input so it is always built.
  Widget _upiToggle() => TextButton.icon(
        key: const Key('upi_section'),
        onPressed: () => setState(() => _upiOpen = !_upiOpen),
        icon: Icon(_upiOpen ? Icons.expand_less : Icons.link),
        label: const Text('UPI लिंक चिपकाएँ', textAlign: TextAlign.center),
      );

  Widget _upiTile() {
    if (!_upiOpen) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: Sp.s),
          TextField(
            key: const Key('upi_link_field'),
            controller: _upiCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'UPI लिंक / QR टेक्स्ट · UPI link / QR text'),
          ),
          const SizedBox(height: Sp.m),
          TextField(
            key: const Key('upi_name_field'),
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'आपको बताया गया नाम (चाहें तो) · Name I was told'),
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
    // A name mismatch is amber (act now), not red: the person is still in control of the payment.
    final label = (mismatch || collect) ? RiskLabel.suspicious : RiskLabel.safe;
    final solid = st.solid(label);
    Widget warn(Key k, Color c, String hi, String? imperative, String en) => Padding(
          padding: const EdgeInsets.only(top: Sp.m),
          child: Row(key: k, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_rounded, size: 32, color: c),
            const SizedBox(width: Sp.s),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hi, style: tt.titleMedium),
                if (imperative != null) Text(imperative, style: tt.titleMedium?.copyWith(color: c)),
                Text(en, style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        );
    final tabular = [const FontFeature.tabularFigures()];
    final payee = '${u['payeeName'] ?? ''}'.trim();
    final amount = u['amount'] == null ? '' : '${u['amount']}'.trim();
    final qrName = payee.isEmpty ? 'नाम नहीं मिला' : payee;
    final told = _toldName.isEmpty ? '—' : _toldName;
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
        if (payee.isNotEmpty || amount.isNotEmpty) ...[
          const SizedBox(height: Sp.l),
          Text('पैसे पाने वाला', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          if (payee.isNotEmpty)
            Text(payee, key: const Key('upi_payee'), style: tt.headlineMedium?.copyWith(fontFeatures: tabular)),
          if (amount.isNotEmpty) ...[
            const SizedBox(height: Sp.s),
            Text('आप भेज रहे हैं', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            Text('₹$amount', key: const Key('upi_amount'), style: tt.displayLarge?.copyWith(fontFeatures: tabular)),
          ],
        ],
        if (u['payeeVpa'] != null) ...[
          const SizedBox(height: Sp.m),
          Row(children: [
            Icon(Icons.account_circle_outlined, size: 28, color: cs.onSurfaceVariant),
            const SizedBox(width: Sp.s),
            Expanded(child: Text('UPI ID: ${u['payeeVpa']}', key: const Key('upi_vpa'), style: tt.bodyLarge)),
          ]),
        ],
        if (mismatch)
          warn(const Key('upi_mismatch'), st.suspicious, 'QR में नाम: $qrName — आपको बताया गया नाम: $told',
              'पैसे भेजने से पहले नाम मिलाएँ', 'Name does not match this UPI ID'),
        if (collect)
          warn(const Key('upi_collect'), st.suspicious,
              'यह QR पैसे माँगता है। इसे स्कैन करने से पैसे जाते हैं, आते नहीं।', null,
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

  static const _shortWord = <RiskLabel, String>{
    RiskLabel.safe: 'सुरक्षित',
    RiskLabel.suspicious: 'सावधान',
    RiskLabel.scam: 'धोखाधड़ी',
  };

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // Before any check: icon, one line, one example that only fills the input.
  Widget _empty() {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Column(key: const Key('try_empty'), children: [
      const SizedBox(height: Sp.l),
      const StateMessage(
        icon: Icons.verified_user_outlined,
        title: 'कोई संदिग्ध मैसेज यहाँ चिपकाएँ, हम बताएँगे कि ठगी तो नहीं',
      ),
      Semantics(
        button: true,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Rad.md), side: BorderSide(color: cs.outline)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('try_example'),
            onTap: () => setState(() { _ctrl.text = _example; _inputError = null; }),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kTouch),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.m),
                child: Row(children: [
                  Icon(Icons.edit_note, size: 28, color: cs.primary),
                  const SizedBox(width: Sp.s),
                  Expanded(child: Text(_example, style: t.textTheme.bodyLarge)),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  // Older checks: status chip, first line of the message, time. The newest is the full card above.
  Widget _historyRows() {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final older = _history.skip(1).toList();
    return Column(key: const Key('try_history'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader(title: 'पिछली जाँचें', icon: Icons.history),
      for (final h in older)
        Container(
          margin: const EdgeInsets.only(bottom: Sp.s),
          padding: const EdgeInsets.all(Sp.m),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(Rad.md),
            border: Border.all(color: cs.outline),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: StatusChip(label: h.v.label, text: _shortWord[h.v.label])),
              const SizedBox(width: Sp.s),
              Text(_hhmm(h.at),
                  style: t.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: Sp.xs),
            Text(h.v.text.split('\n').first, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyLarge),
          ]),
        ),
    ]);
  }

  // Only the primary is pinned (the Scaffold body shrinks above the keyboard, so it stays reachable at 360dp).
  Widget _actionBar() {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.l, Sp.m, Sp.l, Sp.m),
      decoration: BoxDecoration(
        color: t.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: t.colorScheme.outline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity, // full-width pill
          child: PressScale(
            enabled: !_busy,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: Sp.m)),
              onPressed: _busy ? null : _run,
              icon: _busy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                  : const Icon(Icons.verified_user),
              label: Text(_busy ? 'जाँच हो रही है…' : 'मैसेज जाँचें', textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(Sp.l), children: [
          TextField(
            controller: _ctrl,
            minLines: 4,
            maxLines: 8,
            textInputAction: TextInputAction.newline,
            onChanged: (_) {
              if (_inputError != null) setState(() => _inputError = null);
            },
            decoration: InputDecoration(
              hintText: 'संदेश यहाँ चिपकाएँ',
              hintMaxLines: 4,
              alignLabelWithHint: true,
              errorText: _inputError,
              errorMaxLines: 3,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Sp.s),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          if (_retry != null)
            StateMessage(
              key: const Key('try_failed'),
              icon: Icons.error_outline,
              title: 'जाँच नहीं हो पाई, फिर कोशिश करें',
              subtitle: "Couldn't check, try again",
              actionLabel: 'दोबारा जाँचें',
              onAction: _retry,
            ),
          const SizedBox(height: Sp.m),
          _upiToggle(),
          _scanButton(),
          _upiTile(),
          if (_upi != null) _upiCard(),
          if (_history.isEmpty && _upi == null) _empty(),
          if (_history.isNotEmpty) ..._result(_history.first.v),
          if (_history.length > 1) _historyRows(),
        ]),
      ),
      _actionBar(),
    ]);
  }
}
