import 'package:flutter/material.dart';

import '../lessons/lesson_model.dart';
import '../lessons/quiz_engine.dart';
import '../models/verdict.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/stat_tile.dart';

/// UI strings per language. `hne` is a draft pending native-speaker sign-off (T3.6).
class LessonStrings {
  const LessonStrings(this.m);
  final Map<String, String> m;
  String operator [](String k) => m[k]!;

  static const hi = LessonStrings({
    'title': 'सीखें',
    'score': 'आपका डिजिटल वित्तीय साक्षरता स्कोर',
    'best': 'सर्वश्रेष्ठ',
    'new': 'शुरू करें',
    'next': 'अगला',
    'back': 'पीछे',
    'startQuiz': 'क्विज़ शुरू करें',
    'right': 'सही!',
    'wrong': 'ध्यान दें',
    'answerWas': 'सही उत्तर:',
    'nextQ': 'अगला सवाल',
    'finish': 'नतीजा देखें',
    'again': 'फिर से करें',
    'toList': 'सूची पर लौटें',
    'thisTime': 'इस बार',
    'question': 'सवाल',
    'loading': 'पाठ लोड हो रहे हैं…',
    'error': 'पाठ नहीं खुल सके। फिर कोशिश करें।',
    'retry': 'फिर कोशिश करें',
    'empty': 'अभी कोई पाठ नहीं है',
    'emptyHint': 'नए पाठ आने पर यहाँ दिखेंगे',
    'pick': 'सही जवाब चुनें',
  });
  static const hne = LessonStrings({
    'title': 'सीखव',
    'score': 'तुंहर डिजिटल वित्तीय साक्षरता स्कोर',
    'best': 'सबले बढ़िया',
    'new': 'सुरू करव',
    'next': 'आगू',
    'back': 'पाछू',
    'startQuiz': 'क्विज़ सुरू करव',
    'right': 'सही!',
    'wrong': 'ध्यान देव',
    'answerWas': 'सही जवाब:',
    'nextQ': 'आगू के सवाल',
    'finish': 'नतीजा देखव',
    'again': 'फेर करव',
    'toList': 'सूची म लहुटव',
    'thisTime': 'ए पइत',
    'question': 'सवाल',
    'loading': 'पाठ लोड होवत हे…',
    'error': 'पाठ नइ खुल सकिस। फेर कोशिश करव।',
    'retry': 'फेर कोशिश करव',
    'empty': 'अभी कोनो पाठ नइहे',
    'emptyHint': 'नवा पाठ आही त इहाँ दिखही',
    'pick': 'सही जवाब चुनव',
  });
  static const en = LessonStrings({
    'title': 'Learn',
    'score': 'Your Digital Financial Literacy Score',
    'best': 'Best',
    'new': 'Start',
    'next': 'Next',
    'back': 'Back',
    'startQuiz': 'Start quiz',
    'right': 'Correct!',
    'wrong': 'Take note',
    'answerWas': 'Right answer:',
    'nextQ': 'Next question',
    'finish': 'See result',
    'again': 'Try again',
    'toList': 'Back to lessons',
    'thisTime': 'This time',
    'question': 'Question',
    'loading': 'Loading lessons…',
    'error': 'Could not open the lessons. Try again.',
    'retry': 'Try again',
    'empty': 'No lessons yet',
    'emptyHint': 'New lessons will appear here',
    'pick': 'Pick the right answer',
  });

  static LessonStrings of(String lang) => switch (lang) {
    'hne' => hne,
    'en' => en,
    _ => hi,
  };
}

/// One lesson: 3 swipeable cards, then a one-question-at-a-time quiz, then the result.
class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.lesson,
    required this.engine,
    required this.lang,
  });
  final Lesson lesson;
  final QuizEngine engine;
  final String lang;
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

enum _Phase { cards, quiz, result }

class _QuizScreenState extends State<QuizScreen> {
  final _pages = PageController();
  _Phase _phase = _Phase.cards;
  int _card = 0;
  int _q = 0;
  int? _picked;
  late List<int?> _answers;
  QuizResult? _result;

  LessonStrings get _s => LessonStrings.of(widget.lang);
  Lesson get _lesson => widget.lesson;

