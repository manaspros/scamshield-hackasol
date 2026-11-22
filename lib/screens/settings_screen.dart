import 'package:flutter/material.dart';

import '../api/text_api.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<Object?, Object?> _s = {};
  final _pkgCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    TextApi.getSettings().then((s) {
      if (!mounted) return;
      setState(() => _s = s);
      _pkgCtrl.text = '${s['captionPackages'] ?? ''}';    });
  }

  Future<void> _set(String key, Object? value) async {
    final s = await TextApi.setSettings({key: value});
    if (mounted) setState(() => _s = s);
  }

  Widget _switch(String key, String title, String subtitle) => SwitchListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        value: _s[key] == true,
        onChanged: (v) => _set(key, v),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      _switch('useLlm', 'Use on-device Gemma', 'Off = rules only (fastest, for low-end phones)'),
      _switch('overlayEnabled', 'Show warning bubble', 'Floating "This statement is…" widget during calls'),
      _switch('autoEnableCaptions', 'Auto-turn-on Live Caption', 'If no captions appear 6 s into a call'),
      _switch('ocrFallback', 'Screen-reading fallback (OCR)',
          'If the caption window hides its text, read it from a screenshot (Android 11+)'),
      _switch('inCallSignals', 'In-call scam signals',
          'Warn if an OTP arrives, or a UPI/bank/AnyDesk app is opened, during a call'),
      _switch('micProbe', 'Call audio test on next call (experimental)',
          'Tests 3 s from every mic source at the start of the next call, then switches itself off'),
      _switch('wifiOnly', 'Download model on Wi-Fi only', 'The model is ~555 MB'),
      _switch('discoveryMode', 'Discovery mode (debug)',
          'Log text of every window to the Live tab to find your phone\'s caption package'),
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _pkgCtrl,
          decoration: const InputDecoration(
            labelText: 'Caption source packages (comma separated)',
            helperText: 'Found with discovery mode. Packages containing "caption" are always included.',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => _set('captionPackages', v),
        ),
      ),
    ]);
  }
}
