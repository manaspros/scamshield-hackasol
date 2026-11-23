import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/model_api.dart';
import '../api/model_catalog.dart';
import '../api/text_api.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../l10n/strings_profile.dart';
import '../l10n/strings_setup.dart';
import '../lessons/prefs_store.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/island.dart';
import '../widgets/premium.dart';
import '../widgets/state_message.dart';
import 'model_picker_screen.dart';
import 'page_route.dart';

const _api = MethodChannel('scamshield/api');

/// Setup is one-time onboarding; this reopens it from Settings, Profile or the Home fix button.
Future<void> openSetupPage(BuildContext context) =>
    pushTitled(context, homeT(AppLanguage.of(context), 'set_setup'), const SetupScreen());

/// Setup & permissions: a status ring, the 4 required permissions as cards (the next one open, with numbered
/// steps and one button), then "check it works" tools and the optional AI model.
/// [compact] (onboarding) shows only the ring and the 4 cards.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.compact = false, this.onCount, this.header});
  final bool compact;

  /// Scrolls with the cards (onboarding's title), so nothing is squeezed at large text sizes.
  final Widget? header;

  /// Reports how many of the 4 required steps are on (onboarding's button label).
  final ValueChanged<int>? onCount;
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

/// One required permission.
class _Step {
  const _Step({
    required this.id,
    required this.icon,
    required this.color,
    required this.done,
    required this.action,
    required this.onAction,
    required this.how,
    this.onConfirm,
  });
  final String id, action;
  final IconData icon;
  final Color color;
  final bool done;
  final VoidCallback onAction;
  final VoidCallback? onConfirm;
  final int how; // number of how-to lines (setupT 'how_<id>_<n>')
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  Map<Object?, Object?> _service = {};
  ModelState _model = const ModelState();
  bool _mic = false;
  bool _notif = true;
  bool _nlAccess = false;
  StreamSubscription? _sub;
  bool _loaded = false;
  bool _failed = false;
  final _prefs = PrefsStrings();
  String? _askedFor; // the hand-off the user already tapped; the "Android will ask" card shows only then
  bool _captionsOn = false; // no native check for Live Caption, so the user confirms it
  final _open = <String>{}; // cards the user opened or closed by hand
  final _closed = <String>{};
  bool _micOpen = false;
  int? _lastCount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
    _refresh();
    try {
      _sub = TextApi.events.listen((e) {
        if (!mounted) return;
        if (e['type'] == 'model' || (e['type'] == 'download' && e['status'] == 'INSTALLED')) _refresh();
      }, onError: (_) {});
    } on MissingPluginException {
      // tests
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _loadPrefs() async {
    final caps = await _prefs.get(PrefsStrings.captionsKey);
    if (mounted) setState(() => _captionsOn = caps == '1');
  }

  void _confirmCaptions() {
    setState(() => _captionsOn = true);
    _prefs.set(PrefsStrings.captionsKey, '1');
  }

  Future<void> _refresh() async {
    final Map<Object?, Object?> s, m;
    final bool mic, notif, nl;
    try {
      s = await TextApi.serviceStatus();
      m = await TextApi.modelStatus();
      mic = await TextApi.micPermission();
      notif = await _api.invokeMethod<bool>('perm.notificationsGranted') ?? true;
      nl = await _api.invokeMethod<bool>('perm.notificationAccessGranted') ?? false;
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (mounted) {
      setState(() {
        _loaded = true;
        _failed = false;
        _nlAccess = nl;
        _service = s;
        _model = ModelState.fromMap(m);
        _mic = mic;
        _notif = notif;
      });
    }
  }

  /// Text in the app language; works in callbacks (the build-time dependency comes from [build]).
  String _t(String key, [Map<String, Object?> args = const {}]) => setupT(AppLanguage.code, key, args);

  void _snack(String s) => showIsland(context, s, tone: IslandTone.warning);

  bool get _serviceOn => _service['enabled'] == true && _service['connected'] == true;

  List<_Step> _steps(StatusColors st, Pal p) => [
        _Step(
          id: 'call',
          icon: Icons.call_rounded,
          color: p.accent,
          done: _serviceOn,
          action: _t('open_acc'),
          how: 3,
          onAction: () {
            setState(() => _askedFor = _whyNext());
            TextApi.openAccessibilitySettings();
          },
        ),
        _Step(
          id: 'cap',
          icon: Icons.closed_caption_rounded,
          color: p.accent,
          done: _captionsOn,
          action: _t('open_cap'),
          how: 3,
          onAction: TextApi.openCaptionSettings,
          onConfirm: _confirmCaptions,
        ),
        _Step(
          id: 'notif',
          icon: Icons.notifications_active_rounded,
          color: st.scam,
          done: _notif,
          action: _t('notif_enable'),
          how: 2,
          onAction: () async {
            setState(() => _askedFor = _whyNext());
            await _api.invokeMethod('perm.requestNotifications');
            _refresh();
          },
        ),
        _Step(
          id: 'msg',
          icon: Icons.mark_chat_unread_rounded,
          color: st.suspicious,
          done: _nlAccess,
          action: _t('msg_open'),
          how: 3,
          onAction: () {
            setState(() => _askedFor = _whyNext());
            _api.invokeMethod('perm.openNotificationAccess');
          },
        ),
      ];

  @override
  Widget build(BuildContext context) {
    AppLanguage.of(context); // rebuild when the language changes; strings read it via _t
    final th = Theme.of(context);
    final p = palOf(context);
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    if (_failed || !_loaded) {
      return ListView(padding: const EdgeInsets.all(Sp.l), children: [
        ?widget.header,
        _failed
            ? StateMessage(
                icon: Icons.cloud_off,
                title: _t('fail_title'),
                subtitle: _t('fail_sub'),
                actionLabel: _t('retry'),
                onAction: () {
                  setState(() => _failed = false);
                  _refresh();
                },
              )
            : StateMessage(loading: true, title: _t('checking')),
      ]);
    }
    final steps = _steps(st, p);
    final done = steps.where((s) => s.done).length;
    if (_lastCount != done) {
      _lastCount = done;
      final cb = widget.onCount;
      if (cb != null) WidgetsBinding.instance.addPostFrameCallback((_) => cb(done));
    }
    final next = steps.where((s) => !s.done).map((s) => s.id).firstOrNull;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, widget.compact ? Sp.l : Sp.xxl),
        children: [
          ?widget.header,
          _hero(th, p, st, done),
          if (_whyNext() case final why? when why == _askedFor) ...[const SizedBox(height: Sp.m), _prePermissionCard(why)],
          _head(_t('sec_required')),
          for (final s in steps) ...[
            _card(th, p, st, s, next == s.id),
            const SizedBox(height: Sp.s + 2),
          ],
          if (!widget.compact) ...[
            _head(_t('sec_check')),
            _checks(th, p, st),
            _head(_t('sec_optional')),
            _aiRow(th, p, st),
          ],
          const SizedBox(height: Sp.l),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lock_rounded, size: 18, color: p.muted),
            const SizedBox(width: Sp.s),
            Expanded(child: Text(_t('privacy'), style: th.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: 14))),
          ]),
        ],
      ),
    );
  }

  Widget _head(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.xs, Sp.l + 2, Sp.xs, Sp.s),
        child: Semantics(
          header: true,
          child: Text(s.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: palOf(context).muted, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        ),
      );

  Widget _hero(ThemeData th, Pal p, StatusColors st, int done) {
    final all = done == 4;
    final c = all ? st.safe : st.suspicious;
    final title = all ? _t('hero_all') : done == 0 ? _t('hero_none') : _t('hero_some');
    final left = 4 - done;
    final sub = all ? _t('hero_all_s') : _t(left == 1 ? 'hero_left1' : 'hero_left', {'n': left});
    return AnimatedContainer(
      key: const Key('setup_status'),
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(Sp.l + 4),
      decoration: BoxDecoration(
        color: all ? st.safe.withValues(alpha: p.isDark ? 0.16 : 0.10) : p.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: all ? null : Elev.card(th.brightness),
      ),
      child: Builder(builder: (context) {
        final ring = RingProgress(
          value: done / 4,
          size: 84,
          stroke: 9,
          color: c,
          track: p.isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE0E0E5),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text('$done/4', style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ),
        );
        final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: c)),
          const SizedBox(height: 2),
          Text(sub, style: th.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: 15)),
          Text(_t('count', {'n': done}), key: const Key('setup_count'), style: th.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: 13)),
        ]);
        // Large text: ring above the words so the words keep the full width.
        return _bigText
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ring, const SizedBox(height: Sp.m), text])
            : Row(children: [ring, const SizedBox(width: Sp.l + 2), Expanded(child: text)]);
      }),
    );
  }

  Widget _card(ThemeData th, Pal p, StatusColors st, _Step s, bool isNext) {
    final open = !_closed.contains(s.id) && (_open.contains(s.id) || isNext);
    final c = s.done ? st.safe : s.color;
    void toggle() => setState(() {
          if (open) {
            _open.remove(s.id);
            _closed.add(s.id);
          } else {
            _closed.remove(s.id);
            _open.add(s.id);
          }
        });
    return AnimatedContainer(
      key: Key('setup_step_${s.id}'),
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(RadX.card),
        border: Border.all(color: !s.done && open ? p.accent : Colors.transparent, width: 2),
        boxShadow: Elev.card(th.brightness),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            button: true,
            expanded: open,
            label: '${_t('s_${s.id}')}, ${s.done ? _t('on') : _t('todo')}',
            excludeSemantics: true,
            child: InkWell(
              onTap: toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.m + 2),
                child: Row(children: [
                  IconBadge(icon: s.icon, color: c, size: 42, iconSize: 22),
                  const SizedBox(width: Sp.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_t('s_${s.id}'), style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 17)),
                      Text(s.done ? _t('s_${s.id}_d') : _t('not_on'), style: th.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: 14)),
                      // Large text: the pill goes under the title so the title keeps its width.
                      if (_bigText) ...[const SizedBox(height: Sp.xs), _pill(th, s.done ? _t('on') : _t('todo'), s.done ? st.safe : st.suspicious, done: s.done)],
                    ]),
                  ),
                  if (!_bigText) ...[
                    const SizedBox(width: Sp.s),
                    _pill(th, s.done ? _t('on') : _t('todo'), s.done ? st.safe : st.suspicious, done: s.done),
                  ],
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: p.muted),
                  ),
                ]),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.l),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(_t('why_${s.id}'), style: th.textTheme.bodyMedium?.copyWith(color: p.muted, fontSize: 15, height: 1.45)),
                      const SizedBox(height: Sp.m),
                      Container(
                        padding: const EdgeInsets.all(Sp.m),
                        decoration: BoxDecoration(color: p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F5), borderRadius: BorderRadius.circular(16)),
                        child: Column(children: [
                          for (var i = 1; i <= s.how; i++)
                            Padding(
                              padding: EdgeInsets.only(bottom: i == s.how ? 0 : Sp.s + 2),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                                  child: Text('$i', style: th.textTheme.labelSmall?.copyWith(color: p.onAccent, fontWeight: FontWeight.w800, fontSize: 13)),
                                ),
                                const SizedBox(width: Sp.s + 2),
                                Expanded(child: Text(_t('how_${s.id}_$i'), style: th.textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.35))),
                              ]),
                            ),
                        ]),
                      ),
                      if (!s.done) ...[
                        const SizedBox(height: Sp.m),
                        FilledButton.icon(
                          key: isNext ? const Key('setup_primary') : Key('setup_action_${s.id}'),
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                          onPressed: s.onAction,
                          iconAlignment: IconAlignment.end,
                          icon: const Icon(Icons.north_east_rounded, size: 18),
                          label: Text(s.action, textAlign: TextAlign.center),
                        ),
                        TextButton(
                          key: Key('setup_confirm_${s.id}'),
                          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                          onPressed: s.onConfirm ?? _refresh,
                          child: Text(_t('turned_on')),
                        ),
                      ],
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _pill(ThemeData th, String text, Color c, {required bool done}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Rad.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (done) ...[Icon(Icons.check_rounded, size: 14, color: c), const SizedBox(width: 2)],
          Text(text, style: th.textTheme.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
      );

  bool get _bigText => MediaQuery.textScalerOf(context).scale(1) > 1.3;

  Widget _bubbleButton() => FilledButton.tonal(
        key: const Key('setup_bubble'),
        style: FilledButton.styleFrom(minimumSize: const Size(64, 44), padding: const EdgeInsets.symmetric(horizontal: Sp.l)),
        onPressed: _serviceOn
            ? () async {
                try {
                  await TextApi.testOverlay();
                } on PlatformException catch (e) {
                  _snack('${e.message}');
                }
              }
            : null,
        child: Text(_t('show')),
      );

  Widget _checks(ThemeData th, Pal p, StatusColors st) => PGroup(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.m + 2),
          child: Row(children: [
            IconBadge(icon: Icons.chat_bubble_rounded, color: st.scam, size: 42, iconSize: 22),
            const SizedBox(width: Sp.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_t('bub_row'), style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 17)),
                Text(_t('bub_row_d'), style: th.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: 14)),
                if (_bigText) ...[const SizedBox(height: Sp.s), _bubbleButton()],
              ]),
            ),
            if (!_bigText) _bubbleButton(),
          ]),
        ),
        Divider(height: 1, color: p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF0F0F2)),
        InkWell(
          key: const Key('setup_mic'),
          onTap: () => setState(() => _micOpen = !_micOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.m + 2),
            child: Row(children: [
              IconBadge(icon: Icons.mic_rounded, color: p.accent, size: 42, iconSize: 22),
              const SizedBox(width: Sp.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: Sp.s, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(_t('mic_row'), style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 17)),
                    _pill(th, _t('beta'), p.muted, done: false),
                  ]),
                  Text(_t('mic_row_d'), style: th.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: 14)),
                ]),
              ),
              AnimatedRotation(turns: _micOpen ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(Icons.keyboard_arrow_down_rounded, color: p.muted)),
            ]),
          ),
        ),
        if (_micOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_t('mic_body'), style: th.textTheme.bodyMedium?.copyWith(color: p.muted, fontSize: 15)),
              const SizedBox(height: Sp.m),
              Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
                OutlinedButton.icon(
                  onPressed: _mic ? null : () async => TextApi.requestMic(),
                  icon: Icon(_mic ? Icons.check_rounded : Icons.mic_rounded),
                  label: Text(_t(_mic ? 'mic_ok' : 'mic_allow')),
                ),
                OutlinedButton.icon(
                  onPressed: _mic
                      ? () async {
                          await TextApi.setSettings({'micProbe': true});
                          _snack(_t('mic_armed'));
                        }
                      : null,
                  icon: const Icon(Icons.phone_in_talk_rounded),
                  label: Text(_t('mic_next')),
                ),
                TextButton.icon(onPressed: _mic ? () => TextApi.runMicProbe() : null, icon: const Icon(Icons.play_arrow_rounded), label: Text(_t('mic_now'))),
              ]),
            ]),
          ),
      ]);

  Widget _aiRow(ThemeData th, Pal p, StatusColors st) {
    final cat = ModelCatalogStore.models.value;
    final name = cat.where((c) => c.id == _model.idIn(cat)).map((c) => c.name).firstOrNull;
    return PCard(
      key: const Key('setup_ai'),
      onTap: () async {
        await pushTitled(context, profileT(AppLanguage.code, 'm_title'), const ModelPickerScreen());
        if (mounted) _refresh();
      },
      child: Row(children: [
        IconBadge(icon: Icons.memory_rounded, color: p.onAccent, tint: p.accent, size: 42, iconSize: 22),
        const SizedBox(width: Sp.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_t('ai_row'), style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 17)),
            Text(_model.ready ? _t('ai_ready', {'m': name ?? 'Gemma'}) : _t('ai_none'),
                style: th.textTheme.bodySmall?.copyWith(color: _model.ready ? st.safe : p.muted, fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: p.muted),
      ]),
    );
  }

  /// Why the next system hand-off is needed; null when no hand-off is coming.
  String? _whyNext() => !_serviceOn
      ? _t('why_service')
      : !_captionsOn
          ? null
          : !_notif
              ? _t('why_notif')
              : !_nlAccess
                  ? _t('why_msg')
                  : null;

  /// Shown after the user taps a button that opens an Android permission screen or dialog.
  Widget _prePermissionCard(String why) {
    final th = Theme.of(context);
    final p = palOf(context);
    return Container(
      key: const Key('setup_prepermission_card'),
      padding: const EdgeInsets.all(Sp.l),
      decoration: BoxDecoration(color: p.accentTint, borderRadius: BorderRadius.circular(RadX.card)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_rounded, color: p.accent, size: 26),
        const SizedBox(width: Sp.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_t('pre'), style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: Sp.xs),
            Text(why, style: th.textTheme.bodyMedium?.copyWith(fontSize: 15)),
          ]),
        ),
      ]),
    );
  }
}
