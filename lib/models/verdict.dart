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
  final String? scamType;

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
    this.scamType,
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
        scamType: m['scamType'] as String?,
      );

  /// "हिंदी · English" for a known scam type, else null (unknown or absent types show no chip).
  String? get scamTypeLabel {
    final l = _scamTypeLabels[scamType?.toUpperCase()];
    return l == null ? null : '${l.$1} · ${l.$2}';
  }

  int get percent => (confidence * 100).round();
  String get headline => 'This statement is ${label.title} · $percent%';
}

const _scamTypeLabels = <String, (String, String)>{
  'OTP': ('ओटीपी माँगना', 'OTP theft'),
  'KYC': ('केवाईसी धोखा', 'KYC fraud'),
  'DIGITAL_ARREST': ('डिजिटल अरेस्ट', 'Digital arrest'),
  'COURIER_CUSTOMS': ('कूरियर / कस्टम्स धोखा', 'Courier / customs'),
  'FAKE_QR': ('नकली क्यूआर', 'Fake QR'),
  'LOAN_APP': ('लोन ऐप धोखा', 'Loan app'),
  'INVESTMENT': ('निवेश धोखा', 'Investment fraud'),
  'JOB': ('नौकरी का झाँसा', 'Job scam'),
  'MISTAKEN_TRANSFER': ('गलती से भेजे पैसे', 'Mistaken transfer'),
  'ELECTRICITY_BILL': ('बिजली बिल धोखा', 'Electricity bill scam'),
  'SIM_SWAP': ('सिम ब्लॉक धोखा', 'SIM block scam'),
  'CUSTOMER_CARE': ('नकली कस्टमर केयर', 'Fake customer care'),
  'UPI_COLLECT': ('यूपीआई कलेक्ट धोखा', 'UPI collect scam'),
  'SEXTORTION': ('वीडियो ब्लैकमेल', 'Sextortion'),
  'LOTTERY': ('लॉटरी धोखा', 'Lottery scam'),
  'FAMILY_EMERGENCY': ('परिवार इमरजेंसी धोखा', 'Family emergency scam'),
  'PHISHING_LINK': ('फ़र्ज़ी लिंक', 'Phishing link'),
  'OTHER': ('अन्य धोखाधड़ी', 'Other scam'),
};
