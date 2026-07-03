class PersonalProfile {
  const PersonalProfile({
    required this.age,
    required this.birthDate,
    required this.biologicalSex,
    required this.weightKg,
    required this.heightCm,
    required this.bodyFatPercent,
  });

  factory PersonalProfile.fromSummary(Map<String, double> summary) {
    final year = summary['birthYear']?.round() ?? 0;
    final month = summary['birthMonth']?.round() ?? 0;
    final day = summary['birthDay']?.round() ?? 0;
    final age = _ageFromBirthDate(year: year, month: month, day: day);

    return PersonalProfile(
      age: age,
      birthDate: year > 0 && month > 0 && day > 0
          ? '${day.toString().padLeft(2, '0')}-${month.toString().padLeft(2, '0')}-$year'
          : 'Not set',
      biologicalSex: _sexLabel(summary['biologicalSex']?.round() ?? 0),
      weightKg: summary['bodyMassKg'] ?? 0,
      heightCm: summary['heightCm'] ?? 0,
      bodyFatPercent: summary['bodyFatPercent'] ?? 0,
    );
  }

  factory PersonalProfile.empty() {
    return const PersonalProfile(
      age: 0,
      birthDate: 'Not set',
      biologicalSex: 'Not set',
      weightKg: 0,
      heightCm: 0,
      bodyFatPercent: 0,
    );
  }

  final int age;
  final String birthDate;
  final String biologicalSex;
  final double weightKg;
  final double heightCm;
  final double bodyFatPercent;

  PersonalProfile copyWith({
    int? age,
    String? birthDate,
    String? biologicalSex,
    double? weightKg,
    double? heightCm,
    double? bodyFatPercent,
  }) {
    return PersonalProfile(
      age: age ?? this.age,
      birthDate: birthDate ?? this.birthDate,
      biologicalSex: biologicalSex ?? this.biologicalSex,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      bodyFatPercent: bodyFatPercent ?? this.bodyFatPercent,
    );
  }

  static int _ageFromBirthDate({
    required int year,
    required int month,
    required int day,
  }) {
    if (year <= 0 || month <= 0 || day <= 0) return 0;

    final now = DateTime.now();
    var age = now.year - year;
    if (now.month < month || (now.month == month && now.day < day)) {
      age -= 1;
    }

    return age.clamp(0, 130);
  }

  static String _sexLabel(int rawValue) {
    return switch (rawValue) {
      1 => 'Female',
      2 => 'Male',
      3 => 'Other',
      _ => 'Not set',
    };
  }
}
