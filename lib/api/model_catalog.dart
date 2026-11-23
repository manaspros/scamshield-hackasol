import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../lessons/prefs_store.dart';
import 'model_api.dart';

/// The online model list. Add or change models by editing this file in the GitHub release: no new APK needed.
const kModelManifestUrl = 'https://github.com/AB527/open-model/releases/download/v1/models.json';

/// Whether a model's download link works right now.
enum LinkStatus { checking, ok, broken, offline, none }

/// Network access for the catalog, swappable in tests.
abstract class ModelNet {
  /// Body of [url], or null on any network or HTTP error.
  Future<String?> getText(String url);

  /// HTTP status of [url] after redirects, or null when the network is unreachable.
  Future<int?> status(String url);
}

class IoModelNet implements ModelNet {
  const IoModelNet();
  static const _timeout = Duration(seconds: 10);

  HttpClient _client() => HttpClient()..connectionTimeout = _timeout;

  @override
  Future<String?> getText(String url) async {
    final c = _client();
    try {
      final req = await c.getUrl(Uri.parse(url)).timeout(_timeout);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return await res.transform(utf8.decoder).join().timeout(_timeout);
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }

  @override
  Future<int?> status(String url) async {
    final c = _client();
    try {
      var req = await c.openUrl('HEAD', Uri.parse(url)).timeout(_timeout);
      var res = await req.close().timeout(_timeout);
      await res.drain<void>();
      if (res.statusCode == 405 || res.statusCode == 403) {
        // Some hosts refuse HEAD: ask for the first byte instead.
        req = await c.getUrl(Uri.parse(url)).timeout(_timeout);
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        res = await req.close().timeout(_timeout);
        await res.drain<void>();
      }
      return res.statusCode;
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } on HandshakeException {
      return null;
    } catch (_) {
      return 0; // malformed URL or protocol error: treat as broken, not offline
    } finally {
      c.close(force: true);
    }
  }
}

/// Parses models.json: `{"models":[{id,name,file,url,sizeMb,minRamMb,tier,isNew,note:{en,hi}}]}`.
/// Entries without an id, a name or a safe `*.task` file name are skipped; null when nothing usable is left.
List<ModelSpec>? parseManifest(String? raw) {
  if (raw == null) return null;
  try {
    final m = jsonDecode(raw);
    final list = m is Map ? m['models'] : m;
    if (list is! List) return null;
    final safe = RegExp(r'^[A-Za-z0-9._-]{1,120}\.task$');
    final out = <ModelSpec>[];
    final ids = <String>{};
    for (final e in list) {
      if (e is! Map) continue;
      final s = ModelSpec.fromMap(e.cast<Object?, Object?>());
      if (s.id.isEmpty || s.id == 'null' || s.name.isEmpty || !safe.hasMatch(s.file) || !ids.add(s.id)) continue;
      if (s.url != null && !s.url!.startsWith('https://')) continue;
      out.add(s);
    }
    return out.isEmpty ? null : out;
  } on FormatException {
    return null;
  }
}

/// The live model list: built-in until the online models.json (or its cached copy) is read.
abstract final class ModelCatalogStore {
  static const prefsKey = 'models_v1';
  static final ValueNotifier<List<ModelSpec>> models = ValueNotifier(kFallbackCatalog);
  static final ValueNotifier<DateTime?> updated = ValueNotifier(null);
  static final ValueNotifier<Map<String, LinkStatus>> links = ValueNotifier(const {});
  static final ValueNotifier<bool> refreshing = ValueNotifier(false);

  static ModelNet net = const IoModelNet();
  static var _prefs = PrefsStrings();
  static bool _cacheRead = false;

  /// The last list saved on this phone, if any.
  static Future<void> loadCached() async {
    if (_cacheRead) return;
    _cacheRead = true;
    try {
      final raw = await _prefs.get(prefsKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map;
      final list = parseManifest(m['raw'] as String?);
      if (list != null) {
        models.value = list;
        updated.value = DateTime.fromMillisecondsSinceEpoch((m['at'] as num?)?.toInt() ?? 0);
      }
    } catch (_) {
      // corrupt cache: keep the built-in list
    }
  }

  /// Fetches models.json; on success it replaces the list and is cached. Returns whether it worked.
  static Future<bool> refresh() async {
    if (refreshing.value) return false;
    refreshing.value = true;
    try {
      final raw = await net.getText(kModelManifestUrl);
      final list = parseManifest(raw);
      if (list == null) return false;
      final now = DateTime.now();
      models.value = list;
      updated.value = now;
      unawaited(_prefs.set(prefsKey, jsonEncode({'at': now.millisecondsSinceEpoch, 'raw': raw})));
      return true;
    } finally {
      refreshing.value = false;
    }
  }

  /// Checks every download link at once; results arrive in [links] as they finish.
  static Future<void> checkLinks() async {
    final list = models.value;
    links.value = {for (final m in list) m.id: m.url == null ? LinkStatus.none : LinkStatus.checking};
    await Future.wait([
      for (final m in list.where((m) => m.url != null))
        net.status(m.url!).then((code) {
          final s = code == null
              ? LinkStatus.offline
              : code >= 200 && code < 400
                  ? LinkStatus.ok
                  : LinkStatus.broken;
          links.value = {...links.value, m.id: s};
        }),
    ]);
  }

  /// Cached list, then the online one, then the link checks.
  static Future<void> sync() async {
    await loadCached();
    await refresh();
    await checkLinks();
  }

  @visibleForTesting
  static void debugReset({ModelNet? withNet}) {
    _prefs = PrefsStrings();
    _cacheRead = true;
    net = withNet ?? const _OfflineNet();
    models.value = kFallbackCatalog;
    updated.value = null;
    links.value = const {};
    refreshing.value = false;
  }
}

/// Tests: no network at all.
class _OfflineNet implements ModelNet {
  const _OfflineNet();
  @override
  Future<String?> getText(String url) async => null;
  @override
  Future<int?> status(String url) async => null;
}
