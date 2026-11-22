import 'dart:convert';

import 'package:flutter/services.dart';

class Lesson {
  final String id;
  final String title;
  final List<LessonCard> cards;
  final List<QuizQuestion> questions;

  const Lesson({
    required this.id,
    required this.title,
    required this.cards,
    required this.questions,
  });

  factory Lesson.fromJson(Map<String, dynamic> json) => Lesson(
        id: json['id'] as String,
        title: json['title'] as String,
        cards: (json['cards'] as List<dynamic>)
            .map((item) => LessonCard.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        questions: (json['questions'] as List<dynamic>)
            .map((item) => QuizQuestion.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class LessonCard {
  final String title;
  final String body;

  const LessonCard({required this.title, required this.body});

  factory LessonCard.fromJson(Map<String, dynamic> json) => LessonCard(
        title: json['title'] as String,
        body: json['body'] as String,
      );
}

class QuizQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const QuizQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
        question: json['question'] as String,
        options: (json['options'] as List<dynamic>).cast<String>(),
        correctIndex: json['correctIndex'] as int,
        explanation: json['explanation'] as String,
      );
}

/// Parses a language file without depending on Flutter's asset bundle.
List<Lesson> loadLessonsFromJson(String source) {
  final decoded = jsonDecode(source) as Map<String, dynamic>;
  return (decoded['lessons'] as List<dynamic>)
      .map((item) => Lesson.fromJson(item as Map<String, dynamic>))
      .toList(growable: false);
}

/// Loads a language file packaged in the app's asset bundle.
Future<List<Lesson>> loadLessonsFromAssets(
  String language, {
  AssetBundle? bundle,
}) async =>
    loadLessonsFromJson(
      await (bundle ?? rootBundle).loadString('assets/lessons/$language.json'),
    );