  @override
  void initState() {
    super.initState();
    _answers = List.filled(_lesson.questions.length, null);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _restart() => setState(() {
    _phase = _Phase.quiz;
    _q = 0;
    _picked = null;
    _result = null;
    _answers = List.filled(_lesson.questions.length, null);
  });

  Future<void> _advance() async {
    if (_q + 1 < _lesson.questions.length) {
      setState(() {
        _q++;
        _picked = null;
      });
      return;
    }
    final r = await widget.engine.record(_lesson.id, _answers);
    if (mounted)
      setState(() {
        _result = r;
        _phase = _Phase.result;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_lesson.title)),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.cards => _cards(context),
          _Phase.quiz => _quiz(context),
          _Phase.result => _resultView(context),
        },
      ),
    );
  }

  Widget _bigButton(
    String label,
    VoidCallback onPressed, {
    Key? key,
    bool outlined = false,
  }) {
    final style =
        (outlined ? OutlinedButton.styleFrom : FilledButton.styleFrom)(
          minimumSize: const Size.fromHeight(kTouch),
        );
    return outlined
        ? OutlinedButton(
            key: key,
            style: style,
            onPressed: onPressed,
            child: Text(label, textAlign: TextAlign.center),
          )
        : FilledButton(
            key: key,
            style: style,
            onPressed: onPressed,
            child: Text(label, textAlign: TextAlign.center),
          );
  }

  Widget _cards(BuildContext context) {
    final theme = Theme.of(context);
    final last = _card == _lesson.cards.length - 1;
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            key: const Key('card_pages'),
            controller: _pages,
            itemCount: _lesson.cards.length,
            onPageChanged: (i) => setState(() => _card = i),
            itemBuilder: (_, i) {
              final c = _lesson.cards[i];
              return SingleChildScrollView(
                padding: const EdgeInsets.all(Sp.l),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Sp.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield, size: 56, color: theme.colorScheme.primary),
                        const SizedBox(height: Sp.m),
                        Text(c.title, style: theme.textTheme.headlineSmall),
                        const SizedBox(height: Sp.m),
                        Text(c.body, style: theme.textTheme.bodyLarge),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _lesson.cards.length; i++)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.all(Sp.s),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _card
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.l, Sp.xs, Sp.l, Sp.l),
          child: _bigButton(
            last ? _s['startQuiz'] : _s['next'],
            () => last
                ? setState(() => _phase = _Phase.quiz)
                : _pages.nextPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  ),
            key: const Key('cards_next'),
          ),
        ),
      ],
    );
  }

  Widget _quiz(BuildContext context) {
    final theme = Theme.of(context);
    final st = theme.extension<StatusColors>() ?? StatusColors.light;
    final q = _lesson.questions[_q];
    final answered = _picked != null;
    final right = answered && _picked == q.correctIndex;
    final fbLabel = right ? RiskLabel.safe : RiskLabel.suspicious; // amber, not red: gentler for learners
    final fb = st.solid(fbLabel);
    return Column(children: [
      Expanded(
        child: ListView(
      padding: const EdgeInsets.all(Sp.l),
      children: [
        Row(
          children: [
            Icon(Icons.help_outline, size: 32, color: theme.colorScheme.primary),
            const SizedBox(width: Sp.s),
            Expanded(
              child: Text(
                '${_s['question']} ${_q + 1}/${_lesson.questions.length}',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: Sp.s),
        Text(
          q.question,
          key: const Key('question_text'),
          style: theme.textTheme.headlineSmall,
        ),
        if (!answered)
          Padding(
            padding: const EdgeInsets.only(top: Sp.xs),
            child: Text(_s['pick'],
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        if (answered) ...[
          const SizedBox(height: Sp.l),
          Container(
            key: const Key('feedback'),
            padding: const EdgeInsets.all(Sp.l),
            decoration: BoxDecoration(
              color: st.tintOver(fbLabel, theme.colorScheme.surface),
              border: Border.all(color: fb, width: 2),
              borderRadius: BorderRadius.circular(Rad.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(right ? Icons.check_circle : Icons.warning_amber_rounded, color: fb, size: 40),
                    const SizedBox(width: Sp.s),
                    Expanded(
                      child: Text(
                        right ? _s['right'] : _s['wrong'],
                        style: theme.textTheme.titleLarge?.copyWith(color: fb),
                      ),
                    ),
                  ],
                ),
                if (!right) ...[
                  const SizedBox(height: Sp.s),
                  Text(
                    '${_s['answerWas']} ${q.options[q.correctIndex]}',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
                const SizedBox(height: Sp.s),
                Text(q.explanation, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
        const SizedBox(height: Sp.l),
        for (var i = 0; i < q.options.length; i++) _option(context, q, i),
      ],
        ),
      ),
      if (answered)
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.l),
          child: _bigButton(
            _q + 1 < _lesson.questions.length ? _s['nextQ'] : _s['finish'],
            _advance,
            key: const Key('quiz_next'),
          ),
        ),
    ]);
  }

  Widget _option(BuildContext context, QuizQuestion q, int i) {
    final theme = Theme.of(context);
    final st = theme.extension<StatusColors>() ?? StatusColors.light;
    final answered = _picked != null;
    final isRight = i == q.correctIndex;
    final isPicked = i == _picked;
    final color = !answered
        ? theme.colorScheme.primary
        : isRight
        ? st.safe
        : isPicked
        ? st.scam
        : theme.colorScheme.onSurfaceVariant; // hairline (outline) is ~1.3:1 as text
    final icon = !answered
        ? Icons.radio_button_unchecked
        : isRight
        ? Icons.check_circle
        : isPicked
        ? Icons.cancel
        : Icons.radio_button_unchecked;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.m),
      child: OutlinedButton(
        key: Key('option_$i'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(kTouch),
          alignment: Alignment.centerLeft,
          foregroundColor: color,
          // onPressed is null once answered; keep the answer colours readable (AA), not 38% grey.
          disabledForegroundColor: color,
          side: BorderSide(
            color: color,
            width: answered && (isRight || isPicked) ? 3 : 1.5,
          ),
          padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.m),
        ),
        onPressed: answered
            ? null
            : () => setState(() {
                _picked = i;
                _answers[_q] = i;
              }),
        child: Row(
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: Sp.m),
            Expanded(
              child: Text(q.options[i]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultView(BuildContext context) {
    final r = _result!;
    return ListView(
      padding: const EdgeInsets.all(Sp.l),
      children: [
        StatTile(
          value: '${r.correct}/${r.total}',
          caption: _s['thisTime'],
          icon: Icons.check_circle,
        ),
        const SizedBox(height: Sp.m),
        StatTile(
          value: '${widget.engine.score}',
          valueKey: const Key('result_score'),
          caption: '${_s['score']} (/ 100)',
          icon: Icons.shield,
        ),
        const SizedBox(height: Sp.l),
        _bigButton(_s['again'], _restart, key: const Key('result_again')),
        const SizedBox(height: Sp.m),
        _bigButton(
          _s['toList'],
          () => Navigator.of(context).pop(),
          key: const Key('result_back'),
          outlined: true,
        ),
      ],
    );
  }
}
