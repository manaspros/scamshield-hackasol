import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../learn/learn_plan.dart';
import '../l10n/strings_learn.dart';
import '../lessons/lesson_model.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/a11y.dart';
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
                            textAlign: TextAlign.center,
                            style: th.textTheme.titleSmall?.copyWith(color: p.muted, fontWeight: FontWeight.w600),
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
                        padding: const EdgeInsets.fromLTRB(Sp.l, Sp.l, Sp.l, Sp.l + 6),
                        // Centred, card-shaped (not the whole screen), with the next cards peeking behind it.
                        child: LayoutBuilder(builder: (context, box) {
                          final w = math.min(box.maxWidth, 440.0);
                          final h = math.min(box.maxHeight - 12, w * 1.3);
                          return Center(
                            child: SizedBox(
                              width: w,
                              height: h + 12,
                              child: Stack(clipBehavior: Clip.none, children: [
                                if (_deck.length - _i > 2) _peek(p, w, h, 12, 0.92),
                                if (_deck.length - _i > 1) _peek(p, w, h, 6, 0.96),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: 0,
                                  height: h,
                                  // TalkBack: the visible face as the label, "double-tap to flip" as the hint.
                                  child: Semantics(
                                    key: const Key('fc_card_sem'),
                                    button: true,
                                    label: _flipped ? _deck[_i].back : _deck[_i].front,
                                    onTapHint: _l('fc_flip_do'),
                                    onTap: () => setState(() => _flipped = !_flipped),
                                    excludeSemantics: true,
                                    child: GestureDetector(
                                      key: const Key('fc_card'),
                                      onTap: () => setState(() => _flipped = !_flipped),
                                      child: _flipCard(th, p, _deck[_i]),
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                          );
                        }),
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
      duration: motion(context, const Duration(milliseconds: 420)),
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

  /// A card edge peeking out under the current one: the deck has more to come.
  Widget _peek(Pal p, double w, double h, double dy, double scale) => Positioned(
        left: w * (1 - scale) / 2,
        right: w * (1 - scale) / 2,
        top: dy,
        height: h,
        child: Container(
          decoration: BoxDecoration(
            color: p.isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: p.hairline),
          ),
        ),
      );

  /// Text centred in the middle of a card face; scrolls when it is longer than the card.
  Widget _centred(Widget child) => LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(child: child),
          ),
        ),
      );

  Widget _front(ThemeData th, Pal p, StudyCard c) {
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    final topic = _topicTitle(c.topic);
    return PCard(
      key: const Key('fc_front'),
      radius: 28,
      padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.l, Sp.xl, Sp.l),
      child: SizedBox.expand(
        child: Column(children: [
          Wrap(alignment: WrapAlignment.center, spacing: Sp.s, runSpacing: Sp.s, children: [
            if (topic.isNotEmpty) _chip(th, topic, st.scam, st.scam.withValues(alpha: 0.12)),
            if (c.ai) _chip(th, _l('ai_tag'), p.accent, p.accentTint),
          ]),
          Expanded(
            child: _centred(Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.l),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                IconBadge(icon: Icons.help_outline_rounded, color: p.accent, tint: p.accentTint, size: 56, iconSize: 30),
                const SizedBox(height: Sp.l),
                Text(c.front,
                    textAlign: TextAlign.center,
                    style: th.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
              ]),
            )),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.touch_app_rounded, size: 18, color: p.muted),
            const SizedBox(width: Sp.xs),
            Flexible(child: Text(_l('fc_flip'), textAlign: TextAlign.center, style: th.textTheme.bodySmall?.copyWith(color: p.muted))),
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
        padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.l, Sp.xl, Sp.l),
        child: Column(children: [
          Expanded(
            child: _centred(Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.l),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: StatusColors.dark.safe.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: Icon(Icons.verified_user_rounded, color: StatusColors.dark.safe, size: 30),
                ),
                const SizedBox(height: Sp.l),
                Text(c.back,
                    textAlign: TextAlign.center,
                    style: th.textTheme.titleLarge
                        ?.copyWith(color: const Color(0xFFF5F5F7), height: 1.45, fontWeight: FontWeight.w500)),
              ]),
            )),
          ),
          Text(_l('fc_flip_back'), textAlign: TextAlign.center, style: th.textTheme.bodySmall?.copyWith(color: const Color(0xFFA1A1A6))),
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
