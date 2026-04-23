import 'package:shared_preferences/shared_preferences.dart';

/// Service to securely manage app preferences.
///
/// Under the strict architecture rules, direct persistence via [SharedPreferences]
/// is only permitted within `kernel/vault/`. This service abstracts preferences
/// so the rest of the application (like the shell) can safely access basic flags
/// (such as `isOnboarded`) without violating the rules.
class PreferencesService {
  /// Check if the user has completed onboarding.
  Future<bool> getIsOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isOnboarded') ?? false;
  }

  /// Mark onboarding as complete.
  Future<void> setOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isOnboarded', true);
  }

  /// Helper to get a generic boolean preference.
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? defaultValue;
  }

  /// Helper to set a generic boolean preference.
  Future<void> setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  /// Clear all preferences (e.g., during full data purge).
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// Get a string preference.
  Future<String> getString(String key, {String defaultValue = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) ?? defaultValue;
  }

  /// Set a string preference.
  Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  // ─── Retention ──────────────────────────────────────────────────────────────

  /// Get the default retention policy for new recordings.
  Future<String> getDefaultRetentionPolicy() async {
    return getString('default_retention_policy', defaultValue: '90_day');
  }

  /// Set the default retention policy for new recordings.
  Future<void> setDefaultRetentionPolicy(String policy) async {
    await setString('default_retention_policy', policy);
  }
}
