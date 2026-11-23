import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/api/llm_api.dart';
import 'package:scamshield/api/model_api.dart';
import 'package:scamshield/api/model_catalog.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/lessons/quiz_engine.dart';
import 'package:scamshield/profile/user_profile.dart';
import 'package:scamshield/screens/lessons_screen.dart';
import 'package:scamshield/screens/model_picker_screen.dart';
import 'package:scamshield/screens/profile_screen.dart';
import 'package:scamshield/screens/quiz_screen.dart';
import 'package:scamshield/theme/app_theme.dart';

import 'qa/qa_harness.dart';

Future<void> _pump(WidgetTester t, Widget w, {bool dark = false}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    builder: (c, child) => LangScope(notifier: AppLanguage.current, child: child!),
    home: Scaffold(body: w),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

final _prefs = <String, String>{};

void _native({Map<String, Object?>? device, Map<String, Object?>? model}) {
  _prefs.clear();
  FakeChannel('scamshield/api', (c) async => switch (c.method) {
        'models.catalog' => [
            {'id': 'gemma3-270m', 'name': 'Gemma 3 · 270M', 'file': 'a.task', 'url': null, 'sizeMb': 300, 'minRamMb': 3000, 'tier': 'fast'},
            {'id': 'gemma3-1b-int4', 'name': 'Gemma 3 · 1B', 'file': 'b.task', 'url': 'https://x/b.task', 'sizeMb': 555, 'minRamMb': 4000, 'tier': 'balanced'},
            {'id': 'gemma3n-e2b', 'name': 'Gemma 3n · E2B', 'file': 'c.task', 'url': 'https://x/c.task', 'sizeMb': 3100, 'minRamMb': 8000, 'tier': 'best'},
          ],
        'device.info' => device ??
            {'totalRamMb': 5800, 'freeStorageMb': 21000, 'manufacturer': 'Xiaomi', 'model': 'Redmi Note 12', 'soc': 'SM6225', 'release': '14'},
        'modelStatus' => model ?? {'status': 'NOT_FOUND', 'installed': <Object?>[]},
        'downloadModel' => {'status': 'PENDING', 'modelId': (c.arguments as Map)['modelId']},
        'downloadStatus' => {'status': 'IDLE'},
        'getSettings' => {'wifiOnly': true},
        'serviceStatus' => {'enabled': true, 'connected': true},
        'perm.notificationsGranted' || 'perm.notificationAccessGranted' => true,
        _ => null,
      }).install();
  FakeChannel('scamshield/family', (c) async => c.method == 'family.status' ? {'paired': true} : null).install();
  FakeChannel('scamshield/prefs', (c) async {
    final a = (c.arguments as Map?) ?? const {};
    if (c.method == 'setString') _prefs['${a['key']}'] = '${a['value']}';
    return c.method == 'getString' ? _prefs['${a['key']}'] : null;
  }).install();
}

void main() {
  setUp(() => AppLanguage.debugSet('en'));

  group('profile', () {
    testWidgets('PROFILE_editName_savesAndShowsInHeader_completenessUpdates', (t) async {
      _native();
      await _pump(t, const ProfileScreen());
      expect(find.text('Add your name'), findsOneWidget);
      await t.tap(find.byKey(const Key('pf_name')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('pf_text_field')), 'Ramesh Sahu');
      await t.tap(find.byKey(const Key('pf_save')));
      await t.pumpAndSettle();
      expect(ProfileStore.profile.value.name, 'Ramesh Sahu');
      expect(find.text('Ramesh Sahu'), findsWidgets);
      expect(find.text('Profile 17% complete · finish'), findsOneWidget);
      expect(_prefs['profile_v1'], contains('Ramesh Sahu'));
      await t.pump(const Duration(seconds: 4)); // let the "Saved" island leave
      expect(t.takeException(), isNull);
    });

    testWidgets('PROFILE_gender_pickedFromIslandSheet', (t) async {
      _native();
      await _pump(t, const ProfileScreen());
      await t.tap(find.byKey(const Key('pf_gender')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pf_opt_female')));
      await t.pumpAndSettle();
      expect(ProfileStore.profile.value.gender, Gender.female);
      expect(find.text('Female'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('PROFILE_familyContact_addEditDelete', (t) async {
      _native();
      await _pump(t, const ProfileScreen());
      expect(find.text('Paired with a family phone'), findsOneWidget);
      await tapVisible(t, find.byKey(const Key('family_contact_add')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('fc_name')), 'Sunita');
      await t.enterText(find.byKey(const Key('fc_rel')), 'Daughter');
      await t.tap(find.byKey(const Key('fc_save')));
      await t.pumpAndSettle();
      expect(ProfileStore.contacts.value.single.name, 'Sunita');
      expect(_prefs['family_contacts_v1'], contains('Daughter'));
      await tapVisible(t, find.byKey(const Key('family_contact_0')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('fc_delete')));
      await t.pumpAndSettle();
      expect(ProfileStore.contacts.value, isEmpty);
    });

    testWidgets('PROFILE_noOverflow_dark_scale2', (t) async {
      _native();
      ProfileStore.debugSet(UserProfile(name: 'Ramesh Sahu', dob: DateTime(1964, 3, 14), gender: Gender.male, district: 'Raipur'),
          const [FamilyContact(name: 'Sunita', relation: 'Daughter')]);
      t.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(t.platformDispatcher.clearAllTestValues);
      AppLanguage.debugSet('hi');
      await _pump(t, const ProfileScreen(), dark: true);
      for (final k in ['pf_comfort', 'family_contact_0', 'profile_model', 'profile_settings']) {
        await reveal(t, find.byKey(Key(k)));
      }
      expect(t.takeException(), isNull);
    });
  });

  group('model picker', () {
    // What models.json would list: 270M not hosted, 1B and E2B hosted.
    const catalog = [
      ModelSpec(id: 'gemma3-270m', name: 'Gemma 3 · 270M', file: 'a.task', sizeMb: 300, minRamMb: 3000, tier: 'fast'),
      ModelSpec(id: 'gemma3-1b-int4', name: 'Gemma 3 · 1B', file: 'b.task', url: 'https://x/b.task', sizeMb: 555, minRamMb: 4000, tier: 'balanced'),
      ModelSpec(id: 'gemma3n-e2b', name: 'Gemma 3n · E2B', file: 'c.task', url: 'https://x/c.task', sizeMb: 3100, minRamMb: 8000, tier: 'best'),
    ];
    setUp(() {
      ModelCatalogStore.debugReset();
      ModelCatalogStore.models.value = catalog;
      ModelCatalogStore.links.value = {'gemma3-1b-int4': LinkStatus.ok, 'gemma3n-e2b': LinkStatus.ok};
    });

    test('MODEL_manifest_parsesValidEntries_skipsUnsafeOnes', () {
      final list = parseManifest('{"models":['
          '{"id":"a","name":"A","file":"a.task","url":"https://x/a.task","sizeMb":300,"minRamMb":3000,"tier":"fast","isNew":true,"note":{"en":"tiny"}},'
          '{"id":"b","name":"B","file":"../evil.task","url":"https://x/b"},'
          '{"id":"c","name":"C","file":"c.task","url":"http://insecure/c.task"},'
          '{"id":"a","name":"dup","file":"d.task"}'
          ']}')!;
      expect(list.map((m) => m.id), ['a']);
      expect(list.single.isNew, isTrue);
      expect(list.single.noteIn('hi'), 'tiny');
      expect(parseManifest('not json'), isNull);
      expect(parseManifest('{"models":[]}'), isNull);
    });

    test('MODEL_store_refreshReplacesList_andChecksLinks', () async {
      ModelCatalogStore.debugReset(withNet: _Net(
        manifest: '{"models":[{"id":"z","name":"Z","file":"z.task","url":"https://ok/z.task","sizeMb":100,"minRamMb":1000},'
            '{"id":"y","name":"Y","file":"y.task","url":"https://bad/y.task","sizeMb":100,"minRamMb":1000},'
            '{"id":"w","name":"W","file":"w.task","sizeMb":100,"minRamMb":1000}]}',
      ));
      expect(await ModelCatalogStore.refresh(), isTrue);
      expect(ModelCatalogStore.models.value.map((m) => m.id), ['z', 'y', 'w']);
      expect(ModelCatalogStore.updated.value, isNotNull);
      await ModelCatalogStore.checkLinks();
      expect(ModelCatalogStore.links.value, {'z': LinkStatus.ok, 'y': LinkStatus.broken, 'w': LinkStatus.none});
    });

    test('MODEL_store_offline_keepsBuiltInList_marksLinksOffline', () async {
      ModelCatalogStore.debugReset();
      expect(await ModelCatalogStore.refresh(), isFalse);
      expect(ModelCatalogStore.models.value, kFallbackCatalog);
      await ModelCatalogStore.checkLinks();
      expect(ModelCatalogStore.links.value['gemma3-1b-int4'], LinkStatus.offline);
    });

    testWidgets('MODEL_brokenLink_isShownAndCannotBeDownloaded', (t) async {
      _native();
      ModelCatalogStore.links.value = {'gemma3-1b-int4': LinkStatus.broken, 'gemma3n-e2b': LinkStatus.ok};
      await _pump(t, const ModelPickerScreen(listenToEvents: false, syncOnOpen: false));
      expect(find.text('Link not reachable'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('mp_action'))).onPressed, isNull);
    });

    testWidgets('MODEL_showsDevice_recommendsFittingModel_flagsTooBig_downloadsPicked', (t) async {
      _native();
      final calls = <MethodCall>[];
      FakeChannel('scamshield/api', (c) async {
        calls.add(c);
        return switch (c.method) {
          'models.catalog' => [
              {'id': 'gemma3-270m', 'name': 'Gemma 3 · 270M', 'file': 'a.task', 'url': null, 'sizeMb': 300, 'minRamMb': 3000, 'tier': 'fast'},
              {'id': 'gemma3-1b-int4', 'name': 'Gemma 3 · 1B', 'file': 'b.task', 'url': 'https://x/b.task', 'sizeMb': 555, 'minRamMb': 4000, 'tier': 'balanced'},
              {'id': 'gemma3n-e2b', 'name': 'Gemma 3n · E2B', 'file': 'c.task', 'url': 'https://x/c.task', 'sizeMb': 3100, 'minRamMb': 8000, 'tier': 'best'},
            ],
          'device.info' => {'totalRamMb': 5800, 'freeStorageMb': 21000, 'manufacturer': 'Xiaomi', 'model': 'Redmi Note 12', 'soc': 'SM6225', 'release': '14'},
          'modelStatus' => {'status': 'NOT_FOUND', 'installed': <Object?>[]},
          'downloadModel' => {'status': 'PENDING', 'done': 0, 'total': 0},
          'downloadStatus' => {'status': 'IDLE'},
          'getSettings' => {'wifiOnly': true},
          _ => null,
        };
      }).install();
      await _pump(t, const ModelPickerScreen(listenToEvents: false, syncOnOpen: false));
      expect(find.text('6 GB'), findsOneWidget);
      expect(find.text('SM6225'), findsOneWidget);
      expect(find.text('Xiaomi Redmi Note 12 · Android 14'), findsOneWidget);
      // picked by default: the recommended 1B
      expect(find.descendant(of: find.byKey(const Key('mp_dropdown')), matching: find.text('Gemma 3 · 1B')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('mp_dropdown')), matching: find.text('Recommended for your phone')), findsOneWidget);
      await t.tap(find.byKey(const Key('mp_dropdown')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('mp_opt_gemma3n-e2b')), findsOneWidget);
      expect(find.text('Needs 8 GB RAM'), findsOneWidget);
      expect(find.textContaining('Not available yet'), findsOneWidget); // 270M has no link in this list
      await t.tap(find.byKey(const Key('mp_opt_gemma3-270m'))); // disabled: nothing happens
      await t.pumpAndSettle();
      expect(find.byKey(const Key('mp_opt_gemma3-270m')), findsOneWidget, reason: 'disabled row keeps the island open');
      // Tag chips are 16 sp and wrap now, so the rows are taller: scroll the island to the row first.
      await t.ensureVisible(find.byKey(const Key('mp_opt_gemma3-1b-int4')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('mp_opt_gemma3-1b-int4')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('mp_action')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('mp_action')));
      await t.pump();
      final args = calls.where((c) => c.method == 'downloadModel').single.arguments as Map;
      expect(args['modelId'], 'gemma3-1b-int4');
      expect(args['url'], 'https://x/b.task');
      expect(args['file'], 'b.task');
      await t.pump(const Duration(seconds: 4));
      expect(t.takeException(), isNull);
    });

    testWidgets('MODEL_tooHeavy_asksBeforeDownloading', (t) async {
      _native(device: {'totalRamMb': 3500, 'freeStorageMb': 21000});
      await _pump(t, const ModelPickerScreen(listenToEvents: false, syncOnOpen: false));
      await t.ensureVisible(find.byKey(const Key('mp_action')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('mp_action')));
      await t.pumpAndSettle();
      expect(find.text('This model may be too heavy'), findsOneWidget);
    });
  });

  group('quiz reminder', () {
    testWidgets('REMINDER_aiReady_missingDetails_asksOnce_skipStartsQuiz', (t) async {
      _native(model: {'status': 'READY', 'installed': <Object?>[]});
      LlmStatus.ready.value = true;
      await _pump(t, LessonsScreen(store: InMemoryQuizStore(), bundle: DiskBundle(), llm: const NoLlm()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('lessons_primary')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('quiz_reminder')), findsOneWidget);
      expect(find.text('Make this quiz yours'), findsOneWidget);
      await t.tap(find.byKey(const Key('reminder_skip')));
      await t.pumpAndSettle();
      expect(find.byType(QuizScreen), findsOneWidget);
      expect(find.byKey(const Key('quiz_reminder')), findsNothing);
    });
  });
}

/// Scripted network: one manifest; any URL containing "ok" answers 200, others 404.
class _Net implements ModelNet {
  _Net({required this.manifest});
  final String manifest;
  @override
  Future<String?> getText(String url) async => manifest;
  @override
  Future<int?> status(String url) async => url.contains('//ok/') ? 200 : 404;
}
