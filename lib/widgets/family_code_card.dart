import 'dart:async';

import 'package:flutter/material.dart';

import '../api/home_api.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';

const _step = 30;

/// Home's lead card. Paired: the live family code (from the same native TOTP as the Family screen)
/// with a countdown bar. Not paired: one call to action. [onOpen] opens the Family screen either way.
class FamilyCodeCard extends StatefulWidget {
  const FamilyCodeCard({super.key, required this.api, required this.onOpen});
  final HomeApi api;
  final VoidCallback onOpen;
  @override
  State<FamilyCodeCard> createState() => _FamilyCodeCardState();
}

class _FamilyCodeCardState extends State<FamilyCodeCard> {
  bool _loaded = false;
  FamilyCode? _code;
  int _remaining = _step;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    final c = await widget.api.familyCode();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _code = c;
      _remaining = c?.remainingSec ?? _step;
    });
    _timer?.cancel();
    if (c == null) return;
    // Local 1 s countdown; native is asked again when the code rolls over.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        _fetch();
      } else if (mounted) {
        setState(() => _remaining--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    String t(String k) => homeT(lang, k);
    final th = Theme.of(context);
    final cs = th.colorScheme;
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    final code = _code;
    return Semantics(
      container: true,
      child: Material(
        color: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.lg), side: BorderSide(color: cs.outline)),
        child: Padding(
          padding: const EdgeInsets.all(Sp.l),
          child: !_loaded
              ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 3)))
              : code == null
                  ? _unpaired(th, t)
                  : _paired(th, t, code, st),
        ),
      ),
    );
  }

  Widget _paired(ThemeData th, String Function(String) t, FamilyCode c, StatusColors st) {
    final cs = th.colorScheme;
    final spaced = c.code.length == 6 ? '${c.code.substring(0, 3)} ${c.code.substring(3)}' : c.code;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.family_restroom, size: 28, color: cs.primary),
        const SizedBox(width: Sp.s),
        // The ask line doubles as the card title: one fewer row keeps all three actions above the fold.
        Expanded(child: Text(t('fam_ask'), key: const Key('home_family_ask'), style: th.textTheme.titleMedium)),
        IconButton(
          key: const Key('home_family_open'),
          tooltip: t('fam_open'),
          onPressed: widget.onOpen,
          icon: const Icon(Icons.chevron_right),
        ),
      ]),
      const SizedBox(height: Sp.s),
      Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(spaced,
              key: const Key('home_family_code'),
              style: AppText.display.copyWith(fontSize: 48, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ),
      const SizedBox(height: Sp.s),
      LinearProgressIndicator(
        key: const Key('home_family_bar'),
        value: _remaining / _step,
        minHeight: 6,
        borderRadius: BorderRadius.circular(Rad.pill),
        color: _remaining <= 5 ? st.scam : cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        semanticsLabel: '$_remaining ${t('fam_sec')}',
      ),
    ]);
  }

  Widget _unpaired(ThemeData th, String Function(String) t) {
    final cs = th.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.family_restroom, size: 40, color: cs.primary),
        const SizedBox(width: Sp.m),
        Expanded(child: Text(t('fam_pair_t'), style: th.textTheme.titleLarge)),
      ]),
      const SizedBox(height: Sp.s),
      Text(t('fam_pair_b'), style: th.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: Sp.l),
      FilledButton.icon(
        key: const Key('home_family_pair'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
        onPressed: widget.onOpen,
        icon: const Icon(Icons.link, size: 28),
        label: Text(t('fam_pair'), textAlign: TextAlign.center),
      ),
    ]);
  }
}
