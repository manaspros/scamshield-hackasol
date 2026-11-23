import 'package:flutter/material.dart';

import '../api/llm_api.dart';
import '../learn/learn_plan.dart';
import '../learn/quiz_generator.dart';
import '../learn/quiz_session.dart';
import '../l10n/strings_learn.dart';
import '../lessons/lesson_model.dart';
import '../lessons/quiz_engine.dart';
import '../models/verdict.dart';
import '../profile/user_profile.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import '../widgets/premium.dart';
import '../widgets/shell_bar.dart';
import 'flashcards_screen.dart';

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
    'progress': 'पाठ {x}/{y} पूरे',
    'scoreWord': 'स्कोर',
    'pts': '+{n} अंक',
    'emptyScore': 'पहला पाठ पूरा करें — आपका स्कोर यहाँ दिखेगा',
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
    'progress': 'पाठ {x}/{y} पूरा',
    'scoreWord': 'स्कोर',
    'pts': '+{n} अंक',
    'emptyScore': 'पहिली पाठ पूरा करव — तुंहर स्कोर इहाँ दिखही',
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
    'progress': '{x}/{y} lessons done',
    'scoreWord': 'Score',
    'pts': '+{n} pts',
    'emptyScore': 'Finish your first lesson — your score will show here',
  });

  static LessonStrings of(String lang) => switch (lang) {
    'hne' => hne,
    'en' => en,
    _ => hi,
  };
}

/// Lessons finished (X/Y) first, the average score as the secondary line. The score
/// formula stays in [QuizEngine.score]; this only changes what is shown first.
class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key, required this.engine, required this.strings, required this.scoreKey, this.earned = 0});
  final QuizEngine engine;
  final LessonStrings strings;

  /// Key on the [Text] that holds just the score number.
  final Key scoreKey;

  /// Points gained by the attempt that was just finished; hidden when 0.
  final int earned;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final total = engine.lessons.length;
    final done = engine.lessons.where((l) => engine.bestFor(l.id) > 0).length;
    final progress = strings['progress'].replaceAll('{x}', '$done').replaceAll('{y}', '$total');
    final pts = strings['pts'].replaceAll('{n}', '$earned');
    final sub = t.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant);
    return Semantics(
      label: '$progress, ${strings['scoreWord']} ${engine.score}/100',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Sp.xl),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(Rad.lg),
          border: Border.all(color: cs.outline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.shield, size: 32, color: cs.primary),
          const SizedBox(height: Sp.s),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(progress, style: AppText.display.copyWith(fontSize: 40, color: cs.onSurface)),
          ),
          const SizedBox(height: Sp.m),
          ClipRRect(
            borderRadius: BorderRadius.circular(Rad.pill),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 8,
              color: cs.primary,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: Sp.m),
          Wrap(crossAxisAlignment: WrapCrossAlignment.end, children: [
            Text('${strings['scoreWord']} ', style: sub),
            Text('${engine.score}', key: scoreKey, style: sub),
            Text('/100', style: sub),
          ]),
          if (earned > 0) ...[
            const SizedBox(height: Sp.xs),
            Text(pts, key: const Key('result_earned'), style: t.textTheme.titleLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          ],
        ]),
      ),
    );
  }
}

/// One lesson: swipeable cards, then a one-question-at-a-time quiz (AI-written when a model is loaded),
/// then the result with weak areas and new flashcards.
class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.lesson,
    required this.engine,
    required this.lang,
    this.llm = const LlmApi(),
    this.startWithQuiz = false,
  });
  final Lesson lesson;
  final QuizEngine engine;
  final String lang;
  final LlmClient llm;

  /// Skip the cards and go straight to the quiz (the Learn tab's "Start AI quiz").
  final bool startWithQuiz;
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

enum _Phase { cards, quiz, result }

class _QuizScreenState extends State<QuizScreen> {
  final _pages = PageController();
  late _Phase _phase = widget.startWithQuiz ? _Phase.quiz : _Phase.cards;
  int _card = 0;
  int _q = 0;
  int? _picked;
  QuizQuestion? _cur;
  bool _starting = false;
  late QuizSession _session;
  final _right = <bool>[];
  final _misses = <Miss>[];
  QuizResult? _result;
  int _earned = 0;
  bool _reviewing = false;
  int _newCards = 0;

