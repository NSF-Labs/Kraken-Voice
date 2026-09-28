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

  Future<List<String>?> getStringList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(key);
  }

  Future<void> setStringList(String key, List<String> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, value);
  }

  Future<double> getDouble(String key, {required double defaultValue}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(key) ?? defaultValue;
  }

  /// Get an integer preference.
  Future<int?> getInt(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key);
  }

  /// Set an integer preference.
  Future<void> setInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
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

  // ─── Branded Exports ───────────────────────────────────────────────────────

  /// Path to the user's uploaded brand logo (PNG/JPG).
  Future<String> getBrandLogoPath() async =>
      getString('brand_logo_path');

  Future<void> setBrandLogoPath(String path) async =>
      setString('brand_logo_path', path);

  /// Custom header text for exports.
  Future<String> getBrandHeaderText() async =>
      getString('brand_header_text');

  Future<void> setBrandHeaderText(String text) async =>
      setString('brand_header_text', text);

  /// Custom footer text for exports.
  Future<String> getBrandFooterText() async =>
      getString('brand_footer_text');

  Future<void> setBrandFooterText(String text) async =>
      setString('brand_footer_text', text);

  /// Brand accent color as hex string (e.g., '#818CF8').
  Future<String> getBrandColor() async =>
      getString('brand_color', defaultValue: '#818CF8');

  Future<void> setBrandColor(String hex) async =>
      setString('brand_color', hex);

  // ─── Mic Sensitivity ──────────────────────────────────────────────────────

  /// Microphone sensitivity multiplier (0.25 = low, 1.0 = default, 2.0 = high).
  Future<double> getMicSensitivity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('mic_sensitivity') ?? 1.0;
  }

  Future<void> setMicSensitivity(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('mic_sensitivity', value);
  }

  // ─── Transcript Break Threshold ────────────────────────────────────────────

  /// Controls how aggressively line/paragraph breaks are inserted when
  /// reformatting a Whisper transcript.
  ///
  /// **Gap-based**: Gap ≥ threshold → line break; Gap ≥ 3× → paragraph.
  /// **Elapsed-time**: Elapsed ≥ 10× → line break; ≥ 30× → paragraph.
  ///
  /// Default: 0.2s. Range: 0.1–5.0s.
  Future<double> getBreakThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('break_threshold') ?? 0.2;
  }

  Future<void> setBreakThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('break_threshold', value);
  }
}
