import 'package:flutter/material.dart';

import '../api/text_api.dart';
import '../models/verdict.dart';
import '../widgets/verdict_card.dart';

/// Paste any SMS / WhatsApp message / call sentence and run the on-device Text API.
class TryApiScreen extends StatefulWidget {
  const TryApiScreen({super.key});
  @override
  State<TryApiScreen> createState() => _TryApiScreenState();
}

class _TryApiScreenState extends State<TryApiScreen> {
  final _ctrl = TextEditingController();
  final _history = <Verdict>[];
  bool _busy = false;
  String? _error;

  static const samples = [
    'Sir aapke phone pe OTP aaya hoga, woh bata dijiye',
    'मैं सीबीआई से बोल रहा हूं, आप डिजिटल अरेस्ट में हैं, किसी को मत बताना',
    'Your FedEx parcel has illegal drugs, press 1 to talk to customs',
    'SBI se bol raha hoon, aapka KYC update pending hai',
    'Beta khana kha liya? Kal shaam ko milte hain',
    'Please install AnyDesk so I can process your refund',
  ];

  Future<void> _run() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final v = await TextApi.classify(text);
      setState(() => _history.insert(0, v));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
        controller: _ctrl,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'Message or call sentence (English / हिंदी / Hinglish)',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final s in samples)
          ActionChip(
            label: Text(s.length > 28 ? '${s.substring(0, 28)}…' : s),
            onPressed: () => _ctrl.text = s,
          ),
      ]),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _busy ? null : _run,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.shield),
        label: Text(_busy ? 'Analysing on device…' : 'Analyse'),
      ),
      if (_error != null) Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
      const SizedBox(height: 12),
      for (final v in _history) VerdictCard(verdict: v),
    ]);
  }
}
