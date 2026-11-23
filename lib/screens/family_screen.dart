import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart' show StatusColors;
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import '../widgets/section_header.dart';
import '../widgets/state_message.dart';

/// Family code: pair two phones with a shared secret, then compare a rotating
/// 6-digit code against what a caller claims. Codes are computed natively.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({
    super.key,
    this.channel = const MethodChannel('scamshield/family'),
    this.initialLang = 'hi',
  });
  final MethodChannel channel;
  final String initialLang;
  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

enum _Stage { loading, choose, showSecret, enterSecret, code }

const _step = 30;
final _base32 = RegExp(r'^[A-Z2-7]{16,}$');

// hne strings are a first draft: [VERIFY] with a native Chhattisgarhi speaker.
const _s = <String, Map<String, String>>{
  'hi': {
    'title': 'परिवार का कोड',
    'intro': 'असली परिवार वाले को पहचानने के लिए एक गुप्त कोड',
    'show': 'मेरा कोड दिखाएँ',
    'enter': 'परिवार का कोड डालें',
    'secretTitle': 'यह कोड परिवार वाले के फ़ोन में डालें',
    'done': 'हो गया',
    'field': 'परिवार का कोड',
    'save': 'सेव करें',
    'bad': 'कोड सही नहीं है। केवल अक्षर A-Z और अंक 2-7।',
    'now': 'अभी का कोड',
    'sec': 'सेकंड',
    'ask': 'क्या फ़ोन करने वाले का कोड यही है?',
    'yes': 'हाँ, मिलता है',
    'no': 'नहीं मिलता',
    'yesMsg': 'कोड मिल गया। फिर भी पैसे भेजने से पहले सोचें।',
    'noMsg': 'फ़ोन काट दें। अपने परिवार के सदस्य को उनके जाने-पहचाने नंबर पर फ़ोन करें।',
    'unpair': 'जोड़ी हटाएँ',
    'err': 'कोड नहीं मिल सका। फिर कोशिश करें।',
    'retry': 'फिर कोशिश करें',
    'loading': 'कोड जाँचा जा रहा है…',
  },
  'hne': {
    'title': 'परिवार के कोड',
    'intro': 'असली परिवार वाले ल चिन्हे बर एक गुप्त कोड',
    'show': 'मोर कोड देखाव',
    'enter': 'परिवार के कोड डारव',
    'secretTitle': 'ए कोड परिवार वाले के फ़ोन म डारव',
    'done': 'हो गे',
    'field': 'परिवार के कोड',
    'save': 'सेव करव',
    'bad': 'कोड सही नइहे। सिरिफ अक्षर A-Z अउ अंक 2-7।',
    'now': 'अभी के कोड',
    'sec': 'सेकंड',
    'ask': 'का फ़ोन करइया के कोड इही हे?',
    'yes': 'हव, मिलथे',
    'no': 'नइ मिलय',
    'yesMsg': 'कोड मिल गे। तभो पइसा भेजे के पहिली सोचव।',
    'noMsg': 'फ़ोन काट देव। अपन परिवार वाले ल ओकर जाने-पहिचाने नंबर म फ़ोन करव।',
    'unpair': 'जोड़ी हटावव',
    'err': 'कोड नइ मिलिस। फेर कोशिश करव।',
    'retry': 'फेर कोशिश करव',
    'loading': 'कोड जाँचत हे…',
  },
  'en': {
    'title': 'Family code',
    'intro': 'A secret code that proves a caller is really family',
    'show': 'Show my code',
    'enter': 'Enter family code',
    'secretTitle': 'Type this code into your family member\'s phone',
    'done': 'Done',
    'field': 'Family code',
    'save': 'Save',
    'bad': 'Code is not valid. Use letters A-Z and digits 2-7 only.',
    'now': 'Code right now',
    'sec': 'sec',
    'ask': 'Does the caller\'s code match?',
    'yes': 'Yes, it matches',
    'no': 'No, it does not',
    'yesMsg': 'Code matches. Still think before sending any money.',
    'noMsg': 'Hang up. Call your family member on their known number.',
    'unpair': 'Remove pairing',
    'err': 'Could not get the code. Try again.',
    'retry': 'Try again',
    'loading': 'Checking the code…',
  },
};

