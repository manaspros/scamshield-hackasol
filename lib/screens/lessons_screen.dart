import 'package:flutter/material.dart';

import '../api/llm_api.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_learn.dart';
import '../l10n/strings_profile.dart';
import '../l10n/strings_shell.dart';
import '../learn/learn_plan.dart';
import '../lessons/lesson_model.dart';
import '../lessons/prefs_store.dart' show PrefsQuizStore;
import '../lessons/quiz_engine.dart';
import '../profile/user_profile.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/island.dart';
import '../widgets/premium.dart';
import '../widgets/state_message.dart';
import 'flashcards_screen.dart';
import 'page_route.dart';
import 'profile_screen.dart';
import 'quiz_screen.dart';

/// Learn tab: the personal plan (score, weak topics, AI quiz), flashcards, a carousel of lesson cards and the full list.
class LessonsScreen extends StatefulWidget {
  const LessonsScreen({
    super.key,
    QuizStore? store,
    this.bundle,
    this.initialLang,
    this.llm = const LlmApi(),
  }) : _store = store;
  final QuizStore? _store;
  final AssetBundle? bundle;
  final LlmClient llm;

  /// Null = follow the app-wide language.
  final String? initialLang;
  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

const _icons = <String, IconData>{
  'otp': Icons.sms_rounded,
  'upi_pin': Icons.pin_rounded,
  'atm_pin': Icons.atm_rounded,
  'qr': Icons.qr_code_scanner_rounded,
  'digital_arrest': Icons.local_police_rounded,
  'kyc': Icons.badge_rounded,
  'courier': Icons.local_shipping_rounded,
  'loan_app': Icons.request_quote_rounded,
  'electricity_bill': Icons.bolt_rounded,
  'sim_swap': Icons.sim_card_rounded,
  'customer_care': Icons.support_agent_rounded,
  'upi_collect': Icons.request_page_rounded,
  'task_job': Icons.work_rounded,
  'sextortion': Icons.videocam_off_rounded,
  'lottery': Icons.card_giftcard_rounded,
  'family_emergency': Icons.family_restroom_rounded,
  'phishing_link': Icons.link_off_rounded,
};

/// The details reminder shows at most once per app run, so it helps without nagging.
bool _remindedThisRun = false;

class _LessonsScreenState extends State<LessonsScreen> {
  late final QuizStore _store = widget._store ?? PrefsQuizStore();
  late String _lang = widget.initialLang ?? AppLanguage.code;
  String? _lastGlobal;
  QuizEngine? _engine;
  bool _failed = false;
  bool get _aiReady => LlmStatus.ready.value;

  @override
  void initState() {
    super.initState();
    LlmStatus.ready.addListener(_onAi);
    _load();
  }

  void _onAi() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    LlmStatus.ready.removeListener(_onAi);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final g = AppLanguage.of(context);
    if (_lastGlobal == null) {
      if (widget.initialLang == null) _setLang(g);
    } else if (g != _lastGlobal) {
      _setLang(g);
    }
    _lastGlobal = g;
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

  void _setLang(String l) {
    if (l == _lang) return;
    setState(() {
      _lang = l;
      _engine = null;
      _failed = false;
    });
    _load();
  }

  String _l(String k, [Map<String, Object?> a = const {}]) => learnT(_lang, k, a);

  /// Opens a lesson (cards first) or, from the plan card, straight into the quiz.
  /// Before an AI quiz with name / date of birth / gender missing, an island sheet offers to add them (once per run).
  Future<void> _open(QuizEngine e, Lesson l, {bool quiz = false}) async {
    final prof = ProfileStore.profile.value;
    // The details only shape AI-written questions, so the reminder only shows when a model is ready.
    if (_aiReady && prof.missingForQuiz.isNotEmpty && !_remindedThisRun) {
      _remindedThisRun = true;
      final add = await _remind(prof);
      if (!mounted) return;
      if (add == true) {
        await pushTitled(context, shellT(_lang, 'tab_profile'), const ProfileScreen());
        if (!mounted) return;
      } else if (add == null) {
        return; // dismissed
      }
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => QuizScreen(lesson: l, engine: e, lang: _lang, llm: widget.llm, startWithQuiz: quiz),
    ));
    if (mounted) setState(() {});
  }

