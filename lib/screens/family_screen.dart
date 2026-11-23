import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_language.dart';
import '../theme/app_theme.dart' show StatusColors;
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import '../widgets/state_message.dart';

/// Family code: pair two phones with a shared secret, then compare a rotating
/// 6-digit code against what a caller claims. Codes are computed natively.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({
    super.key,
    this.channel = const MethodChannel('scamshield/family'),
    this.initialLang,
  });
  final MethodChannel channel;

  /// Null = follow the app-wide language.
  final String? initialLang;
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
    'unpairTitle': 'जोड़ी हटाएँ?',
    'unpairBody': 'दोनों फ़ोन को फिर से जोड़ना होगा।',
    'cancel': 'रद्द करें',
    'remove': 'हटाएँ',
    'err': 'कोड नहीं मिल सका। फिर कोशिश करें।',
    'retry': 'फिर कोशिश करें',
    'loading': 'कोड जाँचा जा रहा है…',
    'how': 'परिवार के फ़ोन पर भी यही कोड आता है। कॉल पर कोई अपना होने का दावा करे तो कोड पूछें।',
    'askCaller': 'फ़ोन करने वाले से यह कोड पूछें',
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
    'unpairTitle': 'जोड़ी हटावव?',
    'unpairBody': 'दूनो फ़ोन ल फेर जोड़ना परही।',
    'cancel': 'रद्द करव',
    'remove': 'हटावव',
    'err': 'कोड नइ मिलिस। फेर कोशिश करव।',
    'retry': 'फेर कोशिश करव',
    'loading': 'कोड जाँचत हे…',
    'how': 'परिवार के फ़ोन म घलो इही कोड आथे। कॉल म कोनो अपन होय के दावा करय त कोड पूछव।',
    'askCaller': 'फ़ोन करइया ले ए कोड पूछव',
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
    'unpairTitle': 'Remove pairing?',
    'unpairBody': 'Both phones must pair again.',
    'cancel': 'Cancel',
    'remove': 'Remove',
    'err': 'Could not get the code. Try again.',
    'retry': 'Try again',
    'loading': 'Checking the code…',
    'how': 'Your family member\'s phone shows the same code. If a caller claims to be family, ask for it.',
    'askCaller': 'Ask the caller for this code',
  },
};

/// The string tables, for the l10n key-parity test.
@visibleForTesting
const familyStrings = _s;

class _FamilyScreenState extends State<FamilyScreen> {
  // The language chips are a TEMPORARY per-view override: _lang starts from the app-wide language
  // (an explicit initialLang wins for the first read) and re-syncs whenever the global value changes.
  late String _lang = widget.initialLang ?? AppLanguage.code;
  String? _lastGlobal;
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

  @override
  void dispose() {
    _timer?.cancel();
    _field.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final st = await widget.channel.invokeMapMethod<String, Object?>('family.status');
      if (st?['paired'] == true) return await _startCode();
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

  /// Cancel is the focused default; the destructive action is outlined in the scam colour.
  Future<void> _confirmUnpair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scam = Theme.of(ctx).extension<StatusColors>()!.scam;
        return AlertDialog(
          title: Text(t('unpairTitle')),
          content: Text(t('unpairBody')),
          actions: [
            OutlinedButton(
              key: const Key('family_unpair_confirm'),
              style: OutlinedButton.styleFrom(foregroundColor: scam, side: BorderSide(color: scam, width: 2)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t('remove'), textAlign: TextAlign.center),
            ),
            FilledButton(
              key: const Key('family_unpair_cancel'),
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t('cancel'), textAlign: TextAlign.center),
            ),
          ],
        );
      },
    );
    if (ok == true) await _unpair();
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
              checkmarkColor: Theme.of(context).colorScheme.primary,
              onSelected: (_) => setState(() => _lang = code),
            ),
        ]),
        const SizedBox(height: Sp.m),
        // Intro only on the first screens; later stages need the room for the code.
        if (_stage == _Stage.loading || _stage == _Stage.choose)
          // The AppBar already carries the title; only the one-line intro stays.
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.m),
            child: Text(t('intro'), style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        if (_stage == _Stage.choose)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.l),
            child: Text(t('how'), key: const Key('family_how'), style: theme.textTheme.bodyLarge),
          ),
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

  Widget _big(Key key, IconData icon, String label, VoidCallback onTap, {Color? bg}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Sp.m),
        // A coloured answer (yes/no) is outlined so two equal choices never look like two primaries.
        child: bg != null
            ? OutlinedButton.icon(
                key: key,
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                    foregroundColor: bg,
                    side: BorderSide(color: bg, width: 2),
                    minimumSize: const Size.fromHeight(kTouch)),
                icon: Icon(icon, size: 32),
                label: Text(label, textAlign: TextAlign.center),
              )
            : FilledButton.icon(
                key: key,
                onPressed: onTap,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
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
          onPressed: _confirmUnpair,
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
      // Replaces the "code right now" label: the ring already shows it is live, and the room is needed at 2x.
      Text(t('askCaller'), key: const Key('family_ask_caller'), style: theme.textTheme.titleMedium),
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
      _big(const Key('family_yes'), Icons.check_circle, t('yes'), () => setState(() => _match = true), bg: yes),
      _big(const Key('family_no'), Icons.cancel, t('no'), () => setState(() => _match = false), bg: no),
      if (_match == true)
        _banner(const Key('family_yes_msg'), Icons.check_circle, t('yesMsg'), yes, theme),
      if (_match == false)
        _banner(const Key('family_no_warning'), Icons.warning_amber_rounded, t('noMsg'), no, theme),
      const SizedBox(height: Sp.s),
      TextButton.icon(
        key: const Key('family_unpair'),
        onPressed: _confirmUnpair,
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
