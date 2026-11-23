import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/text_api.dart';
import '../lessons/prefs_store.dart';
import '../models/verdict.dart';
import '../theme/tokens.dart';
import '../widgets/section_header.dart';
import '../widgets/state_message.dart';
import '../widgets/status_chip.dart';

/// One-time setup checklist: accessibility service, Live Caption, Gemma model, overlay test.
const _api = MethodChannel('scamshield/api');

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
  String? _lang; // null until the user picks one: that is the first-run state
  bool _langLoaded = false;
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
    final lang = await _prefs.get(PrefsStrings.langKey);
    final caps = await _prefs.get(PrefsStrings.captionsKey);
    if (mounted) setState(() { _lang = lang; _captionsOn = caps == '1'; _langLoaded = true; });
  }

  void _pickLang(String code) {
    setState(() => _lang = code);
    _prefs.set(PrefsStrings.langKey, code);
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

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      await TextApi.importModel();
    } on PlatformException catch (e) {
      _snack('Import failed: ${e.message}');
    } finally {
      if (mounted) setState(() => _importing = false);
      _refresh();
    }
  }

  Future<void> _download() async {
    final r = await TextApi.downloadModel();
    if (!mounted) return;
    setState(() => _dl = r);
    if (r['status'] == 'ERROR') _snack('${r['message']}');
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

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

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
                const StatusChip(label: RiskLabel.safe, text: 'हो गया'),
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
              Flexible(child: Text('बाकी है', style: t.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant))),
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
              label: '$title, हो गया',
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

  /// Hindi label with the English wording as a smaller second line.
  Widget _lbl(String hi, String en) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(hi, textAlign: TextAlign.center),
      Text(en,
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
    final serviceOn = _service['enabled'] == true && _service['connected'] == true;
    final modelStatus = '${_model['status'] ?? '…'}';
    final modelReady = modelStatus == 'READY';
    final downloading = _dl['status'] == 'RUNNING' || _dl['status'] == 'PENDING' || _dl['status'] == 'PAUSED';
    // The 4 required steps; model, mic test and bubble test are optional ("उन्नत").
    final doneCount = [serviceOn, _captionsOn, _notif, _nlAccess].where((d) => d).length;

    // One primary action: the next required step that is still pending.
    final Widget primary = !serviceOn
        ? _primary(Icons.accessibility_new, 'कॉल सुरक्षा चालू करें', TextApi.openAccessibilitySettings)
        : !_captionsOn
            ? _primary(Icons.closed_caption, 'मैंने लाइव कैप्शन चालू कर लिया', _confirmCaptions)
            : !_notif
                ? _primary(Icons.notifications_active, 'सूचनाएँ चालू करें', () async {
                    await _api.invokeMethod('perm.requestNotifications');
                    _refresh();
                  })
                : !_nlAccess
                    ? _primary(Icons.mark_email_unread, 'मैसेज सुरक्षा चालू करें',
                        () => _api.invokeMethod('perm.openNotificationAccess'))
                    : _primary(Icons.chat_bubble_outline, 'चेतावनी बबल जाँचें', () async {
                        try { await TextApi.testOverlay(); } on PlatformException catch (e) { _snack('${e.message}'); }
                      });

    final List<Widget> steps;
    if (_failed) {
      steps = [
        StateMessage(
          icon: Icons.cloud_off,
          title: 'सेटअप की स्थिति नहीं मिल सकी',
          subtitle: 'फिर कोशिश करें',
          actionLabel: 'फिर कोशिश करें',
          onAction: () {
            setState(() => _failed = false);
            _refresh();
          },
        ),
      ];
    } else if (!_loaded) {
      steps = const [StateMessage(loading: true, title: 'स्थिति जाँची जा रही है…')];
    } else {
      steps = [
        if (_whyNext(serviceOn) case final why?) _prePermissionCard(why),
        ..._steps(serviceOn),
        _advanced(modelStatus, modelReady, downloading, serviceOn),
      ];
    }

    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(padding: const EdgeInsets.all(Sp.l), children: [
            SectionHeader(
                title: 'सेटअप',
                icon: Icons.checklist,
                subtitle: _loaded ? '$doneCount / 4 ज़रूरी कदम पूरे' : null),
            // First run: the language choice comes first so it is not pushed off-screen
            // at large text sizes; the privacy line follows directly.
            if (_langLoaded && _lang == null) _languageCard(),
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
          title: 'कॉल सुरक्षा चालू करें',
          subtitle: 'Turn on call protection',
          done: serviceOn,
          body: 'Settings → Accessibility → ScamShield call protection → On.\n'
              'ScamShield only reads on-screen caption text. No audio is recorded and nothing leaves your phone.',
          actions: [
            OutlinedButton.icon(
              onPressed: TextApi.openAccessibilitySettings,
              icon: const Icon(Icons.settings),
              label: _lbl('एक्सेसिबिलिटी खोलें', 'Open Accessibility'),
            ),
          ],
        ),
        _step(
          icon: Icons.closed_caption,
          title: 'लाइव कैप्शन चालू करें',
          subtitle: 'Turn on Live Caption (once, it stays on)',
          done: _captionsOn,
          body: 'वॉल्यूम बटन दबाएँ, नीचे कैप्शन का निशान दबाएँ।\n'
              'Press a volume key, tap the captions icon.\n'
              'Pixel: Settings → Sound → Live Caption (also turn on "Caption calls").\n'
              'Samsung: Settings → Accessibility → Hearing enhancements → Live Caption.\n'
              'ScamShield checks every call and tries to switch it on automatically if it is off.',
          actions: [
            OutlinedButton.icon(
              onPressed: TextApi.openCaptionSettings,
              icon: const Icon(Icons.settings),
              label: _lbl('कैप्शन सेटिंग खोलें', 'Open caption settings'),
            ),
          ],
        ),
        _step(
          icon: Icons.notifications_active,
          title: 'अलर्ट सूचनाएँ चालू करें',
          done: _notif,
          body: 'स्कैम मिलने पर फ़ोन पर तुरंत चेतावनी दिखेगी, साथ में "रिपोर्ट करें" बटन।\n'
              'Allow notifications so a scam warning pops up with a Report button.',
          actions: [
            OutlinedButton.icon(
              onPressed: _notif
                  ? null
                  : () async {
                      await _api.invokeMethod('perm.requestNotifications');
                      _refresh();
                    },
              icon: Icon(_notif ? Icons.check : Icons.notifications),
              label: Text(_notif ? 'सूचनाएँ चालू हैं' : 'सूचनाएँ चालू करें', textAlign: TextAlign.center),
            ),
          ],
        ),
        _step(
          icon: Icons.mark_email_unread,
          title: 'मैसेज सुरक्षा चालू करें',
          done: _nlAccess,
          body: 'ScamShield फ़ोन पर आए मैसेज (SMS, WhatsApp) की सूचनाएँ पढ़ता है, सिर्फ़ इसी फ़ोन पर। कुछ भी फ़ोन से बाहर नहीं जाता।\n'
              'ScamShield reads message notifications on the phone only; nothing leaves the phone. '
              'Settings → Notification access → ScamShield → On.',
          actions: [
            OutlinedButton.icon(
              onPressed: () => _api.invokeMethod('perm.openNotificationAccess'),
              icon: Icon(_nlAccess ? Icons.check : Icons.settings),
              label: Text(_nlAccess ? 'चालू है' : 'नोटिफ़िकेशन एक्सेस खोलें', textAlign: TextAlign.center),
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
        title: Text('उन्नत', style: t.textTheme.titleLarge),
        subtitle: Text('Advanced (optional)', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
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
        Icon(Icons.lock_outline, size: 28, color: cs.primary),
        const SizedBox(width: Sp.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('आपकी कॉल रिकॉर्ड नहीं होती। कुछ भी फ़ोन से बाहर नहीं जाता।', style: t.textTheme.titleMedium),
            Text('Calls are not recorded. Nothing leaves your phone.',
                style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }

  /// First run only: one language choice. Setup copy is Hindi for every choice until
  /// Chhattisgarhi and English strings exist for this screen.
  Widget _languageCard() {
    final t = Theme.of(context);
    return Card(
      key: const Key('setup_firstrun_card'),      child: Padding(
        padding: const EdgeInsets.all(Sp.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.translate, size: 40, color: t.colorScheme.primary),
            const SizedBox(width: Sp.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Semantics(header: true, child: Text('भाषा चुनें', style: t.textTheme.titleLarge)),
                Text('Choose language', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ]),
            ),
          ]),
          const SizedBox(height: Sp.m),
          Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
            for (final (code, label) in const [('hi', 'हिन्दी'), ('hne', 'छत्तीसगढ़ी'), ('en', 'English')])
              ChoiceChip(
                key: Key('lang_$code'),
                label: Text(label),
                labelStyle: t.textTheme.bodyLarge,
                selected: _lang == code,
                checkmarkColor: t.colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.l),
                onSelected: (_) => _pickLang(code),
              ),
          ]),
        ]),
      ),
    );
  }

  /// Why the next system hand-off is needed; null when no hand-off is coming.
  String? _whyNext(bool serviceOn) => !serviceOn
      ? 'ScamShield को स्क्रीन पर आने वाले कॉल कैप्शन पढ़ने होते हैं, ताकि ठगी की बात पर तुरंत चेतावनी मिल सके। '
          'Android एक चेतावनी दिखाएगा। आवाज़ रिकॉर्ड नहीं होती।'
      : !_captionsOn
          ? null
          : !_notif
              ? 'ठगी पकड़े जाने पर फ़ोन पर चेतावनी दिखाने के लिए सूचनाओं की अनुमति चाहिए।'
              : !_nlAccess
                  ? 'SMS और WhatsApp के ठग संदेश पकड़ने के लिए ScamShield को आने वाली सूचनाएँ पढ़नी होंगी। यह सिर्फ़ इसी फ़ोन पर होता है।'
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
              Text('अब Android आपसे पूछेगा। यह सामान्य है।', style: t.textTheme.titleLarge),
              Text('Android will now ask you to confirm. This is normal.',
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
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
          title: 'ऑन-डिवाइस AI मॉडल',
          subtitle: 'On-device AI model (Gemma 3 1B)',
          done: modelReady,
          body: 'Status: $modelStatus ${_model['message'] ?? ''}\n'
              '${_model['path'] != null ? 'File: ${_model['path']} (${_model['sizeMb']} MB)\n' : ''}'
              'Without the model, ScamShield still works using rules only.\n'
              'Download it once (~555 MB, Wi-Fi recommended). It keeps downloading in the background.',
          actions: [
            OutlinedButton.icon(
              onPressed: downloading ? null : _download,
              icon: const Icon(Icons.download),
              label: _lbl('मॉडल डाउनलोड करें', 'Download model'),
            ),
            if (downloading)
              OutlinedButton.icon(
                onPressed: () async { await TextApi.cancelDownload(); _refresh(); setState(() => _dl = {}); },
                icon: const Icon(Icons.close),
                label: _lbl('रद्द करें', 'Cancel'),
              ),
            SizedBox(width: double.infinity, child: _downloadProgress()),
            OutlinedButton.icon(
              onPressed: _importing ? null : _import,
              icon: const Icon(Icons.file_open),
              label: _importing
                  ? _lbl('कॉपी हो रहा है…', 'Copying (≈550 MB)…')
                  : _lbl('.task फ़ाइल जोड़ें', 'Import .task file'),
            ),
            TextButton.icon(
              onPressed: () async { await TextApi.loadModel(); _refresh(); },
              icon: const Icon(Icons.refresh),
              label: _lbl('मॉडल फिर लोड करें', 'Reload model'),
            ),
          ],
        ),
        _step(
          icon: Icons.mic,
          title: 'कॉल ऑडियो टेस्ट',
          subtitle: 'Call audio test (can the mic hear calls on this phone?)',
          done: _mic,
          body: 'Allow the microphone, then make a call ON SPEAKER and keep talking for ~15 s.\n'
              'ScamShield records 3 s from each mic source and shows the result in the Live tab '
              '(HAS_AUDIO / SILENT) with a play button. Nothing is uploaded.',
          actions: [
            OutlinedButton.icon(
              onPressed: _mic ? null : () async { await TextApi.requestMic(); },
              icon: Icon(_mic ? Icons.check : Icons.mic),
              label: _mic ? _lbl('माइक्रोफ़ोन की अनुमति मिल गई', 'Microphone allowed') : _lbl('माइक्रोफ़ोन की अनुमति दें', 'Allow microphone'),
            ),
            OutlinedButton.icon(
              onPressed: _mic
                  ? () async {
                      await TextApi.setSettings({'micProbe': true});
                      _snack('Armed: make a call on speaker now. Results appear in the Live tab.');
                    }
                  : null,
              icon: const Icon(Icons.phone_in_talk),
              label: _lbl('अगली कॉल पर जाँचें', 'Test on my next call'),
            ),
            TextButton.icon(
              onPressed: _mic ? () => TextApi.runMicProbe() : null,
              icon: const Icon(Icons.play_arrow),
              label: _lbl('अभी जाँचें (बिना कॉल)', 'Test now (no call)'),
            ),
          ],
        ),
        _step(
          icon: Icons.chat_bubble_outline,
          title: 'चेतावनी बबल जाँचें',
          subtitle: 'Test the warning bubble',
          done: false,
          body: 'Shows a sample SCAM warning on top of the screen, exactly as it appears during a call.',
          actions: [
            OutlinedButton.icon(
              onPressed: serviceOn
                  ? () async {
                      try { await TextApi.testOverlay(); } on PlatformException catch (e) { _snack('${e.message}'); }
                    }
                  : null,
              icon: const Icon(Icons.visibility),
              label: _lbl('टेस्ट बबल दिखाएँ', 'Show test bubble'),
            ),
          ],
        ),
      ];
}
