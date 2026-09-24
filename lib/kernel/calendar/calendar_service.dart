import 'package:eventide/eventide.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// Reads native device calendars via [Eventide] and schedules recording-reminder
/// notifications via [flutter_local_notifications].
class CalendarService {
  // Singleton
  static final CalendarService _instance = CalendarService._internal();
  factory CalendarService() => _instance;
  CalendarService._internal();

  final Eventide _eventide = Eventide();
  final FlutterLocalNotificationsPlugin _notifPlugin =
      FlutterLocalNotificationsPlugin();

  bool _tzInitialized = false;
  bool _notifInitialized = false;

  // Notification channel
  static const String _channelId = 'kraken_meeting_reminder';
  static const String _channelName = 'Meeting Reminders';

  // Notification ID offset (avoid collisions with other notification IDs)
  static const int _notifIdOffset = 5000;

  /// Minutes before the event to send reminders. Users can select multiple.
  Set<int> reminderIntervals = {5};

  /// Set of event IDs the user has enabled reminders for.
  final Set<String> enabledEventIds = {};

  bool _calendarPermissionGranted = false;

  /// Pre-request calendar read permission via permission_handler so that
  /// Eventide doesn't trigger the permission dialog itself. When Eventide
  /// triggers the dialog, Android restarts the Activity on grant — which
  /// kills the Flutter engine mid-async-call and crashes the app.
  Future<bool> _ensureCalendarPermission() async {
    if (_calendarPermissionGranted) return true;
    var status = await Permission.calendarFullAccess.status;
    if (!status.isGranted) {
      status = await Permission.calendarFullAccess.request();
    }
    _calendarPermissionGranted = status.isGranted;
    debugPrint('[Calendar] Permission status: $status');
    return _calendarPermissionGranted;
  }

  /// Initialize timezone database (required for scheduled notifications).
  void _ensureTimezone() {
    if (!_tzInitialized) {
      tz_data.initializeTimeZones();
      _tzInitialized = true;
    }
  }

