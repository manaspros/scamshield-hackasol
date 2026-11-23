import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../lessons/prefs_store.dart';

/// One line of a saved chat.
class SavedLine {
  const SavedLine({required this.user, required this.text, this.voice = false, this.files = const []});
  final bool user, voice;
  final String text;

  /// Attachment indexes (into the interview's files) shown on this line.
  final List<int> files;

  Map<String, Object?> toJson() => {'u': user, 't': text, if (voice) 'v': true, if (files.isNotEmpty) 'f': files};

  factory SavedLine.fromJson(Map<String, Object?> m) => SavedLine(
        user: m['u'] == true,
        text: '${m['t'] ?? ''}',
        voice: m['v'] == true,
        files: [for (final i in (m['f'] as List?) ?? const []) if (i is num) i.toInt()],
      );
}

/// A report the user started: the interview answers, the chat, and when it was made. Kept on this phone only.
@immutable
class ReportRecord {
  const ReportRecord({
    required this.id,
    required this.createdMs,
    required this.updatedMs,
    required this.interview,
    this.lines = const [],
  });

  final String id;
  final int createdMs, updatedMs;

  /// [ReportInterview.toJson].
  final Map<String, Object?> interview;
  final List<SavedLine> lines;

  bool get lost => interview['lost'] == true;
  bool get finished => interview['finished'] == true;
  String? get scamType => interview['scamType'] as String?;
  Map<String, Object?> get answers => ((interview['answers'] as Map?) ?? const {}).cast<String, Object?>();
  Map<String, Object?> get labels => ((interview['labels'] as Map?) ?? const {}).cast<String, Object?>();
  List<String> get filePaths => [
        for (final f in (interview['files'] as List?) ?? const [])
          if (f is Map && f['path'] is String) f['path'] as String,
      ];

  ReportRecord copyWith({int? updatedMs, Map<String, Object?>? interview, List<SavedLine>? lines}) => ReportRecord(
        id: id,
        createdMs: createdMs,
        updatedMs: updatedMs ?? this.updatedMs,
        interview: interview ?? this.interview,
        lines: lines ?? this.lines,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'c': createdMs,
        'u': updatedMs,
        'iv': interview,
        'lines': [for (final l in lines) l.toJson()],
      };

  static ReportRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, Object?>();
    final id = m['id'], c = m['c'], iv = m['iv'];
    if (id is! String || c is! num || iv is! Map) return null;
    return ReportRecord(
      id: id,
      createdMs: c.toInt(),
      updatedMs: (m['u'] as num?)?.toInt() ?? c.toInt(),
      interview: iv.cast<String, Object?>(),
      lines: [
        for (final l in (m['lines'] as List?) ?? const [])
          if (l is Map) SavedLine.fromJson(l.cast<String, Object?>()),
      ],
    );
  }
}

/// Saved reports, newest first (pref `report_history_v1`). [items] notifies the history sheet.
class ReportHistory {
  ReportHistory._();
  static const key = 'report_history_v1';
  static const maxItems = 30;

  static var _prefs = PrefsStrings();
  static final ValueNotifier<List<ReportRecord>> items = ValueNotifier(const []);
  static bool _loaded = false;

  static Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    _loaded = true;
    try {
      final raw = await _prefs.get(key);
      final list = raw == null ? const [] : jsonDecode(raw) as List;
      items.value = List.unmodifiable([for (final e in list) ?ReportRecord.fromJson(e)]
        ..sort((a, b) => b.updatedMs.compareTo(a.updatedMs)));
    } on FormatException {
      items.value = const [];
    }
  }

  /// Inserts or replaces [r] (by id), newest first, keeping at most [maxItems].
  static Future<void> save(ReportRecord r) async {
    final next = [r, for (final e in items.value) if (e.id != r.id) e];
    final dropped = next.length > maxItems ? next.sublist(maxItems) : const <ReportRecord>[];
    items.value = List.unmodifiable(next.take(maxItems));
    for (final d in dropped) {
      _deleteFiles(d);
    }
    await _persist();
  }

  static Future<void> delete(String id) async {
    final gone = items.value.where((e) => e.id == id).toList();
    items.value = List.unmodifiable([for (final e in items.value) if (e.id != id) e]);
    for (final g in gone) {
      _deleteFiles(g);
    }
    await _persist();
  }

  static Future<void> _persist() => _prefs.set(key, jsonEncode([for (final e in items.value) e.toJson()]));

  // Screenshots belong to their report: they go when it goes.
  static void _deleteFiles(ReportRecord r) {
    for (final p in r.filePaths) {
      try {
        File(p).deleteSync();
      } on FileSystemException {
        // already gone
      }
    }
  }

  @visibleForTesting
  static void debugReset() {
    _prefs = PrefsStrings();
    _loaded = false;
    items.value = const [];
  }
}
