import 'package:flutter/services.dart';

import '../models/verdict.dart';

/// One past SCAM / SUSPICIOUS verdict as the native log stores it: no message text, only the verdict facts.
class PastAlert {
  const PastAlert({
    required this.id,
    required this.tsMs,
    required this.source,
    required this.label,
    required this.confidence,
    required this.triggers,
    this.scamType,
  });

  factory PastAlert.fromMap(Map<Object?, Object?> m) => PastAlert(
        id: (m['id'] as num?)?.toInt() ?? 0,
        tsMs: (m['tsMs'] as num?)?.toInt() ?? 0,
        source: '${m['source'] ?? ''}',
        label: parseLabel(m['label']),
        confidence: ((m['confidence'] as num?) ?? 0).toDouble(),
        triggers: ((m['triggers'] as List?) ?? const []).map((e) => '$e').toList(),
        scamType: m['scamType'] as String?,
      );

  final int id, tsMs;
  final String source;
  final RiskLabel label;
  final double confidence;
  final List<String> triggers;
  final String? scamType;
}

enum AlertSort { newest, risk }

/// Keeps [only] (null = both) of the flagged verdicts; SAFE is never an alert.
List<PastAlert> filterAlerts(List<PastAlert> all, {RiskLabel? only}) =>
    [for (final a in all) if (a.label != RiskLabel.safe && (only == null || a.label == only)) a];

/// Newest first, or scam before suspicious, then higher confidence, then newest.
List<PastAlert> sortAlerts(List<PastAlert> list, AlertSort by) => [...list]..sort((a, b) {
    if (by == AlertSort.risk) {
      final r = b.label.index.compareTo(a.label.index);
      if (r != 0) return r;
      final c = b.confidence.compareTo(a.confidence);
      if (c != 0) return c;
    }
    return b.tsMs.compareTo(a.tsMs);
  });

/// What "Make evidence" built: the flagged events now inside the ZIP.
class EvidenceResult {
  const EvidenceResult(this.items);
  final List<PastAlert> items;
}

/// Protection switches the Home hero reports. Null fields mean "could not be read".
class Protection {
  const Protection({this.call, this.messages, this.alerts});
  final bool? call, messages, alerts;

  /// Key of the first critical item that is off, else null.
  String? get firstOff => call == false
      ? 'off_call'
      : messages == false
          ? 'off_msg'
          : alerts == false
              ? 'off_notif'
              : null;

  bool get known => call != null && messages != null && alerts != null;
}

/// Family code state for the Home card.
class FamilyCode {
  const FamilyCode({required this.code, required this.remainingSec});
  final String code;
  final int remainingSec;
}

/// Client for the channels behind the Home page. Every call returns null / false instead of throwing,
/// so a missing or failing native side shows an empty or error state rather than a crash.
class HomeApi {
  const HomeApi({
    this.api = const MethodChannel('scamshield/api'),
    this.handoff = const MethodChannel('scamshield/handoff'),
    this.family = const MethodChannel('scamshield/family'),
  });
  final MethodChannel api, handoff, family;

  Future<T?> _call<T>(MethodChannel ch, String m, [Object? args]) async {
    try {
      return await ch.invokeMethod<T>(m, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<Protection> protection() async {
    final s = await _call<Map<Object?, Object?>>(api, 'serviceStatus');
    final n = await _call<bool>(api, 'perm.notificationsGranted');
    final l = await _call<bool>(api, 'perm.notificationAccessGranted');
    return Protection(
      call: s == null ? null : s['enabled'] == true && s['connected'] == true,
      messages: l,
      alerts: n,
    );
  }

  /// Every logged SCAM / SUSPICIOUS verdict (unsorted), or null if the log cannot be read.
  Future<List<PastAlert>?> alerts() async {
    final raw = await _call<List<Object?>>(api, 'verdicts.recent', {'sinceMs': 0});
    if (raw == null) return null;
    return filterAlerts([for (final m in raw) PastAlert.fromMap((m as Map).cast<Object?, Object?>())]);
  }

  Future<Map<Object?, Object?>?> graph() async {
    final m = await _call<Map<Object?, Object?>>(handoff, 'graph.summary');
    return m?.cast<Object?, Object?>();
  }

  /// Builds the evidence ZIP (one event by [id], else the last 24 h). Null if the native side failed.
  Future<EvidenceResult?> makeEvidence({int? id}) async {
    final m = await _call<Map<Object?, Object?>>(handoff, 'evidence.make', {'id': id});
    if (m == null) return null;
    final items = (m['items'] as List?) ?? const [];
    return EvidenceResult([for (final e in items) PastAlert.fromMap((e as Map).cast<Object?, Object?>())]);
  }

  Future<bool> shareEvidence() async => await _call<bool>(handoff, 'evidence.share') ?? false;

  /// Opens the dialer on 1930 (DIAL only, the user places the call).
  Future<bool> dial1930() async => await _call<bool>(handoff, 'dial', {'number': '1930'}) ?? false;

  /// Null when not paired (or unreadable).
  Future<FamilyCode?> familyCode() async {
    final st = await _call<Map<Object?, Object?>>(family, 'family.status');
    if (st?['paired'] != true) return null;
    final m = await _call<Map<Object?, Object?>>(family, 'family.code');
    final code = m?['code'] as String?;
    if (code == null) return null;
    return FamilyCode(code: code, remainingSec: (m?['remainingSec'] as num?)?.toInt() ?? 30);
  }

  /// True when paired, false when not, null when unreadable.
  Future<bool?> familyPaired() async =>
      (await _call<Map<Object?, Object?>>(family, 'family.status'))?['paired'] as bool?;
}
