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
    this.isNew = false,
    this.note = const {},
  });

  factory ModelSpec.fromMap(Map<Object?, Object?> m) => ModelSpec(
        id: '${m['id']}',
        name: '${m['name']}',
        file: '${m['file']}',
        url: m['url'] as String?,
        sizeMb: (m['sizeMb'] as num?)?.toInt() ?? 0,
        minRamMb: (m['minRamMb'] as num?)?.toInt() ?? 0,
        tier: '${m['tier'] ?? 'balanced'}',
        isNew: m['isNew'] == true,
        note: {
          for (final e in ((m['note'] as Map?) ?? const {}).entries)
            if (e.value is String) '${e.key}': e.value as String,
        },
      );

  final String id, name, file, tier;
  final String? url;
  final int sizeMb, minRamMb;

  /// Shown with a NEW badge (set in models.json).
  final bool isNew;

  /// Optional one-line description per language from models.json (`{"en": "...", "hi": "..."}`).
  final Map<String, String> note;

  /// [note] in [lang], falling back to Hindi then English; null when models.json gave none.
  String? noteIn(String lang) => note[lang] ?? (lang == 'hne' ? note['hi'] : null) ?? note['en'];

  /// What native needs to download this model.
  Map<String, Object?> toArgs() =>
      {'modelId': id, 'name': name, 'file': file, 'url': url, 'sizeMb': sizeMb, 'minRamMb': minRamMb};

  bool get available => url != null;

  String get sizeLabel => sizeMb >= 1000 ? '${(sizeMb / 1000).toStringAsFixed(1)} GB' : '$sizeMb MB';
}

/// Built-in list (same as Kotlin `ModelCatalog.all`): used until the online models.json has been read.
const kFallbackCatalog = <ModelSpec>[
  ModelSpec(
      id: 'gemma3-270m',
      name: 'Gemma 3 · 270M',
      file: 'gemma3-270m-it-q8.task',
      url: 'https://github.com/AB527/open-model/releases/download/v1/gemma3-270m-it-q8.task',
      sizeMb: 304,
      minRamMb: 3000,
      tier: 'fast'),
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
  const ModelState({
    this.status = 'NOT_FOUND',
    this.modelId,
    this.installed = const [],
    this.message = '',
    this.file,
    this.files = const [],
  });
  factory ModelState.fromMap(Map<Object?, Object?> m) => ModelState(
        status: '${m['status'] ?? 'NOT_FOUND'}',
        modelId: m['modelId'] as String?,
        installed: [for (final e in (m['installed'] as List?) ?? const []) '$e'],
        message: '${m['message'] ?? ''}',
        file: m['file'] as String?,
        files: [for (final e in (m['files'] as List?) ?? const []) '$e'],
      );
  final String status, message;
  final String? modelId, file;

  /// Built-in ids present on the phone (native view) and every `.task` file name present.
  final List<String> installed, files;
  bool get ready => status == 'READY';

  /// The model in use, looked up in the live [catalog] by file name.
  String? idIn(List<ModelSpec> catalog) =>
      catalog.where((c) => c.file == file).map((c) => c.id).firstOrNull ?? modelId;

  bool isInstalled(ModelSpec m) => files.contains(m.file) || installed.contains(m.id);
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


  Future<DeviceInfo> device() async {
    final m = await _call<Map<Object?, Object?>>('device.info');
    return m == null ? const DeviceInfo() : DeviceInfo.fromMap(m);
  }

  Future<ModelState> state() async {
    final m = await _call<Map<Object?, Object?>>('modelStatus');
    return m == null ? const ModelState() : ModelState.fromMap(m);
  }

  Future<Map<Object?, Object?>> download(ModelSpec m) async =>
      await _call<Map<Object?, Object?>>('downloadModel', m.toArgs()) ?? {'status': 'ERROR', 'message': 'Not available'};

  /// Switches to an installed model (by file name) and reloads it.
  Future<ModelState> select(ModelSpec m) async {
    final r = await _call<Map<Object?, Object?>>('models.select', {'id': m.id, 'file': m.file});
    return r == null ? const ModelState() : ModelState.fromMap(r);
  }
}
