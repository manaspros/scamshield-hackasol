import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/screens/live_feed_screen.dart';
import 'package:scamshield/screens/try_api_screen.dart';
import 'package:scamshield/theme/app_theme.dart';
import 'package:scamshield/theme/tokens.dart';
import 'package:scamshield/widgets/a11y.dart';
import 'package:scamshield/widgets/island.dart';

import 'qa/qa_harness.dart';

// WCAG 2.x relative luminance / contrast ratio.
double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Widget _app(Widget home, {bool announce = false, bool screenReader = false, bool noMotion = false}) => MaterialApp(
      theme: AppTheme.light(),
      builder: (c, w) => LangScope(
        notifier: AppLanguage.current,
        child: MediaQuery(
          data: MediaQuery.of(c).copyWith(
            supportsAnnounce: announce,
            accessibleNavigation: screenReader,
            disableAnimations: noMotion,
          ),
          child: w!,
        ),
      ),
      home: Scaffold(body: home),
    );

Map<String, Object?> _verdict(String label, {String text = 'OTP bata dijiye'}) => {
      'type': 'verdict',
      'text': text,
      'label': label,
      'confidence': 0.9,
      'reason': 'OTP maanga ja raha hai',
      'triggers': ['OTP bata'],
      'engine': 'rules-only',
      'latencyMs': 5,
      'source': 'caption',
      'callRisk': 0.8,
      'callLevel': label,
    };

