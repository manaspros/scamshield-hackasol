import 'dart:async';

import 'package:flutter/material.dart';

import '../api/text_api.dart';
import '../models/verdict.dart';
import '../widgets/verdict_card.dart';

/// Live view of the caption pipeline: raw captions, statements, verdicts, discovery output.
class LiveFeedScreen extends StatefulWidget {
  const LiveFeedScreen({super.key});
  @override
  State<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _FeedItem {
  _FeedItem.verdict(this.verdict) : text = null, kind = 'verdict', path = null;
  _FeedItem.note(this.kind, this.text, {this.path}) : verdict = null;
  final String kind;
  final String? text;
  final Verdict? verdict;
  final String? path; // playable probe recording
}

class _LiveFeedScreenState extends State<LiveFeedScreen> with AutomaticKeepAliveClientMixin {
  StreamSubscription? _sub;
  final _items = <_FeedItem>[];
  String _caption = '';
  bool _inCall = false;
  double _callRisk = 0;
  RiskLabel _callLevel = RiskLabel.safe;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sub = TextApi.events.listen(_onEvent);
  }

  void _add(_FeedItem i) {
    _items.insert(0, i);
    if (_items.length > 200) _items.removeLast();
  }

  void _onEvent(Map<Object?, Object?> e) {
    setState(() {
      switch (e['type']) {
        case 'caption':
          _caption = '${e['text']}  [${e['via']}]';
        case 'statement':
          _add(_FeedItem.note('statement', '${e['text']}'));
        case 'verdict':
          final v = Verdict.fromMap(e);
          if (!v.preliminary) {
            _callRisk = ((e['callRisk'] as num?) ?? 0).toDouble();
            _callLevel = parseLabel(e['callLevel']);
          }
          _add(_FeedItem.verdict(v));
        case 'call':
          _inCall = e['active'] == true;
          _add(_FeedItem.note('call', _inCall ? '📞 Call started' : '📴 Call ended'));
          if (_inCall) { _callRisk = 0; _callLevel = RiskLabel.safe; }
        case 'signal':
          _add(_FeedItem.note('signal', '⚡ In-call signal: ${e['kind']} (${e['trigger']})'));
        case 'mic_probe':
          final status = '${e['status']}';
          final db = e['dbfs'] is num ? ' ${(e['dbfs'] as num).toStringAsFixed(1)} dBFS, peak ${e['peak']}' : '';
          final icon = status == 'HAS_AUDIO' ? '✅' : (status == 'SILENT' ? '🔇' : '⚠️');
          _add(_FeedItem.note('mic', '$icon Mic ${e['source']}: $status$db${e['detail'] != null ? ' — ${e['detail']}' : ''}',
              path: e['path'] as String?));
        case 'mic_probe_done':
          _add(_FeedItem.note('mic', 'Mic test finished. Play each recording: can you hear the CALLER?'));
        case 'error':
          _add(_FeedItem.note('error', '❗ ${e['where']}: ${e['message']}'));
        case 'download':
          break;
        case 'discovery':
          _add(_FeedItem.note('discovery', '[${e['pkg']}] ${e['text']}'));
        case 'captions_missing':
          _add(_FeedItem.note('info', 'No captions seen 6 s into the call → trying to turn on Live Caption'));
        case 'captions_enable':
          _add(_FeedItem.note('info', e['ok'] == true ? 'Live Caption turned on' : 'Could not turn on Live Caption automatically'));
        case 'model':
          _add(_FeedItem.note('info', 'Model: ${e['status']} ${e['message']}'));
        case 'service':
          _add(_FeedItem.note('info', e['connected'] == true ? 'Protection service connected' : 'Protection service stopped'));
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Column(children: [
      Card(
        margin: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_inCall ? Icons.call : Icons.call_end, color: _inCall ? Colors.green : theme.disabledColor),
              const SizedBox(width: 8),
              Text(_inCall ? 'In call' : 'Not in a call', style: theme.textTheme.titleMedium),
              const Spacer(),
              Text('Call risk: ${_callLevel.title} ${(_callRisk * 100).round()}%',
                  style: TextStyle(color: _callLevel.color, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _callRisk, color: _callLevel.color, minHeight: 8,
                borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 8),
            Text(_caption.isEmpty ? 'Waiting for Live Caption text…' : _caption,
                maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
      Expanded(
        child: _items.isEmpty
            ? const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Play a scam-call recording on this phone with Live Caption on,\n'
                    'or start a call on speaker. Statements and verdicts appear here.',
                    textAlign: TextAlign.center),
              ))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final it = _items[i];
                  if (it.verdict != null) return VerdictCard(verdict: it.verdict!, compact: true);
                  return ListTile(
                    dense: true,
                    leading: Icon(switch (it.kind) {
                      'statement' => Icons.record_voice_over,
                      'discovery' => Icons.search,
                      'call' => Icons.phone_in_talk,
                      'signal' => Icons.bolt,
                      'mic' => Icons.mic,
                      'error' => Icons.error_outline,
                      _ => Icons.info_outline,
                    }),
                    title: Text(it.text ?? '', maxLines: 4, overflow: TextOverflow.ellipsis),
                    trailing: it.path == null
                        ? null
                        : IconButton(icon: const Icon(Icons.play_arrow), onPressed: () => TextApi.playProbe(it.path!)),
                  );
                },
              ),
      ),
    ]);
  }
}