class _FamilyScreenState extends State<FamilyScreen> {
  late String _lang = widget.initialLang;
  _Stage _stage = _Stage.loading;
  String _secret = '';
  String _code = '';
  int _remaining = _step;
  bool? _match;
  bool _failed = false;
  String? _fieldError;
  Timer? _timer;
  final _field = TextEditingController();

  String t(String k) => _s[_lang]![k]!;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _field.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final st = await widget.channel.invokeMapMethod<String, Object?>('family.status');
      if (st?['paired'] == true) return _startCode();
    } catch (_) {}
    if (mounted) setState(() => _stage = _Stage.choose);
  }

  Future<void> _showMine() async {
    try {
      final s = await widget.channel.invokeMethod<String>('family.newSecret');
      if (mounted) setState(() { _secret = s ?? ''; _stage = _Stage.showSecret; });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _save() async {
    final v = _field.text.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (!_base32.hasMatch(v)) return setState(() => _fieldError = t('bad'));
    try {
      await widget.channel.invokeMethod<void>('family.setSecret', {'secret': v});
      _startCode();
    } catch (_) {
      if (mounted) setState(() => _fieldError = t('bad'));
    }
  }

  Future<void> _unpair() async {
    _timer?.cancel();
    try { await widget.channel.invokeMethod<void>('family.unpair'); } catch (_) {}
    if (mounted) setState(() { _stage = _Stage.choose; _match = null; _field.clear(); _fieldError = null; });
  }

  /// Local 1 s countdown; refetch from native when it rolls over (single TOTP implementation).
  Future<void> _startCode() async {
    await _fetch();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        _fetch();
      } else if (mounted) {
        setState(() => _remaining--);
      }
    });
  }

  Future<void> _fetch() async {
    try {
      final m = await widget.channel.invokeMapMethod<String, Object?>('family.code');
      if (!mounted) return;
      setState(() {
        _code = m?['code'] as String? ?? '';
        _remaining = (m?['remainingSec'] as num?)?.toInt() ?? _step;
        _stage = _Stage.code;
        _failed = false;
        _match = null; // new code, previous answer no longer applies
      });
    } catch (_) {
      if (mounted) setState(() { _failed = true; _stage = _Stage.code; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(Sp.l),
      children: [
        Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
          for (final (code, label) in const [('hi', 'हिन्दी'), ('hne', 'छत्तीसगढ़ी'), ('en', 'English')])
            ChoiceChip(
              key: Key('lang_$code'),
              label: Text(label),
              selected: _lang == code,
              onSelected: (_) => setState(() => _lang = code),
            ),
        ]),
        const SizedBox(height: Sp.m),
        // Intro only on the first screens; later stages need the room for the code.
        if (_stage == _Stage.loading || _stage == _Stage.choose)
          SectionHeader(title: t('title'), icon: Icons.family_restroom, subtitle: t('intro')),
        ...switch (_stage) {
          _Stage.loading => [StateMessage(loading: true, title: t('loading'))],
          _Stage.choose => _choose(theme),
          _Stage.showSecret => _showSecret(theme),
          _Stage.enterSecret => _enterSecret(theme),
          _Stage.code => _codeView(theme),
        },
      ],
    );
  }

  Widget _big(Key key, IconData icon, String label, VoidCallback onTap, {Color? bg, Color? fg}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Sp.m),
        child: FilledButton.icon(
          key: key,
          onPressed: onTap,
          style: FilledButton.styleFrom(
              backgroundColor: bg, foregroundColor: fg, minimumSize: const Size.fromHeight(kTouch)),
          icon: Icon(icon, size: 32),
          label: Text(label, textAlign: TextAlign.center),
        ),
      );

  List<Widget> _choose(ThemeData theme) => [
        if (_failed)
          StateMessage(icon: Icons.error_outline, title: t('err'), actionLabel: t('retry'), onAction: _showMine),
        // One primary action; entering a code by hand is the secondary path.
        _big(const Key('family_show'), Icons.visibility, t('show'), _showMine),
        OutlinedButton.icon(
          key: const Key('family_enter'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
          onPressed: () => setState(() => _stage = _Stage.enterSecret),
          icon: const Icon(Icons.keyboard, size: 32),
          label: Text(t('enter'), textAlign: TextAlign.center),
        ),
      ];

  List<Widget> _showSecret(ThemeData theme) {
    final groups = [for (var i = 0; i < _secret.length; i += 4) _secret.substring(i, (i + 4).clamp(0, _secret.length))];
    return [
      Text(t('secretTitle'), style: theme.textTheme.titleLarge),
      const SizedBox(height: Sp.m),
      Card(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(Sp.l),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: Sp.l,
            runSpacing: Sp.s,
            children: [
              for (final g in groups)
                // Each group sits in its own Row: same test key x4 must not be siblings.
                Row(mainAxisSize: MainAxisSize.min, children: [
                Text(g,
                    key: const Key('family_secret_group'),
                    style: theme.textTheme.headlineMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
            ],
          ),
        ),
      ),
      const SizedBox(height: Sp.m),
      _big(const Key('family_done'), Icons.check_circle, t('done'), _startCode),
    ];
  }

  List<Widget> _enterSecret(ThemeData theme) => [
        TextField(
          key: const Key('family_field'),
          controller: _field,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          style: theme.textTheme.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          decoration: InputDecoration(
            labelText: t('field'),
            errorText: _fieldError,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: Sp.m),
        _big(const Key('family_save'), Icons.save, t('save'), _save),
      ];

  List<Widget> _codeView(ThemeData theme) {
    if (_failed) {
      return [
        StateMessage(icon: Icons.error_outline, title: t('err'), actionLabel: t('retry'), onAction: _fetch),
        TextButton.icon(
          key: const Key('family_unpair'),
          onPressed: _unpair,
          icon: const Icon(Icons.link_off),
          label: Text(t('unpair'), textAlign: TextAlign.center),
        ),
      ];
    }
    final spaced = _code.length == 6 ? '${_code.substring(0, 3)} ${_code.substring(3)}' : _code;
    final st = theme.extension<StatusColors>()!;
    final yes = st.safe;
    final no = st.scam;
    return [
      Text(t('now'), style: theme.textTheme.titleMedium),
      const SizedBox(height: Sp.s),
      Center(
        child: SizedBox(
          width: 280,
          height: 280,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                key: const Key('family_ring'),
                value: _remaining / _step,
                strokeWidth: 14,
                color: _remaining <= 5 ? no : theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.xxl),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(spaced,
                      key: const Key('family_code'),
                      style: AppText.display.copyWith(fontSize: 56, color: theme.colorScheme.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('$_remaining ${t('sec')}',
                      key: const Key('family_remaining'),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: Sp.l),
      Text(t('ask'), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
      const SizedBox(height: Sp.m),
      _big(const Key('family_yes'), Icons.check_circle, t('yes'), () => setState(() => _match = true),
          bg: yes, fg: theme.colorScheme.surface),
      _big(const Key('family_no'), Icons.cancel, t('no'), () => setState(() => _match = false),
          bg: no, fg: theme.colorScheme.surface),
      if (_match == true)
        _banner(const Key('family_yes_msg'), Icons.check_circle, t('yesMsg'), yes, theme),
      if (_match == false)
        _banner(const Key('family_no_warning'), Icons.warning_amber_rounded, t('noMsg'), no, theme),
      const SizedBox(height: Sp.s),
      TextButton.icon(
        key: const Key('family_unpair'),
        onPressed: _unpair,
        icon: const Icon(Icons.link_off),
        label: Text(t('unpair'), textAlign: TextAlign.center),
      ),
    ];
  }

  Widget _banner(Key key, IconData icon, String msg, Color c, ThemeData theme) => Container(
        key: key,
        margin: const EdgeInsets.only(bottom: Sp.s),
        padding: const EdgeInsets.all(Sp.l),
        decoration: BoxDecoration(color: Color.alphaBlend(c.withValues(alpha: theme.extension<StatusColors>()!.tintAlpha), theme.colorScheme.surface), border: Border.all(color: c, width: 3), borderRadius: BorderRadius.circular(Rad.lg)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: c, size: 36),
          const SizedBox(width: Sp.m),
          Expanded(child: Text(msg, style: theme.textTheme.titleMedium?.copyWith(color: c))),
        ]),
      );
}
