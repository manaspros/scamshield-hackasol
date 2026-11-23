import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../lessons/lesson_model.dart';
import '../lessons/prefs_store.dart';
import '../lessons/quiz_engine.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/press_scale.dart';
import '../widgets/state_message.dart';
import '../widgets/stat_tile.dart';
import 'quiz_screen.dart';

/// Lessons list: 8 icon-first tiles, per-topic best, and the overall literacy score.
class LessonsScreen extends StatefulWidget {
  const LessonsScreen({
    super.key,
    QuizStore? store,
    this.bundle,
    this.initialLang = 'hi',
  }) : _store = store;
  final QuizStore? _store;
  final AssetBundle? bundle;
  final String initialLang;
  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

const _icons = <String, IconData>{
  'otp': Icons.sms,
  'upi_pin': Icons.pin,
  'atm_pin': Icons.atm,
  'qr': Icons.qr_code_scanner,
  'digital_arrest': Icons.local_police,
  'kyc': Icons.badge,
  'courier': Icons.local_shipping,
  'loan_app': Icons.request_quote,
};

class _LessonsScreenState extends State<LessonsScreen> {
  late final QuizStore _store = widget._store ?? PrefsQuizStore();
  late String _lang = widget.initialLang;
  QuizEngine? _engine;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lessons = await loadLessonsFromAssets(_lang, bundle: widget.bundle);
      final engine = QuizEngine(lessons, _store);
      await engine.load();
      if (mounted) setState(() => _engine = engine);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _retry() {
    setState(() => _failed = false);
    _load();
  }

  Future<void> _open(QuizEngine e, Lesson l) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => QuizScreen(lesson: l, engine: e, lang: _lang)),
    );
    if (mounted) setState(() {});
  }

  void _setLang(String l) {
    if (l == _lang) return;
    setState(() {
      _lang = l;
      _engine = null;
      _failed = false;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = LessonStrings.of(_lang);
    final e = _engine;
    // One primary action: the next lesson to do (an unfinished one first, else the weakest).
    final Lesson? next = (e == null || e.lessons.isEmpty)
        ? null
        : e.lessons.firstWhere((l) => e.bestFor(l.id) == 0,
            orElse: () => e.lessons.reduce((a, b) => e.bestFor(b.id) < e.bestFor(a.id) ? b : a));
    final Widget content;
    if (_failed) {
      content = StateMessage(
          icon: Icons.cloud_off, title: s['error'], actionLabel: s['retry'], onAction: _retry);
    } else if (e == null) {
      content = StateMessage(loading: true, title: s['loading']);
    } else if (e.lessons.isEmpty) {
      content = StateMessage(icon: Icons.school, title: s['empty'], subtitle: s['emptyHint']);
    } else {
      content = Column(children: [for (final l in e.lessons) _tile(context, e, l, s)]);
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Sp.l),
            children: [
              Wrap(
                spacing: Sp.s,
                runSpacing: Sp.s,
                children: [
                  for (final (code, label) in const [
                    ('hi', 'हिन्दी'),
                    ('hne', 'छत्तीसगढ़ी'),
                    ('en', 'English'),
                  ])
                    ChoiceChip(
                      key: Key('lang_$code'),
                      label: Text(label),
                      selected: _lang == code,
                      checkmarkColor: Theme.of(context).colorScheme.primary,
                      onSelected: (_) => _setLang(code),
                    ),
                ],
              ),
              const SizedBox(height: Sp.m),
              StatTile(
                value: '${e?.score ?? 0}',
                valueKey: const Key('score_value'),
                caption: '${s['score']} (/ 100)',
                icon: Icons.shield,
              ),
              content,
            ],
          ),
        ),
        if (e != null && next != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.l),
            child: FilledButton.icon(
              key: const Key('lessons_primary'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
              onPressed: () => _open(e, next),
              icon: Icon(e.bestFor(next.id) > 0 ? Icons.replay : Icons.play_arrow, size: 28),
              label: Text(
                '${e.bestFor(next.id) > 0 ? s['again'] : s['new']}: ${next.title}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _tile(BuildContext context, QuizEngine e, Lesson l, LessonStrings s) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final st = theme.extension<StatusColors>() ?? StatusColors.light;
    final best = e.bestFor(l.id);
    return PressScale(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('lesson_${l.id}'),
          onTap: () => _open(e, l),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.all(Sp.l),
              child: Row(
                children: [
                  Icon(_icons[l.id] ?? Icons.school, size: 48, color: cs.primary),
                  const SizedBox(width: Sp.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.title, style: theme.textTheme.titleLarge),
                        const SizedBox(height: Sp.xs),
                        Row(
                          children: [
                            Icon(
                              best > 0 ? Icons.check_circle : Icons.play_circle_outline,
                              size: 28,
                              color: best > 0 ? st.safe : cs.primary,
                            ),
                            const SizedBox(width: Sp.s),
                            Flexible(
                              child: Text(
                                best > 0 ? '${s['best']}: $best%' : s['new'],
                                key: Key('best_${l.id}'),
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 32, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
