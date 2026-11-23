import 'package:flutter/material.dart';

import '../api/home_api.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../models/verdict.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/press_scale.dart';
import '../widgets/family_code_card.dart';
import 'evidence_screen.dart';
import 'family_screen.dart';
import 'knowledge_screen.dart';
import 'page_route.dart';
import 'past_alerts_screen.dart';
import 'setup_screen.dart';

/// The main page: protection status, the family code, then three actions.
/// Setup lives in onboarding and Settings; here a failing permission is one compact "Fix" row.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.api = const HomeApi()});
  final HomeApi api;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Protection? _prot;
  int _familyEpoch = 0; // bumped after the Family screen closes so the card re-reads the pairing

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final p = await widget.api.protection();
    if (mounted) setState(() => _prot = p);
  }

  /// Opens [page] and re-reads status on return (the user may have changed a permission there).
  Future<void> _open(String title, Widget page) async {
    await pushTitled(context, title, page);
    if (!mounted) return;
    setState(() => _familyEpoch++);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    String t(String k) => homeT(lang, k);
    final th = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.l, Sp.l, Sp.l, Sp.xxl),
      children: [
        _hero(th, lang),
        const SizedBox(height: Sp.l),
        FamilyCodeCard(
          key: ValueKey(_familyEpoch),
          api: widget.api,
          onOpen: () => _open(t('fam_title'), const FamilyScreen()),
        ),
        const SizedBox(height: Sp.l),
        FilledButton.icon(
          key: const Key('home_make_evidence'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
          onPressed: () => _open(t('ev_title'), EvidenceScreen(api: widget.api)),
          icon: const Icon(Icons.inventory_2, size: 28),
          label: Text(t('act_evidence'), textAlign: TextAlign.center),
        ),
        const SizedBox(height: Sp.m),
        // Side by side on a normal phone so all three actions fit under the family card; stacked at large text.
        _tiles(context, [
          _HomeTile(
            key: const Key('home_about_me'),
            icon: Icons.hub_outlined,
            label: t('act_know'),
            onTap: () => _open(t('kn_title'), KnowledgeScreen(api: widget.api)),
          ),
          _HomeTile(
            key: const Key('home_past_alerts'),
            icon: Icons.history,
            label: t('act_alerts'),
            onTap: () => _open(t('al_title'), PastAlertsScreen(api: widget.api)),
          ),
        ]),
      ],
    );
  }

  Widget _tiles(BuildContext context, List<Widget> tiles) {
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(children: [tiles[0], const SizedBox(height: Sp.m), tiles[1]]);
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: tiles[0]),
        const SizedBox(width: Sp.m),
        Expanded(child: tiles[1]),
      ]),
    );
  }

  /// Green "You're protected", or amber with the first thing that is off and one Fix button.
  Widget _hero(ThemeData th, String lang) {
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    final p = _prot;
    final off = p?.firstOff;
    final ok = p != null && p.known && off == null;
    final label = off != null ? RiskLabel.suspicious : RiskLabel.safe;
    final color = st.solid(label);
    final text = p == null || (off == null && !ok)
        ? homeT(lang, 'prot_checking')
        : off != null
            ? homeT(lang, 'prot_off', {'what': homeT(lang, off)})
            : homeT(lang, 'prot_ok');
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const Key('home_hero'),
        padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.m),
        decoration: ShapeDecoration(
          color: st.tintOver(label, th.colorScheme.surface),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.lg), side: BorderSide(color: color)),
        ),
        // Column, not Row: at large text the Fix button would squeeze the status line to nothing.
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(off != null ? Icons.warning_amber_rounded : Icons.verified_user, size: 32, color: color),
            const SizedBox(width: Sp.m),
            Expanded(child: Text(text, key: const Key('home_hero_text'), style: th.textTheme.titleMedium?.copyWith(color: color))),
          ]),
          if (off != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('home_fix'),
                style: TextButton.styleFrom(minimumSize: const Size(kTouch, kTouch), foregroundColor: color),
                onPressed: () async {
                  await openSetupPage(context);
                  _refresh();
                },
                child: Text(homeT(lang, 'fix')),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Half-width action: icon over a short label, same card shape as ActionTile.
class _HomeTile extends StatelessWidget {
  const _HomeTile({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final cs = th.colorScheme;
    return PressScale(
      enabled: true,
      child: Semantics(
        button: true,
        child: Material(
          color: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.lg), side: BorderSide(color: cs.outline)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Sp.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 32, color: cs.primary),
                const SizedBox(height: Sp.s),
                Text(label, style: th.textTheme.titleSmall),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