  Future<bool?> _remind(UserProfile prof) => showIslandSheet<bool>(context, builder: (ctx) {
        final th = Theme.of(ctx);
        final p = palOf(ctx);
        final st = th.extension<StatusColors>() ?? StatusColors.light;
        final missing = prof.missingForQuiz.toSet();
        Widget row(String key, String label, bool optional) {
          final done = !missing.contains(key) && !optional;
          return Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: Sp.l),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
            child: Row(children: [
              Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: done ? st.safe : p.muted, size: 22),
              const SizedBox(width: Sp.m),
              Expanded(child: Text(label, style: th.textTheme.bodyLarge?.copyWith(fontSize: 17))),
              Flexible(
                child: Text(done ? '' : _l(optional ? 'optional' : 'missing'),
                    textAlign: TextAlign.end,
                    style: th.textTheme.bodySmall?.copyWith(color: optional ? p.muted : st.suspicious, fontWeight: FontWeight.w600)),
              ),
            ]),
          );
        }

        String pt(String k) => profileT(_lang, k);
        return SingleChildScrollView(
          child: Column(key: const Key('quiz_reminder'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(alignment: Alignment.centerLeft, child: IconBadge(icon: Icons.person_add_alt_1_rounded, color: p.accent, tint: p.accentTint, size: 60, iconSize: 32)),
            const SizedBox(height: Sp.l),
            Text(_l('rem_t'), style: th.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: Sp.xs),
            Text(_l('rem_b'), style: th.textTheme.bodyLarge?.copyWith(color: p.muted, fontSize: 17)),
            const SizedBox(height: Sp.l),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ColoredBox(
                color: p.isDark ? const Color(0xFF2C2C2E) : p.page,
                child: Column(children: [
                  row('name', pt('name'), false),
                  row('dob', pt('dob'), false),
                  row('gender', pt('gender'), false),
                  row('work', pt('work'), (prof.occupation ?? '').isEmpty),
                ]),
              ),
            ),
            const SizedBox(height: Sp.l),
            FilledButton(key: const Key('reminder_add'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)), onPressed: () => Navigator.pop(ctx, true), child: Text(_l('rem_add'))),
            TextButton(key: const Key('reminder_skip'), style: TextButton.styleFrom(minimumSize: const Size.fromHeight(52)), onPressed: () => Navigator.pop(ctx, false), child: Text(_l('rem_skip'))),
          ]),
        );
      });

  /// The lesson to do next: the weakest practised topic, else the first unfinished, else the lowest best score.
  Lesson? _next(QuizEngine e, LearnPlan plan) {
    if (e.lessons.isEmpty) return null;
    for (final w in plan.weak) {
      for (final l in e.lessons) {
        if (l.id == w) return l;
      }
    }
    return e.lessons.firstWhere((l) => e.bestFor(l.id) == 0,
        orElse: () => e.lessons.reduce((a, b) => e.bestFor(b.id) < e.bestFor(a.id) ? b : a));
  }

  @override
  Widget build(BuildContext context) {
    final e = _engine;
    if (_failed) {
      return StateMessage(icon: Icons.cloud_off, title: LessonStrings.of(_lang)['error'], actionLabel: LessonStrings.of(_lang)['retry'], onAction: _retry);
    }
    if (e == null) return StateMessage(loading: true, title: LessonStrings.of(_lang)['loading']);
    if (e.lessons.isEmpty) {
      return StateMessage(icon: Icons.school, title: LessonStrings.of(_lang)['empty'], subtitle: LessonStrings.of(_lang)['emptyHint']);
    }
    return ValueListenableBuilder<LearnPlan>(
      valueListenable: LearnStore.plan,
      builder: (context, plan, _) {
        final next = _next(e, plan);
        final done = e.lessons.where((l) => e.bestFor(l.id) > 0).length;
        // Carousel: topics to practise first, then unfinished ones.
        final featured = [
          ...e.lessons.where((l) => plan.weak.contains(l.id)),
          ...e.lessons.where((l) => !plan.weak.contains(l.id) && e.bestFor(l.id) == 0),
          ...e.lessons.where((l) => !plan.weak.contains(l.id) && e.bestFor(l.id) > 0),
        ].take(5).toList();
        return ListView(
          key: const Key('lessons_list'),
          padding: const EdgeInsets.fromLTRB(0, Sp.s, 0, Sp.xl),
          children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: Sp.l), child: _planCard(context, e, plan, next)),
            const SizedBox(height: Sp.l),
            Padding(padding: const EdgeInsets.symmetric(horizontal: Sp.l), child: _deckCard(context, e, plan)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.l),
              child: Row(children: [
                Expanded(child: PSection(title: _l('lessons'))),
                Flexible(
                  child: Text(_l('done_of', {'x': done, 'y': e.lessons.length}),
                      textAlign: TextAlign.end, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palOf(context).muted)),
                ),
              ]),
            ),
            // Height comes from the tallest card, so titles and counts never clip at large text sizes.
            SingleChildScrollView(
              key: const Key('lesson_carousel'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.xs),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < featured.length; i++) ...[
                    if (i > 0) const SizedBox(width: Sp.m),
                    _lessonCard(context, e, plan, featured[i]),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: Sp.l),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.l),
              child: PGroup(children: [
                for (var i = 0; i < e.lessons.length; i++) _row(context, e, plan, e.lessons[i], i == e.lessons.length - 1),
              ]),
            ),
          ],
        );
      },
    );
  }

  Widget _planCard(BuildContext context, QuizEngine e, LearnPlan plan, Lesson? next) {
    final th = Theme.of(context);
    final p = palOf(context);
    final name = ProfileStore.profile.value.firstName;
    final weak = [
      for (final w in plan.weak.take(3))
        for (final l in e.lessons.where((l) => l.id == w)) l.title,
    ];
    final sub = plan.stats.isEmpty
        ? _l('plan_sub_none')
        : weak.isEmpty
            ? _l('plan_sub_strong')
            : _l('plan_sub_weak');
    const ink = Color(0xFFF5F5F7);
    return Container(
      key: const Key('learn_plan'),
      padding: const EdgeInsets.all(Sp.l + 4),
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0xFF1C1C1E) : const Color(0xFF1D1D1F),
        borderRadius: BorderRadius.circular(26),
        border: p.isDark ? Border.all(color: const Color(0xFF38383A)) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Semantics(
            label: '${LessonStrings.of(_lang)['scoreWord']} ${e.score}/100',
            excludeSemantics: true,
            child: RingProgress(
              value: e.score / 100,
              size: 84,
              stroke: 8,
              color: Pal.dark.accent,
              track: const Color(0xFF3A3A3C),
              child: Text('${e.score}', key: const Key('score_value'), style: th.textTheme.titleLarge?.copyWith(color: ink, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: Sp.l),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_l('plan_label'), style: th.textTheme.labelMedium?.copyWith(color: Pal.dark.accent, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Text(name == null ? _l('plan_title') : _l('plan_title_name', {'name': name}),
                  style: th.textTheme.titleLarge?.copyWith(color: ink, fontWeight: FontWeight.w700, height: 1.2)),
              const SizedBox(height: 2),
              Text(sub, style: th.textTheme.bodySmall?.copyWith(color: const Color(0xFFA1A1A6))),
            ]),
          ),
        ]),
        if (weak.isNotEmpty) ...[
          const SizedBox(height: Sp.l),
          Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
            for (final w in weak)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: 6),
                decoration: BoxDecoration(color: const Color(0x29FFB340), borderRadius: BorderRadius.circular(Rad.pill)),
                child: Text(w, style: th.textTheme.labelMedium?.copyWith(color: const Color(0xFFFFB340), fontSize: 16)),
              ),
          ]),
        ],
        if (next != null) ...[
          const SizedBox(height: Sp.l),
          FilledButton.icon(
            key: const Key('lessons_primary'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(kTouch),
              backgroundColor: Pal.dark.accent,
              foregroundColor: Colors.black,
            ),
            onPressed: () => _open(e, next, quiz: true),
            icon: Icon(_aiReady ? Icons.auto_awesome_rounded : Icons.play_arrow_rounded),
            label: Text('${_l(_aiReady ? 'ai_quiz' : 'quiz_btn')}: ${next.title}', textAlign: TextAlign.center),
          ),
          if (!_aiReady)
            Padding(
              padding: const EdgeInsets.only(top: Sp.s),
              child: Text(_l('no_model_hint'), textAlign: TextAlign.center, style: th.textTheme.bodySmall?.copyWith(color: const Color(0xFFA1A1A6), fontSize: 14)),
            ),
        ],
      ]),
    );
  }

  Widget _deckCard(BuildContext context, QuizEngine e, LearnPlan plan) {
    final th = Theme.of(context);
    final p = palOf(context);
    final n = plan.deck.isEmpty ? allLessonCards(e.lessons).length : plan.deck.length;
    return PCard(
      key: const Key('learn_flashcards'),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FlashcardsScreen(lessons: e.lessons, lang: _lang)));
        if (mounted) setState(() {});
      },
      child: Row(children: [
        SizedBox(
          width: 56,
          height: 56,
          child: Stack(children: [
            Positioned(
              left: 6,
              top: 0,
              child: Transform.rotate(
                angle: -0.14,
                child: Container(width: 40, height: 50, decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10))),
              ),
            ),
            Positioned(
              left: 10,
              top: 5,
              child: Container(
                width: 40,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(10)),
                child: Text('$n', style: th.textTheme.titleMedium?.copyWith(color: p.onAccent, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
        const SizedBox(width: Sp.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_l('deck_title'), style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text(plan.newCards > 0 ? _l('deck_new', {'n': plan.newCards}) : _l('deck_count', {'n': n}),
                style: th.textTheme.bodySmall?.copyWith(color: plan.newCards > 0 ? p.accent : p.muted)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: p.muted),
      ]),
    );
  }

  (String, Color, Color) _badge(BuildContext context, QuizEngine e, LearnPlan plan, Lesson l) {
    final p = palOf(context);
    final st = Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
    if (plan.weak.contains(l.id)) return (_l('badge_practise'), st.suspicious, st.suspicious.withValues(alpha: 0.14));
    if (e.bestFor(l.id) > 0) return (_l('badge_done'), st.safe, st.safe.withValues(alpha: 0.14));
    return (_l('badge_new'), p.accent, p.accentTint);
  }

  Widget _lessonCard(BuildContext context, QuizEngine e, LearnPlan plan, Lesson l) {
    final th = Theme.of(context);
    final p = palOf(context);
    final (tag, c, tint) = _badge(context, e, plan, l);
    final best = e.bestFor(l.id);
    return SizedBox(
      width: 220,
      child: PCard(
        key: Key('lesson_card_${l.id}'),
        padding: EdgeInsets.zero,
        radius: 24,
        onTap: () => _open(e, l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 112,
            color: tint,
            padding: const EdgeInsets.all(Sp.m + 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Icon(_icons[l.id] ?? Icons.school_rounded, size: 44, color: c),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Rad.pill)),
                child: Text(tag, style: th.textTheme.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(Sp.m + 2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(l.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.2)),
                const SizedBox(height: Sp.s),
                Text(_l('cards_q', {'c': l.cards.length, 'q': l.questions.length}), style: th.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: 14)),
                const SizedBox(height: Sp.s),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: best / 100, minHeight: 6, color: c, backgroundColor: p.hairline),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, QuizEngine e, LearnPlan plan, Lesson l, bool last) {
    final th = Theme.of(context);
    final p = palOf(context);
    final best = e.bestFor(l.id);
    final s = LessonStrings.of(_lang);
    final (_, c, tint) = _badge(context, e, plan, l);
    return InkWell(
      key: Key('lesson_${l.id}'),
      onTap: () => _open(e, l),
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.s),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF0F0F2)))),
        child: Row(children: [
          IconBadge(icon: _icons[l.id] ?? Icons.school_rounded, color: c, tint: tint, size: 44, iconSize: 24),
          const SizedBox(width: Sp.m),
          Expanded(flex: 3, child: Text(l.title, style: th.textTheme.titleMedium?.copyWith(fontSize: 17))),
          const SizedBox(width: Sp.s),
          Flexible(
            child: Text(best > 0 ? '$best%' : s['new'],
                key: Key('best_${l.id}'),
                textAlign: TextAlign.end,
                style: th.textTheme.titleSmall?.copyWith(color: best > 0 ? c : p.accent)),
          ),
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ]),
      ),
    );
  }
}
