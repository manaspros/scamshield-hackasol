import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/text_api.dart';

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
  Map<Object?, Object?> _dl = {};
  StreamSubscription? _sub;
  bool _importing = false;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  Future<void> _refresh() async {
    final s = await TextApi.serviceStatus();
    final m = await TextApi.modelStatus();
    final mic = await TextApi.micPermission();
    final dl = await TextApi.downloadStatus();
    final notif = await _api.invokeMethod<bool>('perm.notificationsGranted') ?? true;
    if (mounted) setState(() { _service = s; _model = m; _mic = mic; _notif = notif; if (dl['status'] != 'IDLE' || _dl.isEmpty) _dl = dl; });
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
        LinearProgressIndicator(value: frac, minHeight: 8, borderRadius: BorderRadius.circular(4)),
      const SizedBox(height: 4),
      Text('$st ${total > 0 ? '${mb(done)} / ${mb(total)} MB' : ''} ${_dl['message'] ?? ''}'),
    ]);
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Widget _step({required int n, required String title, required bool done, required String body,
      List<Widget> actions = const [], IconData? icon}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: done ? Colors.green : Theme.of(context).colorScheme.secondaryContainer,
              child: done
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : icon != null ? Icon(icon, size: 18) : Text('$n'),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: icon != null
                ? Theme.of(context).textTheme.titleLarge
                : Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 8),
          Text(body),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serviceOn = _service['enabled'] == true && _service['connected'] == true;
    final modelStatus = '${_model['status'] ?? '…'}';
    final modelReady = modelStatus == 'READY';
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        _step(
          n: 1,
          title: 'Turn on call protection',
          done: serviceOn,
          body: 'Settings → Accessibility → ScamShield call protection → On.\n'
              'ScamShield only reads on-screen caption text. No audio is recorded and nothing leaves your phone.',
          actions: [
            FilledButton.tonal(onPressed: TextApi.openAccessibilitySettings, child: const Text('Open Accessibility')),
          ],
        ),
        _step(
          n: 2,
          title: 'Turn on Live Caption (once — it stays on)',
          done: false,
          body: 'Pixel: Settings → Sound → Live Caption (also turn on "Caption calls").\n'
              'Samsung: Settings → Accessibility → Hearing enhancements → Live Caption.\n'
              'Or press a volume key and tap the captions icon under the volume slider.\n'
              'ScamShield checks every call and tries to switch it on automatically if it is off.',
          actions: [
            FilledButton.tonal(onPressed: TextApi.openCaptionSettings, child: const Text('Open caption settings')),
          ],
        ),
        _step(
          n: 3,
          title: 'On-device AI model (Gemma 3 1B)',
          done: modelReady,
          body: 'Status: $modelStatus ${_model['message'] ?? ''}\n'
              '${_model['path'] != null ? 'File: ${_model['path']} (${_model['sizeMb']} MB)\n' : ''}'
              'Without the model, ScamShield still works using rules only.\n'
              'Download it once (~555 MB, Wi-Fi recommended). It keeps downloading in the background.',
          actions: [
            FilledButton.icon(
              onPressed: (_dl['status'] == 'RUNNING' || _dl['status'] == 'PENDING' || _dl['status'] == 'PAUSED')
                  ? null
                  : _download,
              icon: const Icon(Icons.download),
              label: const Text('Download model'),
            ),
            if (_dl['status'] == 'RUNNING' || _dl['status'] == 'PENDING' || _dl['status'] == 'PAUSED')
              OutlinedButton(
                onPressed: () async { await TextApi.cancelDownload(); _refresh(); setState(() => _dl = {}); },
                child: const Text('Cancel'),
              ),
            SizedBox(width: double.infinity, child: _downloadProgress()),
            FilledButton.tonal(
              onPressed: _importing ? null : _import,
              child: Text(_importing ? 'Copying (≈550 MB)…' : 'Import .task file'),
            ),
            OutlinedButton(
              onPressed: () async { await TextApi.loadModel(); _refresh(); },
              child: const Text('Reload model'),
            ),
          ],
        ),
        _step(
          n: 4,
          title: 'Call audio test (can the mic hear calls on this phone?)',
          done: _mic,
          body: 'Allow the microphone, then make a call ON SPEAKER and keep talking for ~15 s.\n'
              'ScamShield records 3 s from each mic source and shows the result in the Live tab '
              '(HAS_AUDIO / SILENT) with a play button. Nothing is uploaded.',
          actions: [
            FilledButton.tonal(
              onPressed: _mic ? null : () async { await TextApi.requestMic(); },
              child: Text(_mic ? 'Microphone allowed' : 'Allow microphone'),
            ),
            FilledButton(
              onPressed: _mic
                  ? () async {
                      await TextApi.setSettings({'micProbe': true});
                      _snack('Armed: make a call on speaker now. Results appear in the Live tab.');
                    }
                  : null,
              child: const Text('Test on my next call'),
            ),
            OutlinedButton(
              onPressed: _mic ? () => TextApi.runMicProbe() : null,
              child: const Text('Test now (no call)'),
            ),
          ],
        ),
        _step(
          n: 5,
          icon: Icons.notifications_active,
          title: 'अलर्ट सूचनाएँ चालू करें',
          done: _notif,
          body: 'स्कैम मिलने पर फ़ोन पर तुरंत चेतावनी दिखेगी, साथ में "रिपोर्ट करें" बटन।\n'
              'Allow notifications so a scam warning pops up with a Report button.',
          actions: [
            FilledButton.icon(
              onPressed: _notif
                  ? null
                  : () async {
                      await _api.invokeMethod('perm.requestNotifications');
                      _refresh();
                    },
              icon: Icon(_notif ? Icons.check : Icons.notifications),
              label: Text(_notif ? 'सूचनाएँ चालू हैं' : 'सूचनाएँ चालू करें'),
            ),
          ],
        ),
        _step(
          n: 6,
          title: 'Test the warning bubble',
          done: false,
          body: 'Shows a sample SCAM warning on top of the screen, exactly as it appears during a call.',
          actions: [
            FilledButton(
              onPressed: serviceOn
                  ? () async {
                      try { await TextApi.testOverlay(); } on PlatformException catch (e) { _snack('${e.message}'); }
                    }
                  : null,
              child: const Text('Show test bubble'),
            ),
          ],
        ),
      ]),
    );
  }
}
