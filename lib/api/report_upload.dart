import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The admin server (repo scamshield-admin on Vercel). Override at build time:
/// `flutter build apk --dart-define=REPORT_SERVER=https://… --dart-define=REPORT_KEY=…`
const kReportServer = String.fromEnvironment('REPORT_SERVER', defaultValue: 'https://scamshield-admin.vercel.app');
const kReportKey = String.fromEnvironment('REPORT_KEY');

/// Hides phone numbers, account / card numbers, OTPs and UPI IDs before a transcript leaves the phone.
String scrubTranscript(String s) => s
    .replaceAll(RegExp(r'[A-Za-z0-9._-]{2,}@[A-Za-z]{2,}'), '•••@•••') // UPI IDs and e-mails
    .replaceAll(RegExp(r'(?:\+?\d[\d\s-]{4,}\d)'), '•••'); // any run of 6+ digits, spaces or dashes allowed

/// What a user agreed to share about one checked call.
class CallReportUpload {
  const CallReportUpload({
    required this.district,
    required this.transcript,
    required this.llm,
    required this.ruleRisk,
    required this.userValidated,
    required this.lang,
    required this.appVersion,
  });
  final String district, transcript, lang, appVersion;

  /// The AI explanation (`CallExplanation.toJson()`), or the keyword result when no AI model was used.
  final Map<String, Object?> llm;
  final double ruleRisk;

  /// true: user said scam, false: not a scam, null: not sure.
  final bool? userValidated;

  Map<String, Object?> toJson() => {
        'district': district,
        'region': 'Chhattisgarh',
        'transcript': scrubTranscript(transcript),
        'llm': llm,
        'ruleRisk': ruleRisk,
        'userValidated': userValidated,
        'lang': lang,
        'appVersion': appVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
}

abstract class ReportSender {
  /// True when the server stored the report.
  Future<bool> send(CallReportUpload r);
}

class HttpReportSender implements ReportSender {
  const HttpReportSender({this.server = kReportServer, this.key = kReportKey});
  final String server, key;

  @override
  Future<bool> send(CallReportUpload r) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (await _post(r)) return true;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  Future<bool> _post(CallReportUpload r) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await c.postUrl(Uri.parse('$server/api/reports')).timeout(const Duration(seconds: 10));
      req.headers.contentType = ContentType.json;
      req.headers.set('x-app-key', key);
      req.add(utf8.encode(jsonEncode(r.toJson())));
      final res = await req.close().timeout(const Duration(seconds: 15));
      await res.drain<void>();
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      c.close(force: true);
    }
  }
}
