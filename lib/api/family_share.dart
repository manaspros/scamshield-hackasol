import '../l10n/strings_home.dart';

/// Pre-written family message: scam type label and time only. Never takes message text, so it cannot leak any.
String familyShareText(String lang, String? typeLabel, int tsMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(tsMs);
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}'; // runs of 2 digits only
  return homeT(lang, 'fam_msg', {'type': typeLabel ?? homeT(lang, 'al_other'), 'time': time});
}
