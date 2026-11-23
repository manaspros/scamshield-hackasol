import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/lessons/quiz_engine.dart';
import 'package:scamshield/screens/family_screen.dart';
import 'package:scamshield/screens/lessons_screen.dart';
import 'package:scamshield/screens/settings_screen.dart';
import 'package:scamshield/screens/setup_screen.dart';
import 'package:scamshield/screens/try_api_screen.dart';
import 'package:scamshield/widgets/verdict_card.dart';

import 'qa_harness.dart';

const _okVerdict = {
  'text': 'x', 'label': 'SCAM', 'confidence': 0.91, 'reason': 'asks for OTP',
  'triggers': ['OTP'], 'engine': 'rules', 'latencyMs': 5, 'source': 'manual',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final e in themes.entries) {
    final theme = e.value;

    testWidgets('QA_family_enterThenCode_noOverflow_${e.key}_scale2', (t) async {
      final fam = FakeChannel('scamshield/family', (c) async => switch (c.method) {
            'family.status' => {'paired': false},
            'family.newSecret' => 'ABCDEFGHIJKLMNOP',
            'family.setSecret' => null,
            'family.code' => {'code': '123456', 'remainingSec': 20},
            _ => null,
          })..install();
      await show(t, theme(), const FamilyScreen(initialLang: 'en'));
      await reveal(t, find.byKey(const Key('family_show')));
      expectTapTarget(t, find.byKey(const Key('family_show')));
      await reveal(t, find.byKey(const Key('family_enter')));
      expectTapTarget(t, find.byKey(const Key('family_enter')));

      // paired -> code view: reach it through "enter code"
      await tapVisible(t, find.byKey(const Key('family_enter')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('family_field')), 'abcd-efgh ijkl mnop');
      await tapVisible(t, find.byKey(const Key('family_save')));
      await t.pump(const Duration(milliseconds: 100));
      expect(fam.named('family.setSecret').single.arguments, {'secret': 'ABCDEFGHIJKLMNOP'});
      expect(find.byKey(const Key('family_code')), findsOneWidget);
      for (final k in ['family_yes', 'family_no', 'family_unpair']) {
        await tapVisible(t, find.byKey(Key(k)));
        if (k == 'family_unpair') {
          await tapVisible(t, find.byKey(const Key('family_unpair_confirm')));
          await t.pumpAndSettle();
        }
        expect(t.takeException(), isNull, reason: k);
      }
      // unpair returns to the chooser and calls native
      expect(fam.named('family.unpair'), hasLength(1));
      await reveal(t, find.byKey(const Key('family_show')));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('QA_family_enterSecret_noOverflow_${e.key}_scale2', (t) async {
      FakeChannel('scamshield/family', (c) async => c.method == 'family.status' ? {'paired': false} : null).install();
      await show(t, theme(), const FamilyScreen(initialLang: 'hi'));
      await tapVisible(t, find.byKey(const Key('family_enter')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('family_field')), 'abc'); // too short -> long Hindi error
      await tapVisible(t, find.byKey(const Key('family_save')));
      await t.pumpAndSettle();
      expect(find.textContaining('कोड सही नहीं है'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('QA_settings_toggles_noOverflow_${e.key}_scale2', (t) async {
      final api = FakeChannel('scamshield/api', (c) async {
        if (c.method == 'getSettings') return {'useLlm': true, 'captionPackages': 'com.x'};
        if (c.method == 'setSettings') return {'useLlm': true, 'overlayEnabled': true, 'captionPackages': 'com.x'};
        return null;
      })..install();
      await show(t, theme(), const SettingsScreen());
      expect(t.takeException(), isNull);
      expect(t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Use on-device Gemma')).value, isTrue);
      await reveal(t, find.widgetWithText(SwitchListTile, 'Show warning bubble'));
      expect(t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Show warning bubble')).value, isFalse);
      await tapVisible(t, find.widgetWithText(SwitchListTile, 'Show warning bubble'));
      await t.pumpAndSettle();
      expect(api.named('setSettings').single.arguments, {'overlayEnabled': true});
      await reveal(t, find.widgetWithText(SwitchListTile, 'Show warning bubble'));
      expect(t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Show warning bubble')).value, isTrue);
      // every switch is reachable at 2.0 scale
      for (final title in ['Use on-device Gemma', 'Show warning bubble', 'Auto-turn-on Live Caption',
        'Screen-reading fallback (OCR)', 'In-call scam signals', 'Call audio test on next call (experimental)',
        'Download model on Wi-Fi only', 'Discovery mode (debug)']) {
        final f = find.widgetWithText(SwitchListTile, title);
        await reveal(t, f);
        expectTapTarget(t, f);
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('QA_tryApi_analyse_noOverflow_${e.key}_scale2', (t) async {
      final api = FakeChannel('scamshield/api', (c) async => c.method == 'classify' ? _okVerdict : null)..install();
      await show(t, theme(), const TryApiScreen());
      await t.enterText(find.byType(TextField), 'OTP bata do');
      await tapVisible(t, find.text('Analyse'));
      await t.pumpAndSettle();
      expect(api.named('classify').single.arguments['text'], 'OTP bata do');
      expect(find.byType(VerdictCard), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('QA_setup_actionsTappable_${e.key}_scale2', (t) async {
      fakeEvents();
      final api = FakeChannel('scamshield/api', (c) async => switch (c.method) {
            'serviceStatus' => {'enabled': false, 'connected': false},
            'modelStatus' => {'status': 'MISSING', 'message': 'none'},
            'downloadStatus' => {'status': 'IDLE'},
            'micPermission' => false,
            'perm.notificationsGranted' => false,
            'perm.notificationAccessGranted' => false,
            _ => null,
          })..install();
      await show(t, theme(), const SetupScreen());
      await tapVisible(t, find.text('Open Accessibility'));
      await tapVisible(t, find.text('Open caption settings'));
      expect(api.named('openAccessibilitySettings'), hasLength(1));
      expect(api.named('openCaptionSettings'), hasLength(1));
      expect(t.takeException(), isNull);
    });

    testWidgets('QA_lessons_openLesson_${e.key}_scale2', (t) async {
      FakeChannel('scamshield/prefs', (_) async => null).install();
      await show(t, theme(), LessonsScreen(store: InMemoryQuizStore(), bundle: DiskBundle(), initialLang: 'en'));
      for (final id in ['otp', 'upi_pin', 'atm_pin', 'qr', 'digital_arrest', 'kyc', 'courier', 'loan_app']) {
        await reveal(t, find.byKey(Key('lesson_$id')));
        expectTapTarget(t, find.byKey(Key('lesson_$id')));
      }
      await t.scrollUntilVisible(find.byKey(const Key('lesson_otp')), -150, scrollable: find.byType(Scrollable).first);
      await tapVisible(t, find.byKey(const Key('lesson_otp')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('cards_next')), findsOneWidget); // lesson opened
      expect(t.takeException(), isNull);
    });

  }
}
