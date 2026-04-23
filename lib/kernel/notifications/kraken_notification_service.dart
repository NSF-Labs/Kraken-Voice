import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Centralized notification service for Kraken Hub.
/// Handles system-level (shade) notifications for transcription events
/// and usage limit warnings.
class KrakenNotificationService {
  // Singleton
  static final KrakenNotificationService _instance = KrakenNotificationService._internal();
  factory KrakenNotificationService() => _instance;
  KrakenNotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Notification channel IDs
  static const String _transcriptionChannelId = 'kraken_transcription';
  static const String _limitsChannelId = 'kraken_limits';

  // Notification IDs (unique per type)
  static const int _transcriptionCompleteId = 1001;
  static const int _transcriptionFailedId = 1002;
  static const int _storageLimitWarningId = 2001;
  static const int _recordingLimitWarningId = 2002;

  /// Initialize the notification system. Call once at app startup.
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
    );
    _initialized = true;
    debugPrint('[Notifications] Initialized.');
  }

  bool _permissionRequested = false;

  /// Request notification permission. On Android 13+ this shows a system dialog.
  /// Safe to call multiple times — only prompts once.
  Future<bool> requestPermission() async {
    if (_permissionRequested) return true;
    _permissionRequested = true;

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      debugPrint('[Notifications] Permission granted: $granted');
      return granted ?? false;
    }
    return true; // non-Android platform
  }

  /// Ensures permission is granted before showing a notification.
  Future<bool> _ensurePermission() async {
    if (!_initialized) return false;
    return requestPermission();
  }

  // ─── Transcription Notifications ──────────────────────────────────────────

  /// Show a notification when transcription completes successfully.
  Future<void> notifyTranscriptionComplete(String recordingTitle) async {
    if (!await _ensurePermission()) return;

    await _plugin.show(
      id: _transcriptionCompleteId,
      title: 'Transcription Complete',
      body: '"$recordingTitle" has been transcribed and is ready to view.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _transcriptionChannelId,
          'Transcription Updates',
          channelDescription: 'Notifies when audio transcription completes.',
          importance: Importance.high,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
          autoCancel: true,
        ),
      ),
    );
  }

  /// Show a notification when transcription fails.
  Future<void> notifyTranscriptionFailed(String recordingTitle) async {
    if (!await _ensurePermission()) return;

    await _plugin.show(
      id: _transcriptionFailedId,
      title: 'Transcription Failed',
      body: '"$recordingTitle" could not be transcribed. Tap to retry.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _transcriptionChannelId,
          'Transcription Updates',
          channelDescription: 'Notifies when audio transcription completes.',
          importance: Importance.high,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
          autoCancel: true,
        ),
      ),
    );
  }

  // ─── Usage Limit Notifications ────────────────────────────────────────────

  /// Show a warning when storage usage is approaching the cap.
  /// [usedPercent] should be 0.0-1.0.
  Future<void> notifyStorageWarning({
    required double usedPercent,
    required String usedLabel,
    required String capLabel,
  }) async {
    if (!await _ensurePermission()) return;

    final percent = (usedPercent * 100).round();

    await _plugin.show(
      id: _storageLimitWarningId,
      title: 'Storage Almost Full',
      body: 'Kraken is using $usedLabel of $capLabel ($percent%). Oldest audio may be auto-deleted to free space.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _limitsChannelId,
          'Usage Limits',
          channelDescription: 'Warns when approaching storage or usage limits.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          autoCancel: true,
        ),
      ),
    );
  }

  /// Show a warning when recording count is approaching a free-tier limit.
  Future<void> notifyRecordingLimitWarning({
    required int currentCount,
    required int maxCount,
  }) async {
    if (!await _ensurePermission()) return;

    final remaining = maxCount - currentCount;

    await _plugin.show(
      id: _recordingLimitWarningId,
      title: 'Approaching Recording Limit',
      body: 'You have $remaining recording${remaining == 1 ? '' : 's'} remaining on the free plan. Upgrade for unlimited recordings.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _limitsChannelId,
          'Usage Limits',
          channelDescription: 'Warns when approaching storage or usage limits.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          autoCancel: true,
        ),
      ),
    );
  }

  /// Dismiss a specific notification.
  Future<void> dismiss(int id) async {
    await _plugin.cancel(id: id);
  }
}
