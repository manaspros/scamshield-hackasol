import 'package:flutter/services.dart';

/// One downloadable on-device model (mirrors Kotlin `ModelSpec`).
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.name,
    required this.file,
    required this.sizeMb,
    required this.minRamMb,
    required this.tier,
    this.url,
  });

  factory ModelSpec.fromMap(Map<Object?, Object?> m) => ModelSpec(
        id: '${m['id']}',
        name: '${m['name']}',
        file: '${m['file']}',
        url: m['url'] as String?,
        sizeMb: (m['sizeMb'] as num?)?.toInt() ?? 0,
        minRamMb: (m['minRamMb'] as num?)?.toInt() ?? 0,
        tier: '${m['tier'] ?? 'balanced'}',
      );

  final String id, name, file, tier;
  final String? url;
  final int sizeMb, minRamMb;

  bool get available => url != null;

  String get sizeLabel => sizeMb >= 1000 ? '${(sizeMb / 1000).toStringAsFixed(1)} GB' : '$sizeMb MB';
}

/// Same list as Kotlin `ModelCatalog.all`; used when the native side is missing (tests) or fails.
const kFallbackCatalog = <ModelSpec>[
  ModelSpec(id: 'gemma3-270m', name: 'Gemma 3 · 270M', file: 'gemma3-270m-it-q8.task', sizeMb: 300, minRamMb: 3000, tier: 'fast'),
  ModelSpec(
      id: 'gemma3-1b-int4',
      name: 'Gemma 3 · 1B',
      file: 'gemma3-1b-it-int4.task',
      url: 'https://github.com/AB527/open-model/releases/download/v1/gemma3-1b-it-int4.task',
      sizeMb: 555,
      minRamMb: 4000,
      tier: 'balanced'),
  ModelSpec(id: 'gemma3n-e2b', name: 'Gemma 3n · E2B', file: 'gemma-3n-E2B-it-int4.task', sizeMb: 3100, minRamMb: 8000, tier: 'best'),
];

const kModelHeadroomMb = 150;

/// Why a model can't be picked on this phone, or null when it can.
enum ModelBlock { notHosted, lowRam, lowStorage }

ModelBlock? blockFor(ModelSpec m, DeviceInfo d) {
  if (!m.available) return ModelBlock.notHosted;
  if (d.totalRamMb > 0 && d.totalRamMb < m.minRamMb) return ModelBlock.lowRam;
  if (d.freeStorageMb > 0 && d.freeStorageMb < m.sizeMb + kModelHeadroomMb) return ModelBlock.lowStorage;
  return null;
}

/// Largest hosted model that fits; the smallest hosted one when none does (mirrors Kotlin `ModelCatalog.recommend`).
String recommendModelId(List<ModelSpec> all, DeviceInfo d) {
  final hosted = all.where((m) => m.available).toList();
  if (hosted.isEmpty) return all.isEmpty ? '' : all.first.id;
  final fit = hosted.where((m) => blockFor(m, d) == null).toList();
  return (fit.isEmpty ? hosted.first : fit.last).id;
}

class DeviceInfo {
  const DeviceInfo({
    this.totalRamMb = 0,
    this.availRamMb = 0,
    this.freeStorageMb = 0,
    this.manufacturer = '',
    this.model = '',
    this.soc = '',
    this.release = '',
    this.recommendedId,
  });

  factory DeviceInfo.fromMap(Map<Object?, Object?> m) => DeviceInfo(
        totalRamMb: (m['totalRamMb'] as num?)?.toInt() ?? 0,
        availRamMb: (m['availRamMb'] as num?)?.toInt() ?? 0,
        freeStorageMb: (m['freeStorageMb'] as num?)?.toInt() ?? 0,
        manufacturer: '${m['manufacturer'] ?? ''}',
        model: '${m['model'] ?? ''}',
        soc: '${m['soc'] ?? ''}',
        release: '${m['release'] ?? ''}',
        recommendedId: m['recommendedId'] as String?,
      );

  final int totalRamMb, availRamMb, freeStorageMb;
  final String manufacturer, model, soc, release;
  final String? recommendedId;

  bool get known => totalRamMb > 0;

  /// "6 GB": rounded the way phones are sold (5.6 GB usable shows as 6 GB).
  String get ramLabel => totalRamMb <= 0 ? '—' : '${(totalRamMb / 1024).ceil()} GB';
  String get storageLabel => freeStorageMb <= 0 ? '—' : '${(freeStorageMb / 1024).floor()} GB';
  String get phoneLabel {
    final name = [manufacturer, model].where((s) => s.isNotEmpty).join(' ');
    final os = release.isEmpty ? '' : 'Android $release';
    return [name, os].where((s) => s.isNotEmpty).join(' · ');
  }
}

/// Model status as GemmaClassifier reports it.
class ModelState {
  const ModelState({this.status = 'NOT_FOUND', this.modelId, this.installed = const [], this.message = ''});
  factory ModelState.fromMap(Map<Object?, Object?> m) => ModelState(
        status: '${m['status'] ?? 'NOT_FOUND'}',
        modelId: m['modelId'] as String?,
        installed: [for (final e in (m['installed'] as List?) ?? const []) '$e'],
        message: '${m['message'] ?? ''}',
      );
  final String status, message;
  final String? modelId;
  final List<String> installed;
  bool get ready => status == 'READY';
}

class ModelApi {
  const ModelApi({this.ch = const MethodChannel('scamshield/api')});
  final MethodChannel ch;

  Future<T?> _call<T>(String m, [Object? a]) async {
    try {
      return await ch.invokeMethod<T>(m, a).timeout(const Duration(seconds: 3), onTimeout: () => null);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<List<ModelSpec>> catalog() async {
    final raw = await _call<List<Object?>>('models.catalog');
    if (raw == null || raw.isEmpty) return kFallbackCatalog;
    return [for (final m in raw) ModelSpec.fromMap((m as Map).cast<Object?, Object?>())];
  }

  Future<DeviceInfo> device() async {
    final m = await _call<Map<Object?, Object?>>('device.info');
    return m == null ? const DeviceInfo() : DeviceInfo.fromMap(m);
  }

  Future<ModelState> state() async {
    final m = await _call<Map<Object?, Object?>>('modelStatus');
    return m == null ? const ModelState() : ModelState.fromMap(m);
  }

  Future<Map<Object?, Object?>> download(String id) async =>
      await _call<Map<Object?, Object?>>('downloadModel', {'modelId': id}) ?? {'status': 'ERROR', 'message': 'Not available'};

  Future<ModelState> select(String id) async {
    final m = await _call<Map<Object?, Object?>>('models.select', {'id': id});
    return m == null ? const ModelState() : ModelState.fromMap(m);
  }
}
