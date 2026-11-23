import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../learn/learn_plan.dart';
import '../l10n/strings_learn.dart';
import '../lessons/lesson_model.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/premium.dart';
import '../widgets/shell_bar.dart';

/// The user's flashcards: AI-made cards from past quizzes first, else every lesson card.
/// Tap flips the card; "I knew it" / "Review again" moves on (review-again cards come first next time).
class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({super.key, required this.lessons, required this.lang});
  final List<Lesson> lessons;
  final String lang;

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  late List<StudyCard> _deck;
  late final bool _personal;
  late final int _newCount;
  int _i = 0;
  bool _flipped = false;
  int _knew = 0;
  final _review = <String>{}; // fronts marked "review again" this round

  String _l(String k, [Map<String, Object?> a = const {}]) => learnT(widget.lang, k, a);

  @override
  void initState() {
    super.initState();
    final plan = LearnStore.plan.value;
    _personal = plan.deck.isNotEmpty;
    _newCount = plan.newCards;
    final src = _personal ? plan.deck : allLessonCards(widget.lessons);
    // Cards not yet known first, keeping their order (new AI cards are at the front of the deck).
    _deck = [...src.where((c) => !c.known), ...src.where((c) => c.known)];
    // Clear the "N new" badge after this frame: other screens listen to the plan and must not rebuild mid-build.
    if (plan.newCards > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => LearnStore.save(LearnStore.plan.value.copyWith(newCards: 0)));
    }
  }

  String _topicTitle(String id) => widget.lessons.where((l) => l.id == id).map((l) => l.title).firstOrNull ?? '';

  Future<void> _mark(bool knew) async {
    final c = _deck[_i];
    if (knew) {
      _knew++;
    } else {
      _review.add(c.front);
    }
    if (_personal) {
      final plan = LearnStore.plan.value;
      final deck = [
        for (final d in plan.deck) d.front == c.front ? d.withKnown(knew) : d,
      ];
      unawaited(LearnStore.save(plan.copyWith(deck: deck))); // in memory at once, disk write trails
    }
    if (!mounted) return;
    setState(() {
      _i++;
      _flipped = false;
    });
  }

  void _again() => setState(() {
        final again = _deck.where((c) => _review.contains(c.front)).toList();
        if (again.isNotEmpty) _deck = again;
        _review.clear();
        _i = 0;
        _knew = 0;
        _flipped = false;
      });

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final p = palOf(context);
    final done = _i >= _deck.length;
    return Scaffold(
      appBar: shellBar(titleText: _l('deck_title')),
      body: SafeArea(
        child: _deck.isEmpty
            ? Center(child: Text(_l('fc_empty'), style: th.textTheme.titleMedium))
            : done
                ? _doneView(th, p)
                : Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, 0),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            _l('fc_pos', {'i': _i + 1, 'n': _deck.length}) + (_newCount > 0 ? ' · ${_l('fc_new', {'n': _newCount})}' : ''),
                            key: const Key('fc_position'),
                            style: th.textTheme.titleSmall?.copyWith(color: p.muted),
                          ),
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: _i / _deck.length, minHeight: 6, backgroundColor: p.hairline),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(Sp.l),
                        child: GestureDetector(
                          key: const Key('fc_card'),
                          onTap: () => setState(() => _flipped = !_flipped),
                          child: _flipCard(th, p, _deck[_i]),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.l),
                      child: Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('fc_again'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(60),
                              foregroundColor: (th.extension<StatusColors>() ?? StatusColors.light).suspicious,
                              side: BorderSide(color: p.hairline, width: 2),
                            ),
                            onPressed: () => _mark(false),
                            icon: const Icon(Icons.replay_rounded),
                            label: Text(_l('fc_again')),
                          ),
                        ),
                        const SizedBox(width: Sp.m),
                        Expanded(
                          child: FilledButton.icon(
                            key: const Key('fc_knew'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(60),
                              backgroundColor: (th.extension<StatusColors>() ?? StatusColors.light).safe,
                              foregroundColor: p.isDark ? Colors.black : Colors.white,
                            ),
                            onPressed: () => _mark(true),
                            icon: const Icon(Icons.check_rounded),
                            label: Text(_l('fc_knew')),
                          ),
                        ),
                      ]),
                    ),
                  ]),
      ),
    );
  }

  Widget _flipCard(ThemeData th, Pal p, StudyCard c) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: _flipped ? 1 : 0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      builder: (context, t, _) {
        final back = t > 0.5;
        final angle = t * math.pi;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          child: back
              ? Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi), child: _back(th, p, c))
              : _front(th, p, c),
        );
      },
    );
  }

  Widget _front(ThemeData th, Pal p, StudyCard c) {
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    final topic = _topicTitle(c.topic);
    return PCard(
      key: const Key('fc_front'),
      radius: 28,
      padding: const EdgeInsets.all(Sp.xl),
      child: SizedBox.expand(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
            if (topic.isNotEmpty) _chip(th, topic, st.scam, st.scam.withValues(alpha: 0.12)),
            if (c.ai) _chip(th, _l('ai_tag'), p.accent, p.accentTint),
          ]),
          const SizedBox(height: Sp.l),
          Expanded(
            child: SingleChildScrollView(
              child: Text(c.front, style: th.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
            ),
          ),
          Row(children: [
            Icon(Icons.touch_app_rounded, size: 18, color: p.muted),
            const SizedBox(width: Sp.xs),
            Text(_l('fc_flip'), style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
          ]),
        ]),
      ),
    );
  }

  Widget _back(ThemeData th, Pal p, StudyCard c) => Container(
        key: const Key('fc_back'),
        decoration: BoxDecoration(
          color: p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFF1D1D1F),
          borderRadius: BorderRadius.circular(28),
          border: p.isDark ? Border.all(color: const Color(0xFF48484A)) : null,
        ),
        padding: const EdgeInsets.all(Sp.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.verified_user_rounded, color: StatusColors.dark.safe, size: 32),
          const SizedBox(height: Sp.l),
          Expanded(
            child: SingleChildScrollView(
              child: Text(c.back, style: th.textTheme.titleLarge?.copyWith(color: const Color(0xFFF5F5F7), height: 1.45, fontWeight: FontWeight.w500)),
            ),
          ),
          Text(_l('fc_flip_back'), style: th.textTheme.bodySmall?.copyWith(color: const Color(0xFFA1A1A6))),
        ]),
      );

  Widget _chip(ThemeData th, String s, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Rad.pill)),
        child: Text(s, style: th.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700, fontSize: 14)),
      );

  Widget _doneView(ThemeData th, Pal p) {
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          IconBadge(icon: Icons.emoji_events_rounded, color: st.safe, size: 84, iconSize: 44),
          const SizedBox(height: Sp.l),
          Text(_l('fc_done_t'), key: const Key('fc_done'), style: th.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: Sp.s),
          Text(_l('fc_done_s', {'k': _knew, 'n': _deck.length}), textAlign: TextAlign.center, style: th.textTheme.bodyLarge?.copyWith(color: p.muted)),
          const SizedBox(height: Sp.xl),
          FilledButton(key: const Key('fc_restart'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)), onPressed: _again, child: Text(_l('fc_restart'))),
          const SizedBox(height: Sp.s),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_l('back_learn')),
          ),
        ]),
      ),
    );
  }
}
