import 'dart:async';

import 'package:flutter/material.dart';

import '../api/text_api.dart';
import '../models/verdict.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/section_header.dart';
import '../widgets/state_message.dart';
import '../widgets/status_chip.dart';
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
  bool _streamError = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _sub = TextApi.events.listen(_onEvent, onError: (Object _) {
      if (mounted) setState(() => _streamError = true);
    });
  }

  void _retry() {
    _sub?.cancel();
    setState(() => _streamError = false);
    _listen();
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
          _add(_FeedItem.note('call', _inCall ? 'Call started' : 'Call ended'));
          if (_inCall) { _callRisk = 0; _callLevel = RiskLabel.safe; }
        case 'signal':
          _add(_FeedItem.note('signal', 'In-call signal: ${e['kind']} (${e['trigger']})'));
        case 'mic_probe':
          final status = '${e['status']}';
          final db = e['dbfs'] is num ? ' ${(e['dbfs'] as num).toStringAsFixed(1)} dBFS, peak ${e['peak']}' : '';
          final kind = status == 'HAS_AUDIO' ? 'mic' : (status == 'SILENT' ? 'mic_off' : 'mic_warn');
          _add(_FeedItem.note(kind, 'Mic ${e['source']}: $status$db${e['detail'] != null ? ' — ${e['detail']}' : ''}',
              path: e['path'] as String?));
        case 'mic_probe_done':
          _add(_FeedItem.note('mic', 'Mic test finished. Play each recording: can you hear the CALLER?'));
        case 'error':
          _add(_FeedItem.note('error', '${e['where']}: ${e['message']}'));
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

  static IconData _iconFor(String kind) => switch (kind) {
        'statement' => Icons.record_voice_over,
        'discovery' => Icons.search,
        'call' => Icons.phone_in_talk,
        'signal' => Icons.bolt,
        'mic' => Icons.mic,
        'mic_off' => Icons.mic_off,
        'mic_warn' => Icons.warning_amber_rounded,
        'error' => Icons.error_outline,
        _ => Icons.info_outline,
      };

  // What to do now, by verdict. Calm, imperative, one short line each.
  static const _adviceTitle = 'घबराएँ नहीं। अभी यह करें:';
  static const _advice = <RiskLabel, List<String>>{
    RiskLabel.scam: ['पैसे न भेजें, कॉल काट दें', 'OTP या PIN किसी को न बताएँ'],
    RiskLabel.suspicious: ['जल्दबाज़ी न करें, कॉल काट दें', 'पहले अपने परिवार से पूछें'],
  };

  Widget _dominant(Verdict v) {
    final warn = v.label != RiskLabel.safe;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: VerdictCard(
        key: ValueKey(identityHashCode(v)),
        verdict: v,
        adviceTitle: warn ? _adviceTitle : null,
        advice: _advice[v.label] ?? const [],
        footer: warn ? const _Helpline() : null,
      ),
    );
  }

  Widget _history(_FeedItem it, StatusColors st, ColorScheme cs) {
    if (it.verdict != null) return VerdictCard(verdict: it.verdict!, compact: true);
    return ListTile(
      leading: Icon(
        _iconFor(it.kind),
        size: 32,
        color: switch (it.kind) {
          'error' => st.scam,
          'mic_warn' || 'mic_off' => st.suspicious,
          'mic' => st.safe,
          _ => cs.onSurface,
        },
      ),
      title: Text(it.text ?? '', maxLines: 4, overflow: TextOverflow.ellipsis),
      trailing: it.path == null
          ? null
          : IconButton(
              tooltip: 'सुनें',
              icon: const Icon(Icons.play_arrow),
              onPressed: () => TextApi.playProbe(it.path!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final st = theme.extension<StatusColors>() ?? StatusColors.light;
    final latest = _items.where((i) => i.verdict != null).firstOrNull;
    final rest = [for (final i in _items) if (i != latest) i];

    final List<Widget> body;
    Widget? primary;
    if (_streamError) {
      body = const [
        StateMessage(icon: Icons.sync_problem, title: 'लाइव फ़ीड रुक गया', subtitle: 'नीचे दबाकर फिर जोड़ें'),
      ];
      primary = _primary(Icons.refresh, 'फिर कोशिश करें', _retry);
    } else if (_items.isEmpty) {
      body = const [
        StateMessage(
            icon: Icons.hearing,
            title: 'अभी कोई कॉल नहीं जाँची गई',
            subtitle: 'कॉल आने पर यहाँ चेतावनी दिखेगी'),
      ];
      primary = _primary(Icons.closed_caption, 'लाइव कैप्शन चालू करें', TextApi.openCaptionSettings);
    } else {
      body = [
        if (latest != null) _dominant(latest.verdict!),
        if (latest != null && rest.isNotEmpty) const SectionHeader(title: 'पिछली जाँच', icon: Icons.history),
        for (final it in rest) _history(it, st, cs),
      ];
    }

    // The status card scrolls with the list so nothing is cut off at large text sizes.
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(Sp.l), children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(Sp.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(_inCall ? Icons.call : Icons.call_end, size: 40, color: _inCall ? st.safe : cs.onSurfaceVariant),
                  const SizedBox(width: Sp.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_inCall ? 'कॉल चल रही है' : 'अभी कोई कॉल नहीं', style: theme.textTheme.titleLarge),
                    ]),
                  ),
                ]),
                const SizedBox(height: Sp.m),
                StatusChip(label: _callLevel, text: '${_callLevel.hindi} · ${(_callRisk * 100).round()}%'),
                const SizedBox(height: Sp.m),
                LinearProgressIndicator(value: _callRisk, color: st.solid(_callLevel)),
                const SizedBox(height: Sp.m),
                Text(_caption.isEmpty ? 'Live Caption का टेक्स्ट आने की प्रतीक्षा…' : _caption,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ]),
            ),
          ),
          ...body,
        ]),
      ),
      if (primary != null) primary,
    ]);
  }

  Widget _primary(IconData icon, String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.l),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
          onPressed: onTap,
          icon: Icon(icon, size: 28),
          label: Text(label, textAlign: TextAlign.center),
        ),
      );
}

/// Cyber-crime helpline, shown big under a scam or suspicious verdict. There is no
/// dialer channel in the app yet, so this is a number to read, not a button.
class _Helpline extends StatelessWidget {
  const _Helpline();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Sp.l),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: t.colorScheme.outline),
      ),
      child: Row(children: [
        Icon(Icons.call, size: 40, color: t.colorScheme.primary),
        const SizedBox(width: Sp.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('1930 पर कॉल करें', style: t.textTheme.titleLarge),
            Text('साइबर ठगी की मुफ़्त हेल्पलाइन',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}
