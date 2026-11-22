import 'package:flutter/material.dart';

import '../lessons/lesson_model.dart';
import '../lessons/quiz_engine.dart';

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
    'wrong': 'गलत',
    'answerWas': 'सही उत्तर:',
    'nextQ': 'अगला सवाल',
    'finish': 'नतीजा देखें',
    'again': 'फिर से करें',
    'toList': 'सूची पर लौटें',
    'thisTime': 'इस बार',
    'question': 'सवाल',
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
    'wrong': 'गलत',
    'answerWas': 'सही जवाब:',
    'nextQ': 'आगू के सवाल',
    'finish': 'नतीजा देखव',
    'again': 'फेर करव',
    'toList': 'सूची म लहुटव',
    'thisTime': 'ए पइत',
    'question': 'सवाल',
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
    'wrong': 'Wrong',
    'answerWas': 'Right answer:',
    'nextQ': 'Next question',
    'finish': 'See result',
    'again': 'Try again',
    'toList': 'Back to lessons',
    'thisTime': 'This time',
    'question': 'Question',
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
          minimumSize: const Size.fromHeight(64),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.shield,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          c.title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          c.body,
                          style: const TextStyle(fontSize: 20, height: 1.4),
                        ),
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
                margin: const EdgeInsets.all(6),
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
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
    final q = _lesson.questions[_q];
    final answered = _picked != null;
    final right = answered && _picked == q.correctIndex;
    final fb = right ? Colors.green.shade800 : theme.colorScheme.error;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${_s['question']} ${_q + 1}/${_lesson.questions.length}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          q.question,
          key: const Key('question_text'),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < q.options.length; i++) _option(context, q, i),
        if (answered) ...[
          const SizedBox(height: 8),
          Container(
            key: const Key('feedback'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: fb, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      right ? Icons.check_circle : Icons.cancel,
                      color: fb,
                      size: 32,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        right ? _s['right'] : _s['wrong'],
                        style: TextStyle(
                          color: fb,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!right) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_s['answerWas']} ${q.options[q.correctIndex]}',
                    style: const TextStyle(fontSize: 18),
                  ),
                ],
                const SizedBox(height: 6),
                Text(q.explanation, style: const TextStyle(fontSize: 18)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _bigButton(
            _q + 1 < _lesson.questions.length ? _s['nextQ'] : _s['finish'],
            _advance,
            key: const Key('quiz_next'),
          ),
        ],
      ],
    );
  }

  Widget _option(BuildContext context, QuizQuestion q, int i) {
    final theme = Theme.of(context);
    final answered = _picked != null;
    final isRight = i == q.correctIndex;
    final isPicked = i == _picked;
    final color = !answered
        ? theme.colorScheme.primary
        : isRight
        ? Colors.green.shade800
        : isPicked
        ? theme.colorScheme.error
        : theme.colorScheme.outline;
    final icon = !answered
        ? Icons.radio_button_unchecked
        : isRight
        ? Icons.check_circle
        : isPicked
        ? Icons.cancel
        : Icons.radio_button_unchecked;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton(
        key: Key('option_$i'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          alignment: Alignment.centerLeft,
          foregroundColor: color,
          side: BorderSide(
            color: color,
            width: answered && (isRight || isPicked) ? 3 : 1.5,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        onPressed: answered
            ? null
            : () => setState(() {
                _picked = i;
                _answers[_q] = i;
              }),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(q.options[i], style: const TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultView(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  '${_s['thisTime']}: ${r.correct}/${r.total}',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  _s['score'],
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  '${widget.engine.score}',
                  key: const Key('result_score'),
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text('/ 100', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _bigButton(_s['again'], _restart, key: const Key('result_again')),
        const SizedBox(height: 12),
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