  /// Initialize the notification plugin if not already done.
  /// Required before any zonedSchedule/cancel calls.
  Future<void> _ensureNotificationsInitialized() async {
    if (_notifInitialized) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifPlugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
    );
    // Request exact alarm permission on Android 12+
    final androidPlugin = _notifPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.requestExactAlarmsPermission();
    }
    _notifInitialized = true;
    debugPrint('[Calendar] Notification plugin initialized');
  }

  /// Fetch all readable calendars from the device.
  /// Permission is pre-requested to avoid Eventide triggering the system
  /// dialog, which causes an Activity restart and crashes the app.
  Future<List<ETCalendar>> getCalendars() async {
    try {
      final hasPermission = await _ensureCalendarPermission();
      if (!hasPermission) {
        debugPrint('[Calendar] Calendar permission denied by user');
        return [];
      }
      final calendars = await _eventide.retrieveCalendars(
        onlyWritableCalendars: false,
      );
      return calendars.toList();
    } catch (e) {
      debugPrint('[Calendar] Error retrieving calendars: $e');
      return [];
    }
  }

  /// Fetch upcoming events from all calendars for the next [days] days.
  Future<List<KrakenCalendarEvent>> getUpcomingEvents({int days = 7}) async {
    final calendars = await getCalendars();
    if (calendars.isEmpty) return [];

    final now = DateTime.now();
    final end = now.add(Duration(days: days));
    final allEvents = <KrakenCalendarEvent>[];

    for (final cal in calendars) {
      try {
        final events = await _eventide.retrieveEvents(
          calendarId: cal.id,
          startDate: now,
          endDate: end,
        );
        for (final event in events) {
          // Skip all-day events (typically not meetings to record)
          if (event.isAllDay) continue;

          // Guard against null dates — Eventide can return incomplete
          // event data after a fresh permission grant / activity restart.
          final startDate = event.startDate;
          final endDate = event.endDate;
          final eventTitle = event.title;
          if (eventTitle.isEmpty) continue;

          allEvents.add(KrakenCalendarEvent(
            eventId: event.id,
            calendarId: cal.id,
            calendarName: cal.title,
            title: eventTitle,
            description: event.description,
            location: event.location,
            start: startDate,
            end: endDate,
            isAllDay: event.isAllDay,
          ));
        }
      } catch (e) {
        debugPrint('[Calendar] Error reading calendar ${cal.title}: $e');
      }
    }

    // Sort by start time
    allEvents.sort((a, b) => a.start.compareTo(b.start));
    return allEvents;
  }

  /// Generate a unique notification ID for a specific event + interval combo.
  int _notifId(String eventId, int minutesBefore) {
    return _notifIdOffset + (eventId.hashCode.abs() * 100 + minutesBefore) % 100000;
  }

  /// Schedule local notification reminders for a specific event.
  /// One notification is scheduled per interval in [reminderIntervals].
  Future<void> scheduleReminder(KrakenCalendarEvent event) async {
    _ensureTimezone();
    await _ensureNotificationsInitialized();

    final now = DateTime.now();

    for (final minutes in reminderIntervals) {
      final reminderTime = event.start.subtract(Duration(minutes: minutes));

      // Don't schedule if the reminder time has already passed
      if (reminderTime.isBefore(now)) {
        debugPrint(
            '[Calendar] Skipping ${minutes}m reminder for "${event.title}" — time already passed.');
        continue;
      }

      final notifId = _notifId(event.eventId, minutes);
      final tzTime = tz.TZDateTime.from(reminderTime, tz.local);
      final body = minutes == 0
          ? '"${event.title}" is starting now. Open Kraken to record.'
          : '"${event.title}" starts in $minutes min. Open Kraken to record.';

      await _notifPlugin.zonedSchedule(
        id: notifId,
        title: '🎙 Time to Record',
        body: body,
        scheduledDate: tzTime,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription:
                'Reminds you to start recording before a meeting.',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            autoCancel: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      debugPrint(
          '[Calendar] Scheduled ${minutes}m reminder for "${event.title}" at $reminderTime');
    }

    enabledEventIds.add(event.eventId);
  }

  /// Cancel all previously scheduled reminders for an event.
  Future<void> cancelReminder(KrakenCalendarEvent event) async {
    await _ensureNotificationsInitialized();
    // Cancel notifications for all possible intervals
    for (final minutes in [0, 5, 15, 30]) {
      final notifId = _notifId(event.eventId, minutes);
      await _notifPlugin.cancel(id: notifId);
    }
    enabledEventIds.remove(event.eventId);
    debugPrint('[Calendar] Cancelled all reminders for "${event.title}"');
  }

  /// Toggle reminder for an event. Returns true if now enabled.
  Future<bool> toggleReminder(KrakenCalendarEvent event) async {
    if (enabledEventIds.contains(event.eventId)) {
      await cancelReminder(event);
      return false;
    } else {
      await scheduleReminder(event);
      return true;
    }
  }
}

/// Simplified calendar event model for the Kraken UI layer.
class KrakenCalendarEvent {
  final String eventId;
  final String calendarId;
  final String calendarName;
  final String title;
  final String? description;
  final String? location;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;

  KrakenCalendarEvent({
    required this.eventId,
    required this.calendarId,
    required this.calendarName,
    required this.title,
    this.description,
    this.location,
    required this.start,
    required this.end,
    this.isAllDay = false,
  });

  /// Duration of the event.
  Duration get duration => end.difference(start);

  /// Whether this event is happening right now.
  bool get isNow {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end);
  }

  /// Whether this event is today.
  bool get isToday {
    final now = DateTime.now();
    return start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
  }

  /// Whether this event is tomorrow.
  bool get isTomorrow {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return start.year == tomorrow.year &&
        start.month == tomorrow.month &&
        start.day == tomorrow.day;
  }
}
