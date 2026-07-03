import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DashboardCacheSnapshot {
  const DashboardCacheSnapshot({
    required this.healthSummary,
    required this.healthSummaryText,
    required this.savedAt,
  });

  final Map<String, double> healthSummary;
  final Map<String, String> healthSummaryText;
  final DateTime savedAt;
}

class DashboardCacheService {
  static const _healthSummaryKey = 'dashboard_health_summary_v1';
  static const _healthSummaryTextKey = 'dashboard_health_summary_text_v1';
  static const _savedAtKey = 'dashboard_cache_saved_at_v1';

  Future<DashboardCacheSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawSummary = prefs.getString(_healthSummaryKey);
    if (rawSummary == null || rawSummary.isEmpty) return null;

    try {
      final rawText = prefs.getString(_healthSummaryTextKey);
      final savedAt =
          DateTime.tryParse(prefs.getString(_savedAtKey) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final decodedSummary = jsonDecode(rawSummary) as Map<String, dynamic>;
      final decodedText = rawText == null || rawText.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(rawText) as Map<String, dynamic>;

      return DashboardCacheSnapshot(
        healthSummary: decodedSummary.map(
          (key, value) => MapEntry(key, value is num ? value.toDouble() : 0),
        ),
        healthSummaryText: decodedText.map(
          (key, value) => MapEntry(key, value?.toString() ?? ''),
        )..removeWhere((_, value) => value.isEmpty),
        savedAt: savedAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required Map<String, double> healthSummary,
    required Map<String, String> healthSummaryText,
  }) async {
    if (healthSummary.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_healthSummaryKey, jsonEncode(healthSummary));
    await prefs.setString(_healthSummaryTextKey, jsonEncode(healthSummaryText));
    await prefs.setString(
      _savedAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
  }
}
