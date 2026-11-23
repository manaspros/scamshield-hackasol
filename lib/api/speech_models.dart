import 'model_api.dart' show DeviceInfo;

/// One offline speech (Vosk) model; mirrors Kotlin `SttModelConfig.all` (same ids).
class SttModel {
  const SttModel({required this.id, required this.sizeMb, required this.minRamMb, required this.lang, required this.large});
  final String id;
  final int sizeMb, minRamMb;

  /// 'hi' (also used for Chhattisgarhi) or 'en'.
  final String lang;
  final bool large;

  String get sizeLabel => sizeMb >= 1000 ? '${(sizeMb / 1000).toStringAsFixed(1)} GB' : '$sizeMb MB';

  /// Zip + unzipped copy + headroom, like the native storage check.
  int get neededMb => sizeMb * 3;
}

const kSttModels = <SttModel>[
  SttModel(id: 'vosk-small-hi', sizeMb: 42, minRamMb: 0, lang: 'hi', large: false),
  SttModel(id: 'vosk-small-en-in', sizeMb: 36, minRamMb: 0, lang: 'en', large: false),
  SttModel(id: 'vosk-hi', sizeMb: 1500, minRamMb: 8000, lang: 'hi', large: true),
];

SttModel sttById(String? id) => kSttModels.firstWhere((m) => m.id == id, orElse: () => kSttModels.first);

/// Why [m] does not suit this phone, or null.
enum SttBlock { lowRam, lowStorage }

SttBlock? sttBlockFor(SttModel m, DeviceInfo d) {
  if (d.totalRamMb > 0 && d.totalRamMb < m.minRamMb) return SttBlock.lowRam;
  if (d.freeStorageMb > 0 && d.freeStorageMb < m.neededMb) return SttBlock.lowStorage;
  return null;
}

/// The small model in the app language: fast and accurate enough for a phone call. The large one is never the
/// default because it takes minutes per call even on 8 GB phones.
String recommendSttId(String appLang) => appLang == 'en' ? 'vosk-small-en-in' : 'vosk-small-hi';
