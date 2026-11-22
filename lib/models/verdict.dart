import 'package:flutter/material.dart';

enum RiskLabel { safe, suspicious, scam }

RiskLabel parseLabel(Object? s) => switch ('$s'.toUpperCase()) {
      'SCAM' => RiskLabel.scam,
      'SUSPICIOUS' => RiskLabel.suspicious,
      _ => RiskLabel.safe,
    };

extension RiskLabelUi on RiskLabel {
  String get title => switch (this) {
        RiskLabel.safe => 'SAFE',
        RiskLabel.suspicious => 'SUSPICIOUS',
        RiskLabel.scam => 'SCAM',
      };
  String get hindi => switch (this) {
        RiskLabel.safe => 'सामान्य बातचीत',
        RiskLabel.suspicious => 'सावधान रहें',
        RiskLabel.scam => 'धोखाधड़ी हो सकती है',
      };
  Color get color => switch (this) {
        RiskLabel.safe => const Color(0xFF1B5E20),
        RiskLabel.suspicious => const Color(0xFFB45309),
        RiskLabel.scam => const Color(0xFFB71C1C),
      };
  IconData get icon => switch (this) {
        RiskLabel.safe => Icons.verified_user,
        RiskLabel.suspicious => Icons.warning_amber_rounded,
        RiskLabel.scam => Icons.dangerous,
      };
}

/// Result of the on-device Text API (rules + Gemma).
class Verdict {
  final String text;
  final RiskLabel label;
  final double confidence;
  final String reason;
  final List<String> triggers;
  final String engine;
  final int latencyMs;
  final String source;
  final bool preliminary;

  const Verdict({
    required this.text,
    required this.label,
    required this.confidence,
    required this.reason,
    required this.triggers,
    required this.engine,
    required this.latencyMs,
    required this.source,
    this.preliminary = false,
  });

  factory Verdict.fromMap(Map<Object?, Object?> m) => Verdict(
        text: (m['text'] as String?) ?? '',
        label: parseLabel(m['label']),
        confidence: ((m['confidence'] as num?) ?? 0).toDouble().clamp(0.0, 1.0),
        reason: (m['reason'] as String?) ?? '',
        triggers: ((m['triggers'] as List?) ?? const []).map((e) => '$e').toList(),
        engine: (m['engine'] as String?) ?? 'unknown',
        latencyMs: ((m['latencyMs'] as num?) ?? 0).toInt(),
        source: (m['source'] as String?) ?? 'manual',
        preliminary: (m['preliminary'] as bool?) ?? false,
      );

  int get percent => (confidence * 100).round();
  String get headline => 'This statement is ${label.title} · $percent%';
}
