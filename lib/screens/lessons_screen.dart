import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../lessons/lesson_model.dart';
import '../lessons/prefs_store.dart';
import '../lessons/quiz_engine.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lessons = await loadLessonsFromAssets(_lang, bundle: widget.bundle);
    final engine = QuizEngine(lessons, _store);
    await engine.load();
    if (mounted) setState(() => _engine = engine);
  }

  void _setLang(String l) {
    if (l == _lang) return;
    setState(() {
      _lang = l;
      _engine = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = LessonStrings.of(_lang);
    final e = _engine;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (code, label) in const [
              ('hi', 'हिन्दी'),
              ('hne', 'छत्तीसगढ़ी'),
              ('en', 'English'),
            ])
              ChoiceChip(
                key: Key('lang_$code'),
                label: Text(label, style: const TextStyle(fontSize: 16)),
                selected: _lang == code,
                onSelected: (_) => _setLang(code),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  s['score'],
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  '${e?.score ?? 0}',
                  key: const Key('score_value'),
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('/ 100', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
        ),
        if (e == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final l in e.lessons) _tile(context, e, l, s),
      ],
    );
  }

  Widget _tile(BuildContext context, QuizEngine e, Lesson l, LessonStrings s) {
    final theme = Theme.of(context);
    final best = e.bestFor(l.id);
    return Card(
      child: InkWell(
        key: Key('lesson_${l.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => QuizScreen(lesson: l, engine: e, lang: _lang),
            ),
          );
          if (mounted) setState(() {});
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: theme.colorScheme.primary,
                  child: Icon(
                    _icons[l.id] ?? Icons.school,
                    size: 32,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            best > 0
                                ? Icons.check_circle
                                : Icons.play_circle_outline,
                            color: best > 0
                                ? Colors.green.shade800
                                : theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              best > 0 ? '${s['best']}: $best%' : s['new'],
                              key: Key('best_${l.id}'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