Map<String, Object?> _result(String label) => _verdict(label)..remove('type');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppLanguage.debugSet('en'));
  tearDown(() => AppLanguage.debugSet('hi'));

  group('contrast of the changed tokens', () {
    test('contrast helper matches the WCAG reference values', () {
      expect(contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)), closeTo(21, 0.01));
      expect(contrast(const Color(0xFFE0E0E0), const Color(0xFFFFFFFF)), closeTo(1.32, 0.01)); // the old outline
    });

    test('light muted text is >= 4.5:1 on page, surfaces, the segmented fill and accent tints', () {
      const p = Pal.light;
      final fills = <String, Color>{
        'page': p.page,
        'surface': p.surface,
        'surfaceAlt': p.surfaceAlt,
        'segmented #EEEEF1': const Color(0xFFEEEEF1),
        'accentTint over surface': Color.alphaBlend(p.accentTint, p.surface),
        'accentTint over page': Color.alphaBlend(p.accentTint, p.page),
      };
      fills.forEach((name, bg) => expect(contrast(p.muted, bg), greaterThanOrEqualTo(4.5), reason: 'muted on $name'));
      // still reads as secondary: clearly lighter than ink
      expect(contrast(p.ink, p.surface) - contrast(p.muted, p.surface), greaterThan(8));
    });

    test('dark muted text is >= 4.5:1 on its fills', () {
      const p = Pal.dark;
      for (final bg in [p.page, p.surface, p.surfaceAlt, const Color(0xFF2C2C2E), Color.alphaBlend(p.accentTint, p.surface)]) {
        expect(contrast(p.muted, bg), greaterThanOrEqualTo(4.5), reason: 'muted on $bg');
      }
    });

    for (final (name, p) in [('light', Pal.light), ('dark', Pal.dark)]) {
      test('$name input outline is >= 3:1 against the field fill and the page (WCAG 1.4.11)', () {
        expect(contrast(p.fieldLine, p.surface), greaterThanOrEqualTo(3.0));
        expect(contrast(p.fieldLine, p.page), greaterThanOrEqualTo(3.0));
      });
    }

    testWidgets('text fields use the strong outline, not the hairline', (t) async {
      for (final (theme, p) in [(AppTheme.light(), Pal.light), (AppTheme.dark(), Pal.dark)]) {
        final b = theme.inputDecorationTheme.enabledBorder as OutlineInputBorder;
        expect(b.borderSide.color, p.fieldLine);
      }
    });
  });

  group('reduced motion', () {
    testWidgets('motion() is zero when animations are off, unchanged otherwise', (t) async {
      const d = Duration(milliseconds: 300);
      late Duration on, off;
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(),
        child: Builder(builder: (c) {
          on = motion(c, d);
          return const SizedBox();
        }),
      ));
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(builder: (c) {
          off = motion(c, d);
          return const SizedBox();
        }),
      ));
      expect(on, d);
      expect(off, Duration.zero);
    });
  });

  group('island toast', () {
    Future<void> toast(WidgetTester t, {required bool screenReader}) async {
      await t.pumpWidget(_app(
        Builder(
          builder: (c) => TextButton(onPressed: () => showIsland(c, 'Saved. ' * 20), child: const Text('go')),
        ),
        screenReader: screenReader,
      ));
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
    }

    Finder msg() => find.textContaining('Saved.');

    testWidgets('leaves after 3 s by default', (t) async {
      await toast(t, screenReader: false);
      expect(msg(), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(msg(), findsNothing);
    });

    testWidgets('stays at least 10 s with TalkBack on, and is never clipped', (t) async {
      await toast(t, screenReader: true);
      final text = t.widget<Text>(msg());
      expect(text.maxLines, isNull);
      expect(text.overflow, isNull);
      await t.pump(const Duration(seconds: 9));
      expect(msg(), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(msg(), findsNothing);
    });
  });

  testWidgets('island menu: own route for TalkBack and a labelled close layer', (t) async {
    final sem = t.ensureSemantics();
    String? picked;
    await t.pumpWidget(_app(Center(
      child: IslandMenu<String>(
        header: 'Pick one',
        items: const [IslandMenuItem(value: 'a', label: 'Apple')],
        onSelected: (v) => picked = v,
        builder: (c, open, toggle) => TextButton(onPressed: toggle, child: const Text('open')),
      ),
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final dismiss = find.byKey(const Key('island_menu_dismiss'));
    expect(t.getSemantics(dismiss), isSemantics(label: 'Close', isButton: true, hasTapAction: true, hasDismissAction: true));
    expect(find.bySemanticsLabel('Pick one'), findsWidgets); // names the route
    await t.tap(dismiss);
    await t.pumpAndSettle();
    expect(find.text('Apple'), findsNothing);
    expect(picked, isNull);
    sem.dispose();
  });

  group('announcements', () {
    testWidgets('Check: a new verdict is announced once (headline + first advice), not on rebuild', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      FakeChannel('scamshield/api', (c) async => c.method == 'classify' ? _result('SCAM') : null).install();
      final sem = t.ensureSemantics();
      await t.pumpWidget(_app(const TryApiScreen(), announce: true));
      t.takeAnnouncements();

      await t.enterText(find.byType(TextField).first, 'OTP bata dijiye');
      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
      final said = t.takeAnnouncements().map((a) => a.message).toList();
      expect(said, ['Scam!. Do not send money, hang up']);

      // Android path: the card is a live region whose label is the same sentence.
      final live = find.byType(LiveAnnounce);
      expect(live, findsOneWidget);
      expect(t.getSemantics(live), isSemantics(isLiveRegion: true, label: 'Scam!. Do not send money, hang up'));

      // A rebuild (typing) says nothing more.
      await t.enterText(find.byType(TextField).first, 'something else');
      await t.pumpAndSettle();
      expect(t.takeAnnouncements(), isEmpty);

      // The same verdict again is a new check: announced again.
      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
      expect(t.takeAnnouncements().map((a) => a.message), ['Scam!. Do not send money, hang up']);
      sem.dispose();
    });

    testWidgets('Check: the failed state is announced', (t) async {
      FakeChannel('scamshield/api', (c) async => throw PlatformException(code: 'X')).install();
      await t.pumpWidget(_app(const TryApiScreen(), announce: true));
      await t.enterText(find.byType(TextField).first, 'hello');
      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
      expect(t.takeAnnouncements().map((a) => a.message), ['Could not check. Please try again.']);
    });

    testWidgets('No announcement events where the platform does not support them (Android)', (t) async {
      FakeChannel('scamshield/api', (c) async => c.method == 'classify' ? _result('SCAM') : null).install();
      await t.pumpWidget(_app(const TryApiScreen()));
      await t.enterText(find.byType(TextField).first, 'OTP bata dijiye');
      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
      expect(t.takeAnnouncements(), isEmpty);
    });

    testWidgets('Live feed: speaks a verdict when it changes, not for every same-level statement', (t) async {
      final emit = fakeEvents();
      final sem = t.ensureSemantics();
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(const LiveFeedScreen(), announce: true));
      await t.pumpAndSettle();
      t.takeAnnouncements();

      emit({'type': 'call', 'active': true});
      emit(_verdict('SUSPICIOUS'));
      await t.pumpAndSettle();
      expect(t.takeAnnouncements().map((a) => a.message), ['Be careful. Do not rush, hang up']);

      emit(_verdict('SUSPICIOUS', text: 'another line'));
      await t.pumpAndSettle();
      expect(t.takeAnnouncements(), isEmpty, reason: 'same level, same words: no repeat');

      emit(_verdict('SCAM'));
      await t.pumpAndSettle();
      expect(t.takeAnnouncements().map((a) => a.message), ['Scam!. Do not send money, hang up']);
      expect(t.getSemantics(find.byKey(const Key('live_announce'))),
          isSemantics(isLiveRegion: true, label: 'Scam!. Do not send money, hang up'));

      emit({'type': 'signal', 'kind': 'otp_during_call', 'trigger': 'OTP'});
      await t.pumpAndSettle();
      expect(t.takeAnnouncements().map((a) => a.message), [startsWith('An OTP arrived')]);
      sem.dispose();
    });
  });
}