  LessonStrings get _s => LessonStrings.of(widget.lang);
  String _l(String k, [Map<String, Object?> a = const {}]) => learnT(widget.lang, k, a);
  Lesson get _lesson => widget.lesson;
  String? get _name => ProfileStore.profile.value.firstName;

  @override
  void initState() {
    super.initState();
    _newSession();
    if (_phase == _Phase.quiz) WidgetsBinding.instance.addPostFrameCallback((_) => _beginQuiz());
  }

  void _newSession() {
    _session = QuizSession(
      lesson: _lesson,
      llm: widget.llm,
      profile: ProfileStore.profile.value,
      lang: widget.lang,
      weak: LearnStore.plan.value.weak,
    );
  }

  @override
  void dispose() {
    _pages.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _beginQuiz() async {
    setState(() {
      _phase = _Phase.quiz;
      _starting = true;
    });
    await _session.start();
    if (!mounted) return;
    setState(() => _starting = false);
    await _show(0);
  }

  /// Puts question [i] on screen (waits for the AI if it's still writing) and prepares the next one.
  Future<void> _show(int i) async {
    final ready = _session.ready(i);
    setState(() {
      _q = i;
      _picked = null;
      _cur = ready;
    });
    if (ready == null) {
      final q = await _session.at(i);
      if (!mounted || _q != i) return;
      setState(() => _cur = q);
    }
    _session.prefetch(i + 1);
  }

  void _useReady() => setState(() => _cur = _session.useReady(_q));

  void _restart() {
    _newSession();
    _right.clear();
    _misses.clear();
    setState(() {
      _result = null;
      _newCards = 0;
    });
    _beginQuiz();
  }

  final _scroll = ScrollController();

  void _pick(QuizQuestion q, int i) {
    setState(() => _picked = i);
    // Bring the explanation into view under the options.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      }
    });
    final ok = i == q.correctIndex;
    _right.add(ok);
    if (!ok) _misses.add(Miss(question: q.question, picked: q.options[i], right: q.options[q.correctIndex]));
  }

  Future<void> _advance() async {
    if (_q + 1 < _session.length) {
      await _show(_q + 1);
      return;
    }
    final before = widget.engine.score;
    final correct = _right.where((r) => r).length;
    final r = await widget.engine.recordScore(_lesson.id, correct, _right.length);
    if (!mounted) return;
    setState(() {
      _earned = widget.engine.score - before;
      _result = r;
      _phase = _Phase.result;
    });
    _review(correct);
  }

  /// Updates the learning plan; with a model, asks it for weak spots and new flashcards.
  Future<void> _review(int correct) async {
    var plan = LearnStore.plan.value.withAnswers(_lesson.id, List.of(_right));
    final valid = {for (final l in widget.engine.lessons) l.id};
    List<StudyCard> add = const [];
    String? note;
    if (_session.ai && _misses.isNotEmpty) {
      if (mounted) setState(() => _reviewing = true);
      final rv = await QuizGenerator(widget.llm).review(
        lesson: _lesson,
        misses: List.of(_misses),
        correct: correct,
        total: _right.length,
        profile: ProfileStore.profile.value,
        lang: widget.lang,
        validTopics: valid,
      );
      if (rv != null) {
        add = rv.cards;
        note = rv.plan;
        final extra = rv.weak.where((w) => !plan.weak.contains(w));
        plan = plan.copyWith(weak: [...plan.weak, ...extra]);
      }
    }
    if (add.isEmpty && plan.weak.contains(_lesson.id)) {
      add = fallbackCards(widget.engine.lessons, [_lesson.id]);
    }
    if (note == null && plan.weak.isNotEmpty) {
      final titles = [
        for (final w in plan.weak.take(2))
          for (final l in widget.engine.lessons.where((l) => l.id == w)) l.title,
      ];
      note = _l('plan_default', {'topics': titles.join(', ')});
    }
    final fresh = add.where((c) => !plan.deck.any((d) => d.front.toLowerCase() == c.front.toLowerCase())).length;
    plan = plan.copyWith(deck: mergeDeck(plan.deck, add), note: note ?? _l('plan_keep'), newCards: fresh);
    final saved = LearnStore.save(plan); // updates the plan in memory at once; the disk write can trail
    if (mounted) {
      setState(() {
        _reviewing = false;
        _newCards = fresh;
      });
    }
    await saved;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: shellBar(titleText: _lesson.title),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey('$_phase$_q${_cur != null}'),
            child: switch (_phase) {
              _Phase.cards => _cards(context),
              _Phase.quiz => _quiz(context),
              _Phase.result => _resultView(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _bigButton(String label, VoidCallback onPressed, {Key? key, bool outlined = false}) {
    final style = (outlined ? OutlinedButton.styleFrom : FilledButton.styleFrom)(minimumSize: const Size.fromHeight(kTouch));
    return outlined
        ? OutlinedButton(key: key, style: style, onPressed: onPressed, child: Text(label, textAlign: TextAlign.center))
        : FilledButton(key: key, style: style, onPressed: onPressed, child: Text(label, textAlign: TextAlign.center));
  }

  Widget _cards(BuildContext context) {
    final theme = Theme.of(context);
    final p = palOf(context);
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
                child: PCard(
                  radius: 28,
                  padding: const EdgeInsets.all(Sp.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconBadge(icon: Icons.shield_rounded, color: p.accent, tint: p.accentTint, size: 60, iconSize: 32),
                      const SizedBox(height: Sp.l),
                      Text(c.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: Sp.m),
                      Text(c.body, style: theme.textTheme.bodyLarge),
                    ],
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == _card ? 28 : 10,
                height: 10,
                margin: const EdgeInsets.all(Sp.xs),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Rad.pill),
                  color: i == _card ? p.accent : p.hairline,
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.l),
          child: _bigButton(
            last ? _s['startQuiz'] : _s['next'],
            () => last ? _beginQuiz() : _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
            key: const Key('cards_next'),
          ),
        ),
      ],
    );
  }

  Widget _segments(BuildContext context) {
    final p = palOf(context);
    final st = Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
    final n = _session.length;
    return Row(children: [
      for (var i = 0; i < n; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: i < _right.length ? (_right[i] ? st.safe : st.scam) : (i == _q ? p.accent.withValues(alpha: 0.35) : p.hairline),
            ),
          ),
        ),
      ],
    ]);
  }

  Widget _quiz(BuildContext context) {
    final theme = Theme.of(context);
    final p = palOf(context);
    final q = _cur;
    final head = Padding(
      padding: const EdgeInsets.fromLTRB(Sp.l, Sp.m, Sp.l, 0),
      child: Row(children: [
        Expanded(child: _segments(context)),
        const SizedBox(width: Sp.m),
        Text('${_q + 1}/${_session.length}', style: theme.textTheme.titleSmall?.copyWith(color: p.muted, fontWeight: FontWeight.w700)),
      ]),
    );
    if (_starting || q == null) {
      return Column(children: [
        if (!_starting) head,
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Sp.xl),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                IconBadge(icon: Icons.auto_awesome_rounded, color: p.accent, tint: p.accentTint, size: 72, iconSize: 38),
                const SizedBox(height: Sp.l),
                Text(_l('ai_writing'), key: const Key('quiz_ai_writing'), textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                const SizedBox(height: Sp.xs),
                Text(_l('ai_writing_s'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: p.muted)),
                const SizedBox(height: Sp.l),
                const SizedBox(width: 160, child: LinearProgressIndicator()),
                if (!_starting) ...[
                  const SizedBox(height: Sp.l),
                  TextButton(key: const Key('quiz_use_ready'), onPressed: _useReady, child: Text(_l('use_ready'))),
                ],
              ]),
            ),
          ),
        ),
      ]);
    }
    final answered = _picked != null;
    final right = answered && _picked == q.correctIndex;
    return Column(children: [
      head,
      Expanded(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(Sp.l),
          children: [
            if (_session.aiMade(_q))
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  key: const Key('quiz_ai_chip'),
                  margin: const EdgeInsets.only(bottom: Sp.m),
                  padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: 6),
                  decoration: BoxDecoration(color: p.accentTint, borderRadius: BorderRadius.circular(Rad.pill)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome_rounded, size: 16, color: p.accent),
                    const SizedBox(width: 6),
                    Flexible(child: Text('${_l('ai_made')} · ${_lesson.title}', style: theme.textTheme.labelSmall?.copyWith(color: p.accent, fontSize: 14))),
                  ]),
                ),
              ),
            Text(q.question, key: const Key('question_text'), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
            if (!answered)
              Padding(
                padding: const EdgeInsets.only(top: Sp.xs),
                child: Text(_s['pick'], style: theme.textTheme.bodySmall?.copyWith(color: p.muted)),
              ),
            const SizedBox(height: Sp.l),
            for (var i = 0; i < q.options.length; i++) _option(context, q, i),
            if (answered) ...[
              const SizedBox(height: Sp.s),
              Container(
                key: const Key('feedback'),
                padding: const EdgeInsets.all(Sp.l + 4),
                decoration: BoxDecoration(
                  color: p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFF1D1D1F),
                  borderRadius: BorderRadius.circular(30),
                  border: p.isDark ? Border.all(color: const Color(0xFF48484A)) : null,
                  boxShadow: Elev.island(theme.brightness),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: right ? StatusColors.dark.safe : StatusColors.dark.scam),
                      child: Icon(right ? Icons.check_circle : Icons.warning_amber_rounded, size: 20, color: const Color(0xFF1C1C1E)),
                    ),
                    const SizedBox(width: Sp.s + 2),
                    Expanded(
                      child: Text(
                        _name == null ? (right ? _s['right'] : _s['wrong']) : _l(right ? 'correct_name' : 'not_quite_name', {'name': _name}),
                        style: theme.textTheme.titleLarge?.copyWith(color: const Color(0xFFF5F5F7), fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                  const SizedBox(height: Sp.s),
                  if (!right)
                    Text('${_s['answerWas']} ${q.options[q.correctIndex]}',
                        style: theme.textTheme.bodyLarge?.copyWith(color: const Color(0xFFF5F5F7), fontWeight: FontWeight.w600, fontSize: 17)),
                  Text(q.explanation, style: theme.textTheme.bodyLarge?.copyWith(color: const Color(0xFFD1D1D6), fontSize: 17)),
                ]),
              ),
            ],
          ],
        ),
      ),
      if (answered)
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.l),
          child: FilledButton(
            key: const Key('quiz_next'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
            onPressed: _advance,
            child: Text(_q + 1 < _session.length ? _s['nextQ'] : _s['finish'], textAlign: TextAlign.center),
          ),
        ),
    ]);
  }

  Widget _option(BuildContext context, QuizQuestion q, int i) {
    final theme = Theme.of(context);
    final p = palOf(context);
    final st = theme.extension<StatusColors>() ?? StatusColors.light;
    final answered = _picked != null;
    final isRight = i == q.correctIndex;
    final isPicked = i == _picked;
    final good = answered && isRight;
    final bad = answered && isPicked && !isRight;
    final border = good ? st.safe : bad ? st.scam : p.surface;
    final bg = good ? st.tintOver(RiskLabel.safe, p.surface) : bad ? st.tintOver(RiskLabel.scam, p.surface) : p.surface;
    final dot = good ? st.safe : bad ? st.scam : (p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF0F0F2));
    final onDot = good || bad ? (p.isDark ? Colors.black : Colors.white) : p.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s + 2),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: border, width: 2)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('option_$i'),
          onTap: answered ? null : () => _pick(q, i),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.m),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
                  alignment: Alignment.center,
                  child: good
                      ? Icon(Icons.check_circle, color: onDot, size: 22)
                      : bad
                          ? Icon(Icons.cancel, color: onDot, size: 22)
                          : Text(String.fromCharCode(65 + i), style: theme.textTheme.titleSmall?.copyWith(color: onDot, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: Sp.m),
                Expanded(
                  child: Text(q.options[i],
                      style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17, fontWeight: FontWeight.w500, color: answered && !good && !bad ? p.muted : p.ink)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultView(BuildContext context) {
    final r = _result!;
    final theme = Theme.of(context);
    final p = palOf(context);
    final st = theme.extension<StatusColors>() ?? StatusColors.light;
    final all = r.total > 0 && r.correct == r.total;
    final w = _l(all ? 'res_great' : 'res_good');
    final title = _name == null ? w : _l('res_name', {'w': w, 'name': _name});
    final titles = {for (final l in widget.engine.lessons) l.id: l.title};
    return ValueListenableBuilder<LearnPlan>(
      valueListenable: LearnStore.plan,
      builder: (context, plan, _) {
        final rows = plan.stats.entries.where((e) => titles.containsKey(e.key) && e.value.seen > 0).toList()
          ..sort((a, b) => a.value.accuracy.compareTo(b.value.accuracy));
        return ListView(
          padding: const EdgeInsets.all(Sp.l),
          children: [
            const SizedBox(height: Sp.s),
            Center(
              child: RingProgress(
                value: r.total == 0 ? 0 : r.correct / r.total,
                size: 156,
                stroke: 14,
                color: p.accent,
                track: p.hairline,
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${r.correct}/${r.total}', key: const Key('result_correct'), style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(_l('correct_word'), style: theme.textTheme.bodySmall?.copyWith(color: p.muted)),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Sp.l),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: Sp.xs),
            Text(_l(all ? 'res_body_strong' : 'res_body_weak'), textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(color: p.muted, fontSize: 17)),
            const SizedBox(height: Sp.m),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: st.tintOver(RiskLabel.safe, p.surface), borderRadius: BorderRadius.circular(Rad.pill)),
                child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (_earned > 0) ...[
                    Text(_s['pts'].replaceAll('{n}', '$_earned'), key: const Key('result_earned'), style: theme.textTheme.titleSmall?.copyWith(color: st.safe, fontWeight: FontWeight.w700)),
                    Text(' · ', style: theme.textTheme.titleSmall?.copyWith(color: st.safe, fontWeight: FontWeight.w700)),
                  ],
                  Text('${_s['scoreWord']} ', style: theme.textTheme.titleSmall?.copyWith(color: st.safe, fontWeight: FontWeight.w700)),
                  Text('${widget.engine.score}', key: const Key('result_score'), style: theme.textTheme.titleSmall?.copyWith(color: st.safe, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
            if (rows.isNotEmpty) ...[
              PSection(title: _l('where')),
              for (final e in rows.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: Sp.s + 2),
                  child: _weakRow(context, titles[e.key]!, e.value),
                ),
            ],
            const SizedBox(height: Sp.m),
            if (_reviewing)
              PCard(
                key: const Key('result_reviewing'),
                child: Row(children: [
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3)),
                  const SizedBox(width: Sp.m),
                  Expanded(child: Text(_l('reviewing'), style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17))),
                ]),
              )
            else if (plan.note != null)
              Container(
                key: const Key('result_plan'),
                padding: const EdgeInsets.all(Sp.l + 2),
                decoration: BoxDecoration(color: p.accentTint, borderRadius: BorderRadius.circular(RadX.card)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.auto_awesome_rounded, color: p.accent),
                  const SizedBox(width: Sp.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_l('plan_week'), style: theme.textTheme.labelMedium?.copyWith(color: p.accent, fontWeight: FontWeight.w700)),
                      const SizedBox(height: Sp.xs),
                      Text(plan.note!, style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.4)),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: Sp.l),
            if (_newCards > 0) ...[
              FilledButton.icon(
                key: const Key('result_practise'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
                onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                  builder: (_) => FlashcardsScreen(lessons: widget.engine.lessons, lang: widget.lang),
                )),
                icon: const Icon(Icons.style_rounded),
                label: Text(_l('practise_new', {'n': _newCards})),
              ),
              const SizedBox(height: Sp.m),
            ],
            _bigButton(_s['again'], _restart, key: const Key('result_again'), outlined: _newCards > 0),
            const SizedBox(height: Sp.m),
            _bigButton(_s['toList'], () => Navigator.of(context).pop(), key: const Key('result_back'), outlined: true),
          ],
        );
      },
    );
  }

  Widget _weakRow(BuildContext context, String title, TopicStat s) {
    final theme = Theme.of(context);
    final p = palOf(context);
    final st = theme.extension<StatusColors>() ?? StatusColors.light;
    final a = s.accuracy;
    final (tag, c, lbl) = a < 0.4
        ? (_l('tag_needs'), st.scam, RiskLabel.scam)
        : a < kWeakBelow
            ? (_l('tag_almost'), st.suspicious, RiskLabel.suspicious)
            : (_l('tag_strong'), st.safe, RiskLabel.safe);
    return PCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: st.tintOver(lbl, p.surface), borderRadius: BorderRadius.circular(Rad.pill)),
            child: Text(tag, style: theme.textTheme.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ]),
        const SizedBox(height: Sp.s + 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: a, minHeight: 8, color: c, backgroundColor: p.hairline),
        ),
        const SizedBox(height: Sp.xs),
        Text('${(a * 100).round()}% · ${s.correct}/${s.seen}', style: theme.textTheme.bodySmall?.copyWith(color: p.muted)),
      ]),
    );
  }
}
