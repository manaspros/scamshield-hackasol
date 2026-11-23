import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/text_api.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../l10n/strings_profile.dart';
import '../l10n/strings_setup.dart';
import '../lessons/prefs_store.dart';
import '../models/verdict.dart';
import '../theme/tokens.dart';
import '../widgets/state_message.dart';
import '../widgets/island.dart';
import '../widgets/status_chip.dart';
import 'model_picker_screen.dart';
import 'page_route.dart';

/// One-time setup checklist: accessibility service, Live Caption, Gemma model, overlay test.
const _api = MethodChannel('scamshield/api');

/// Setup is one-time onboarding; this reopens it from Settings or the Home fix banner.
Future<void> openSetupPage(BuildContext context) =>
    pushTitled(context, homeT(AppLanguage.of(context), 'set_setup'), const SetupScreen());

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  Map<Object?, Object?> _service = {};
  Map<Object?, Object?> _model = {};
  bool _mic = false;
  bool _notif = true;
  bool _nlAccess = false;
  Map<Object?, Object?> _dl = {};
  StreamSubscription? _sub;
  bool _importing = false;
  bool _loaded = false;
  final _expanded = <String>{}; // done steps the user opened again
  bool _failed = false;
  final _prefs = PrefsStrings();
  String? _askedFor; // the hand-off the user already tapped; the "Android will ask" card shows only then
  bool _captionsOn = false; // no native check for Live Caption, so the user confirms it

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
    _refresh();
    _sub = TextApi.events.listen((e) {
      if (!mounted) return;
      if (e['type'] == 'download') setState(() => _dl = e);
      if (e['type'] == 'model' || (e['type'] == 'download' && e['status'] == 'INSTALLED')) _refresh();
    });
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
    final Map<Object?, Object?> s, m, dl;
    final bool mic, notif, nl;
    try {
      s = await TextApi.serviceStatus();
      m = await TextApi.modelStatus();
      mic = await TextApi.micPermission();
      dl = await TextApi.downloadStatus();
      notif = await _api.invokeMethod<bool>('perm.notificationsGranted') ?? true;
      nl = await _api.invokeMethod<bool>('perm.notificationAccessGranted') ?? false;
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (mounted) setState(() { _loaded = true; _failed = false; _nlAccess = nl; _service = s; _model = m; _mic = mic; _notif = notif; if (dl['status'] != 'IDLE' || _dl.isEmpty) _dl = dl; });
  }

  /// Text in the app language; works in callbacks (the build-time dependency comes from [build]).
  String _t(String key, [Map<String, Object?> args = const {}]) => setupT(AppLanguage.code, key, args);

  /// The small English second line: only in Hindi / Chhattisgarhi mode.
  String? _secondary(String key) => AppLanguage.code == 'en' ? null : _t(key);

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      await TextApi.importModel();
    } on PlatformException catch (e) {
      _snack(_t('import_failed', {'e': e.message}));
    } finally {
      if (mounted) setState(() => _importing = false);
      _refresh();
    }
  }

  /// Opens the model picker (device-aware recommendation, then download); re-reads status on return.
  Future<void> _download() async {
    await pushTitled(context, profileT(AppLanguage.code, 'm_title'), const ModelPickerScreen());
    if (!mounted) return;
    _refresh();
  }

  Widget _downloadProgress() {
    final st = '${_dl['status'] ?? 'IDLE'}';
    if (st == 'IDLE' || st == 'ERROR') {
      return st == 'ERROR'
          ? Text('${_dl['message']}', style: TextStyle(color: Theme.of(context).colorScheme.error))
          : const SizedBox.shrink();
    }
    final done = (_dl['done'] as num?)?.toDouble() ?? 0;
    final total = (_dl['total'] as num?)?.toDouble() ?? 0;
    final frac = total > 0 ? done / total : null;
    String mb(double b) => (b / (1024 * 1024)).toStringAsFixed(0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (st == 'RUNNING' || st == 'PENDING' || st == 'PAUSED')
        LinearProgressIndicator(value: frac),
      const SizedBox(height: Sp.xs),
      Text('$st ${total > 0 ? '${mb(done)} / ${mb(total)} MB' : ''} ${_dl['message'] ?? ''}'),
    ]);
  }

  void _snack(String s) => showIsland(context, s, tone: IslandTone.warning);

  Widget _step({required String title, required bool done, required String body,
      required IconData icon, String? subtitle, List<Widget> actions = const []}) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final open = !done || _expanded.contains(title);
    final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: Sp.m),
      Text(body, style: t.textTheme.bodyLarge),
      if (actions.isNotEmpty) ...[
        const SizedBox(height: Sp.m),
        Wrap(spacing: Sp.s, runSpacing: Sp.s, children: actions),
      ],
    ]);
    // Done: one compact row (icon, title, "हो गया"); tap to show the details again.
    // Pending: full step. State is icon + word, never colour alone.
    final header = done
        ? Row(children: [
            Icon(icon, size: 32, color: cs.primary),
            const SizedBox(width: Sp.m),
            // Wrap: title and chip share a line when they fit, stack at large text sizes.
            Expanded(
              child: Wrap(spacing: Sp.s, runSpacing: Sp.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(title, style: t.textTheme.titleMedium),
                StatusChip(label: RiskLabel.safe, text: _t('done')),
              ]),
            ),
            Icon(open ? Icons.expand_less : Icons.expand_more, size: 32, color: cs.onSurfaceVariant),
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 40, color: cs.primary),
              const SizedBox(width: Sp.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: t.textTheme.titleLarge),
                  if (subtitle != null)
                    Text(subtitle, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
            ]),
            const SizedBox(height: Sp.m),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.radio_button_unchecked, size: 24, color: cs.onSurfaceVariant),
              const SizedBox(width: Sp.s),
              Flexible(child: Text(_t('todo'), style: t.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant))),
            ]),
          ]);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(done ? Sp.m : Sp.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (done)
            Semantics(
              button: true,
              expanded: open,
              label: _t('done_sem', {'title': title}),
              excludeSemantics: true,
              onTap: () => setState(() => open ? _expanded.remove(title) : _expanded.add(title)),
              child: InkWell(
                onTap: () => setState(() => open ? _expanded.remove(title) : _expanded.add(title)),
                child: ConstrainedBox(constraints: const BoxConstraints(minHeight: kTouch), child: header),
              ),
            )
          else
            header,
          if (open) details,
        ]),
      ),
    );
  }

  /// Label in the app language; in hi/hne the English wording follows as a smaller second line.
  Widget _lbl(String key) {
    final small = Theme.of(context).textTheme.bodySmall;
    final sec = _secondary('${key}_s');
    if (sec == null) return Text(_t(key), textAlign: TextAlign.center);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_t(key), textAlign: TextAlign.center),
      Text(sec,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: small?.fontSize, fontWeight: FontWeight.w400)),
    ]);
  }

  Widget _primary(IconData icon, String label, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.l),
        child: FilledButton.icon(
          key: const Key('setup_primary'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
          onPressed: onTap,
          icon: Icon(icon, size: 28),
          label: Text(label, textAlign: TextAlign.center),
        ),
      );

  @override
  Widget build(BuildContext context) {
    AppLanguage.of(context); // rebuild when the language changes; strings read it via _t
    final serviceOn = _service['enabled'] == true && _service['connected'] == true;
    final modelStatus = '${_model['status'] ?? '…'}';
    final modelReady = modelStatus == 'READY';
    final downloading = _dl['status'] == 'RUNNING' || _dl['status'] == 'PENDING' || _dl['status'] == 'PAUSED';
    // The 4 required steps; model, mic test and bubble test are optional ("उन्नत").
    final doneCount = [serviceOn, _captionsOn, _notif, _nlAccess].where((d) => d).length;

    // One primary action: the next required step that is still pending.
    final Widget primary = !serviceOn
        ? _primary(Icons.accessibility_new, _t('call_title'), () {
            setState(() => _askedFor = _whyNext(serviceOn));
            TextApi.openAccessibilitySettings();
          })
        : !_captionsOn
            ? _primary(Icons.closed_caption, _t('prim_cap'), _confirmCaptions)
            : !_notif
                ? _primary(Icons.notifications_active, _t('notif_enable'), () async {
                    setState(() => _askedFor = _whyNext(serviceOn));
                    await _api.invokeMethod('perm.requestNotifications');
                    _refresh();
                  })
                : !_nlAccess
                    ? _primary(Icons.mark_email_unread, _t('msg_title'),
                        () {
                          setState(() => _askedFor = _whyNext(serviceOn));
                          _api.invokeMethod('perm.openNotificationAccess');
                        })
                    : _primary(Icons.chat_bubble_outline, _t('bub_title'), () async {
                        try { await TextApi.testOverlay(); } on PlatformException catch (e) { _snack('${e.message}'); }
                      });

    final List<Widget> steps;
    if (_failed) {
      steps = [
        StateMessage(
          icon: Icons.cloud_off,
          title: _t('fail_title'),
          subtitle: _t('fail_sub'),
          actionLabel: _t('retry'),
          onAction: () {
            setState(() => _failed = false);
            _refresh();
          },
        ),
      ];
    } else if (!_loaded) {
      steps = [StateMessage(loading: true, title: _t('checking'))];
    } else {
      steps = [
        if (_whyNext(serviceOn) case final why? when why == _askedFor) _prePermissionCard(why),
        ..._steps(serviceOn),
        _advanced(modelStatus, modelReady, downloading, serviceOn),
      ];
    }

    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(padding: const EdgeInsets.fromLTRB(Sp.l, Sp.l, Sp.l, Sp.xxl), children: [
            // The AppBar already says "सेटअप"; the progress counter leads the list.
            if (_loaded)
              Padding(
                padding: const EdgeInsets.only(bottom: Sp.m),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(_t('count', {'n': doneCount}),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: Sp.s),
                  LinearProgressIndicator(value: doneCount / 4, minHeight: 6, borderRadius: BorderRadius.circular(Rad.pill)),
                ]),
              ),
            _privacyLine(),
            ...steps,
          ]),
        ),
      ),
      if (_loaded && !_failed) primary,
    ]);
  }

  List<Widget> _steps(bool serviceOn) => [
        _step(
          icon: Icons.accessibility_new,
          title: _t('call_title'),
          subtitle: _secondary('call_s'),
          done: serviceOn,
          body: _t('call_body'),
          actions: [
            OutlinedButton.icon(
              onPressed: TextApi.openAccessibilitySettings,
              icon: const Icon(Icons.settings),
              label: _lbl('open_acc'),
            ),
          ],
        ),
        _step(
          icon: Icons.closed_caption,
          title: _t('cap_title'),
          subtitle: _secondary('cap_s'),
          done: _captionsOn,
          body: _t('cap_body'),
          actions: [
            OutlinedButton.icon(
              onPressed: TextApi.openCaptionSettings,
              icon: const Icon(Icons.settings),
              label: _lbl('open_cap'),
            ),
          ],
        ),
        _step(
          icon: Icons.notifications_active,
          title: _t('notif_title'),
          done: _notif,
          body: _t('notif_body'),
          actions: [
            OutlinedButton.icon(
              onPressed: _notif
                  ? null
                  : () async {
                      await _api.invokeMethod('perm.requestNotifications');
                      _refresh();
                    },
              icon: Icon(_notif ? Icons.check : Icons.notifications),
              label: Text(_t(_notif ? 'notif_on' : 'notif_enable'), textAlign: TextAlign.center),
            ),
          ],
        ),
        _step(
          icon: Icons.mark_email_unread,
          title: _t('msg_title'),
          done: _nlAccess,
          body: _t('msg_body'),
          actions: [
            OutlinedButton.icon(
              onPressed: () => _api.invokeMethod('perm.openNotificationAccess'),
              icon: Icon(_nlAccess ? Icons.check : Icons.settings),
              label: Text(_t(_nlAccess ? 'msg_on' : 'msg_open'), textAlign: TextAlign.center),
            ),
          ],
        ),
      ];

  /// Optional items (model, mic test, bubble test): closed by default, not counted.
  Widget _advanced(String modelStatus, bool modelReady, bool downloading, bool serviceOn) {
    final t = Theme.of(context);
    return Theme(
      data: t.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('setup_advanced'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        minTileHeight: kTouch,
        leading: Icon(Icons.tune, size: 32, color: t.colorScheme.onSurface),
        title: Text(_t('adv'), style: t.textTheme.titleLarge),
        subtitle: AppLanguage.code == 'en'
            ? null
            : Text(_t('adv_s'), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        children: _optionalSteps(modelStatus, modelReady, downloading, serviceOn),
      ),
    );
  }

  Widget _privacyLine() {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.l),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lock_outline, size: 28, color: cs.onSurfaceVariant),
        const SizedBox(width: Sp.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_t('privacy'), style: t.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
            if (_secondary('privacy_s') case final sub?)
              Text(sub, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }

  /// Why the next system hand-off is needed; null when no hand-off is coming.
  String? _whyNext(bool serviceOn) => !serviceOn
      ? _t('why_service')
      : !_captionsOn
          ? null
          : !_notif
              ? _t('why_notif')
              : !_nlAccess
                  ? _t('why_msg')
                  : null;

  /// Shown before the button that opens an Android permission screen or dialog.
  Widget _prePermissionCard(String why) {
    final t = Theme.of(context);
    return Card(
      key: const Key('setup_prepermission_card'),
      child: Padding(
        padding: const EdgeInsets.all(Sp.l),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 40, color: t.colorScheme.primary),
          const SizedBox(width: Sp.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_t('pre'), style: t.textTheme.titleLarge),
              if (_secondary('pre_s') case final sub?)
                Text(sub, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: Sp.s),
              Text(why, style: t.textTheme.bodyLarge),
            ]),
          ),
        ]),
      ),
    );
  }

  List<Widget> _optionalSteps(String modelStatus, bool modelReady, bool downloading, bool serviceOn) => [
        _step(
          icon: Icons.memory,
          title: _t('model_title'),
          subtitle: _secondary('model_s'),
          done: modelReady,
          body: _t('model_status', {'s': modelStatus, 'm': _model['message'] ?? ''}) +
              (_model['path'] != null ? _t('model_file', {'p': _model['path'], 'mb': _model['sizeMb']}) : '') +
              _t('model_body'),
          actions: [
            OutlinedButton.icon(
              onPressed: downloading ? null : _download,
              icon: const Icon(Icons.download),
              label: _lbl('model_dl'),
            ),
            if (downloading)
              OutlinedButton.icon(
                onPressed: () async { await TextApi.cancelDownload(); _refresh(); setState(() => _dl = {}); },
                icon: const Icon(Icons.close),
                label: _lbl('cancel'),
              ),
            SizedBox(width: double.infinity, child: _downloadProgress()),
            OutlinedButton.icon(
              onPressed: _importing ? null : _import,
              icon: const Icon(Icons.file_open),
              label: _importing
                  ? _lbl('copying')
                  : _lbl('import'),
            ),
            TextButton.icon(
              onPressed: () async { await TextApi.loadModel(); _refresh(); },
              icon: const Icon(Icons.refresh),
              label: _lbl('reload'),
            ),
          ],
        ),
        _step(
          icon: Icons.mic,
          title: _t('mic_title'),
          subtitle: _secondary('mic_s'),
          done: _mic,
          body: _t('mic_body'),
          actions: [
            OutlinedButton.icon(
              onPressed: _mic ? null : () async { await TextApi.requestMic(); },
              icon: Icon(_mic ? Icons.check : Icons.mic),
              label: _lbl(_mic ? 'mic_ok' : 'mic_allow'),
            ),
            OutlinedButton.icon(
              onPressed: _mic
                  ? () async {
                      await TextApi.setSettings({'micProbe': true});
                      _snack(_t('mic_armed'));
                    }
                  : null,
              icon: const Icon(Icons.phone_in_talk),
              label: _lbl('mic_next'),
            ),
            TextButton.icon(
              onPressed: _mic ? () => TextApi.runMicProbe() : null,
              icon: const Icon(Icons.play_arrow),
              label: _lbl('mic_now'),
            ),
          ],
        ),
        _step(
          icon: Icons.chat_bubble_outline,
          title: _t('bub_title'),
          subtitle: _secondary('bub_s'),
          done: false,
          body: _t('bub_body'),
          actions: [
            OutlinedButton.icon(
              onPressed: serviceOn
                  ? () async {
                      try { await TextApi.testOverlay(); } on PlatformException catch (e) { _snack('${e.message}'); }
                    }
                  : null,
              icon: const Icon(Icons.visibility),
              label: _lbl('bub_show'),
            ),
          ],
        ),
      ];
}
