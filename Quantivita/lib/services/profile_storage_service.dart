import 'package:shared_preferences/shared_preferences.dart';

import '../models/personal_profile.dart';

class ProfileStorageService {
  static const _ageKey = 'profile.age';
  static const _birthDateKey = 'profile.birthDate';
  static const _sexKey = 'profile.biologicalSex';
  static const _weightKey = 'profile.weightKg';
  static const _heightKey = 'profile.heightCm';
  static const _bodyFatKey = 'profile.bodyFatPercent';

  Future<PersonalProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final hasProfile =
        prefs.containsKey(_ageKey) ||
        prefs.containsKey(_birthDateKey) ||
        prefs.containsKey(_weightKey) ||
        prefs.containsKey(_heightKey) ||
        prefs.containsKey(_bodyFatKey);

    if (!hasProfile) return null;

    return PersonalProfile(
      age: prefs.getInt(_ageKey) ?? 0,
      birthDate: prefs.getString(_birthDateKey) ?? 'Not set',
      biologicalSex: prefs.getString(_sexKey) ?? 'Not set',
      weightKg: prefs.getDouble(_weightKey) ?? 0,
      heightCm: prefs.getDouble(_heightKey) ?? 0,
      bodyFatPercent: prefs.getDouble(_bodyFatKey) ?? 0,
    );
  }

  Future<void> save(PersonalProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setInt(_ageKey, profile.age),
      prefs.setString(_birthDateKey, profile.birthDate),
      prefs.setString(_sexKey, profile.biologicalSex),
      prefs.setDouble(_weightKey, profile.weightKg),
      prefs.setDouble(_heightKey, profile.heightCm),
      prefs.setDouble(_bodyFatKey, profile.bodyFatPercent),
    ]);
  }
}
