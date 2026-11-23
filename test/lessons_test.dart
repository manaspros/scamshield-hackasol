import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/lessons/lesson_model.dart';

Map<String, dynamic> _readLanguage(String language) =>
    jsonDecode(File('assets/lessons/$language.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('T3_3_seventeenLessonsEightCoreNineNew', () {
    for (final language in ['en', 'hi', 'hne']) {
      final lessons = loadLessonsFromJson(
        File('assets/lessons/$language.json').readAsStringSync(),
      );
      expect(lessons, hasLength(17), reason: language);
      expect(lessons.take(8).every((l) => l.cards.length >= 3 && l.questions.length == 3), isTrue);
    }
  });

  test('T3_3_languageKeyParity', () {
    final languages = ['en', 'hi', 'hne'].map(_readLanguage).toList();
    final lessonLists = languages
        .map((data) => data['lessons'] as List<dynamic>)
        .toList();
    final expectedIds = (lessonLists.first)
        .map((lesson) => (lesson as Map<String, dynamic>)['id'])
        .toList();

    for (var languageIndex = 0;
        languageIndex < lessonLists.length;
        languageIndex++) {
      final lessons = lessonLists[languageIndex];
      expect(
        lessons.map((lesson) => (lesson as Map<String, dynamic>)['id']).toList(),
        expectedIds,
        reason: ['en', 'hi', 'hne'][languageIndex],
      );
      for (final rawLesson in lessons) {
        final lesson = rawLesson as Map<String, dynamic>;
        expect((lesson['cards'] as List<dynamic>).length, inInclusiveRange(2, 4));
        final questions = lesson['questions'] as List<dynamic>;
        expect(questions.length, inInclusiveRange(1, 3));
        for (final rawQuestion in questions) {
          final question = rawQuestion as Map<String, dynamic>;
          final options = question['options'] as List<dynamic>;
          final correctIndex = question['correctIndex'] as int;
          expect(options.length, inInclusiveRange(3, 4));
          expect(correctIndex, inInclusiveRange(0, options.length - 1));
        }
      }
    }
    expect(languages[2]['_verify'], 'VERIFY:hne native speaker sign-off (T3.6)');
  });
}
