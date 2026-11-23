import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/l10n/app_language.dart';
import 'package:scamshield/lessons/quiz_engine.dart';
import 'package:scamshield/screens/lessons_screen.dart';

const _langs = ['en', 'hi', 'hne'];
const _newIds = [
  'electricity_bill',
  'sim_swap',
  'customer_care',
  'upi_collect',
  'task_job',
  'sextortion',
  'lottery',
  'family_emergency',
  'phishing_link',
];

List<Map<String, dynamic>> _lessons(String lang) =>
    ((jsonDecode(File('assets/lessons/$lang.json').readAsStringSync())
            as Map<String, dynamic>)['lessons'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(File(key).readAsBytesSync()));
}

void main() {
  test('R3_COV_lessons_allNewIdsPresentInAllLanguages', () {
    for (final lang in _langs) {
      final byId = {for (final l in _lessons(lang)) l['id'] as String: l};
      for (final id in _newIds) {
        final l = byId[id];
        expect(l, isNotNull, reason: '$lang/$id');
        expect((l!['cards'] as List).length, 2, reason: '$lang/$id');
        expect((l['questions'] as List).length, 1, reason: '$lang/$id');
        final text = jsonEncode(l);
        expect(text, contains('1930'), reason: '$lang/$id core rule');
      }
    }
  });

  test('R3_COV_lessons_keyParityAcrossLanguages', () {
    shape(String lang) => [
          for (final l in _lessons(lang))
            '${l['id']}:${(l['cards'] as List).length}:${(l['questions'] as List).length}',
        ];
    expect(shape('hi'), shape('en'));
    expect(shape('hne'), shape('en'));
    for (final lang in _langs) {
      final byId = {for (final l in _lessons(lang)) l['id'] as String: l};
      for (final id in ['qr', 'courier', 'loan_app']) {
        expect((byId[id]!['cards'] as List).length, 4, reason: '$lang/$id');
      }
    }
  });

  test('R3_COV_lessons_noRealLookingNumbers', () {
    final digitRun = RegExp(r'\d{6,}');
    final upiId = RegExp(r'\b[\w.\-]+@[\w.\-]+\b');
    final domain = RegExp(r'\b[\w\-]+\.(com|in|org|net|co|ly|io|me|xyz|app)\b');
    final url = RegExp(r'https?://|www\.');
    for (final lang in _langs) {
      final text = File('assets/lessons/$lang.json')
          .readAsStringSync()
          .replaceAll('cybercrime.gov.in', '')
          .replaceAll('1930', '');
      expect(digitRun.hasMatch(text), isFalse, reason: '$lang digit run');
      expect(upiId.hasMatch(text), isFalse, reason: '$lang upi id');
      expect(url.hasMatch(text), isFalse, reason: '$lang url');
      expect(domain.hasMatch(text), isFalse, reason: '$lang domain');
    }
  });

  testWidgets('R3_COV_lessons_hindiScreenRendersNewLessonTitle', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    AppLanguage.debugSet('hi');
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: LessonsScreen(store: InMemoryQuizStore(), bundle: _DiskBundle())),
    ));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('lesson_electricity_bill')), 200);
    expect(find.text('बिजली बिल धोखा'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
