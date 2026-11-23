import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../lessons/prefs_store.dart';

enum Gender { male, female, other }

enum TechComfort { low, medium, high }

/// The user's own details, kept on this phone only (pref `profile_v1`; the district keeps its old `district` key).
/// Used for the greeting and to tailor AI quizzes and flashcards.
@immutable
class UserProfile {
  const UserProfile({this.name, this.dob, this.gender, this.district, this.phone, this.occupation, this.techComfort});

  final String? name, district, phone, occupation;
  final DateTime? dob;
  final Gender? gender;
  final TechComfort? techComfort;

  static const empty = UserProfile();

  /// Whole years on [now] (default: today), or null without a date of birth.
  int? ageOn([DateTime? now]) {
    final d = dob;
    if (d == null) return null;
    final n = now ?? DateTime.now();
    var a = n.year - d.year;
    if (n.month < d.month || (n.month == d.month && n.day < d.day)) a--;
    return a < 0 ? null : a;
  }

  String? get firstName {
    final n = name?.trim();
    if (n == null || n.isEmpty) return null;
    return n.split(RegExp(r'\s+')).first;
  }

  String get initials {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final f = parts.first.characters.first;
    final l = parts.length > 1 ? parts.last.characters.first : '';
    return (f + l).toUpperCase();
  }

  /// The details the AI quiz asks for before it starts (name, date of birth, gender).
  List<String> get missingForQuiz => [
        if ((name ?? '').trim().isEmpty) 'name',
        if (dob == null) 'dob',
        if (gender == null) 'gender',
      ];

  /// 0..1 over the six personal fields (phone is optional and not counted).
  double get completeness {
    var n = 0;
    if ((name ?? '').trim().isNotEmpty) n++;
    if (dob != null) n++;
    if (gender != null) n++;
    if ((district ?? '').isNotEmpty) n++;
    if ((occupation ?? '').trim().isNotEmpty) n++;
    if (techComfort != null) n++;
    return n / 6;
  }

  UserProfile copyWith({
    String? name,
    DateTime? dob,
    Gender? gender,
    String? district,
    String? phone,
    String? occupation,
    TechComfort? techComfort,
  }) =>
      UserProfile(
        name: name ?? this.name,
        dob: dob ?? this.dob,
        gender: gender ?? this.gender,
        district: district ?? this.district,
        phone: phone ?? this.phone,
        occupation: occupation ?? this.occupation,
        techComfort: techComfort ?? this.techComfort,
      );

  Map<String, Object?> toJson() => {
        if (name != null) 'name': name,
        if (dob != null) 'dob': dob!.toIso8601String().substring(0, 10),
        if (gender != null) 'gender': gender!.name,
        if (phone != null) 'phone': phone,
        if (occupation != null) 'occupation': occupation,
        if (techComfort != null) 'techComfort': techComfort!.name,
      };

  factory UserProfile.fromJson(Map<String, Object?> m, {String? district}) {
    T? pick<T extends Enum>(List<T> values, Object? v) {
      for (final e in values) {
        if (e.name == v) return e;
      }
      return null;
    }

    return UserProfile(
      name: m['name'] as String?,
      dob: DateTime.tryParse('${m['dob'] ?? ''}'),
      gender: pick(Gender.values, m['gender']),
      district: district,
      phone: m['phone'] as String?,
      occupation: m['occupation'] as String?,
      techComfort: pick(TechComfort.values, m['techComfort']),
    );
  }

  /// One plain-English line for an LLM prompt; never includes the name or phone number.
  String promptContext([DateTime? now]) {
    final a = ageOn(now);
    final parts = <String>[
      if (a != null) 'age $a${a >= 60 ? ' (senior citizen)' : ''}',
      if (gender != null) gender!.name,
      if ((occupation ?? '').trim().isNotEmpty) 'works as ${occupation!.trim()}',
      if ((district ?? '').isNotEmpty) 'lives in $district district, Chhattisgarh',
      if (techComfort != null) '${techComfort!.name} comfort with smartphones',
    ];
    return parts.isEmpty ? 'an adult smartphone user in India' : parts.join(', ');
  }
}

/// A family contact the user added by hand (name, relation, optional phone). On this phone only.
@immutable
class FamilyContact {
  const FamilyContact({required this.name, required this.relation, this.phone});
  final String name, relation;
  final String? phone;

  Map<String, Object?> toJson() => {'name': name, 'relation': relation, if (phone != null) 'phone': phone};

  factory FamilyContact.fromJson(Map<String, Object?> m) =>
      FamilyContact(name: '${m['name'] ?? ''}', relation: '${m['relation'] ?? ''}', phone: m['phone'] as String?);
}

/// Loads and saves the profile and family contacts; [profile] / [contacts] notify every screen that shows them.
class ProfileStore {
  ProfileStore._();
  static const profileKey = 'profile_v1', contactsKey = 'family_contacts_v1', districtKey = 'district';

  static var _prefs = PrefsStrings();
  static final ValueNotifier<UserProfile> profile = ValueNotifier(UserProfile.empty);
  static final ValueNotifier<List<FamilyContact>> contacts = ValueNotifier(const []);
  static bool _loaded = false;

  static Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    _loaded = true;
    try {
      final raw = await _prefs.get(profileKey);
      final district = await _prefs.get(districtKey);
      final m = raw == null ? const <String, Object?>{} : (jsonDecode(raw) as Map).cast<String, Object?>();
      profile.value = UserProfile.fromJson(m, district: district);
    } on FormatException {
      profile.value = UserProfile.empty;
    }
    try {
      final raw = await _prefs.get(contactsKey);
      contacts.value = raw == null
          ? const []
          : [for (final e in jsonDecode(raw) as List) FamilyContact.fromJson((e as Map).cast<String, Object?>())];
    } on FormatException {
      contacts.value = const [];
    }
  }

  static Future<void> save(UserProfile p) async {
    profile.value = p;
    await _prefs.set(profileKey, jsonEncode(p.toJson()));
    if (p.district != null) await _prefs.set(districtKey, p.district!);
  }

  static Future<void> saveContacts(List<FamilyContact> list) async {
    contacts.value = List.unmodifiable(list);
    await _prefs.set(contactsKey, jsonEncode([for (final c in list) c.toJson()]));
  }

  @visibleForTesting
  static void debugSet(UserProfile p, [List<FamilyContact> c = const []]) {
    _loaded = true;
    profile.value = p;
    contacts.value = c;
  }

  @visibleForTesting
  static void debugReset() {
    _prefs = PrefsStrings();
    _loaded = false;
    profile.value = UserProfile.empty;
    contacts.value = const [];
  }
}
