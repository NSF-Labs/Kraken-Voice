import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:krak_en_voice/design/tokens.dart';
import 'package:krak_en_voice/kernel/calendar/calendar_service.dart';
import 'package:krak_en_voice/kernel/vault/preferences_service.dart';

/// Tab screen that shows upcoming calendar events from the device's native
/// calendar and lets the user toggle recording reminders for each event.
class CalendarTabScreen extends StatefulWidget {
  const CalendarTabScreen({super.key});

  @override
  State<CalendarTabScreen> createState() => _CalendarTabScreenState();
}

class _CalendarTabScreenState extends State<CalendarTabScreen> {
  final CalendarService _calendarService = CalendarService();

  bool _isLoading = true;
  List<KrakenCalendarEvent> _events = [];
  String? _errorMessage;

  /// Available reminder intervals (in minutes). 0 = "At start".
  static const List<int> _reminderOptions = [0, 5, 15, 30];
  Set<int> _selectedIntervals = {5};

  @override
  void initState() {
    super.initState();
    _initCalendar();
  }

  /// Ensure persisted reminders are loaded BEFORE calendar events so that
  /// prune logic and initial state are correct. Previous implementation
  /// fired both async methods in parallel, causing a race condition.
  Future<void> _initCalendar() async {
    await _loadPersistedReminders();
    await _loadReminderIntervals();
    await _loadCalendar();
  }

  /// Load the user's preferred reminder intervals from SharedPreferences.
  Future<void> _loadReminderIntervals() async {
    final prefs = PreferencesService();
    final saved = await prefs.getStringList('calendar_reminder_intervals');
    if (saved != null && saved.isNotEmpty) {
      _selectedIntervals = saved.map((s) => int.parse(s)).toSet();
    }
    _calendarService.reminderIntervals = Set.of(_selectedIntervals);
    if (mounted) setState(() {});
  }

  /// Toggle an interval on/off. At least one must remain selected.
  Future<void> _toggleInterval(int minutes) async {
    setState(() {
      if (_selectedIntervals.contains(minutes)) {
        // Don't allow deselecting the last one
        if (_selectedIntervals.length > 1) {
          _selectedIntervals.remove(minutes);
        }
      } else {
        _selectedIntervals.add(minutes);
      }
    });
    _calendarService.reminderIntervals = Set.of(_selectedIntervals);
    final prefs = PreferencesService();
    await prefs.setStringList(
      'calendar_reminder_intervals',
      _selectedIntervals.map((i) => i.toString()).toList(),
    );
  }

  /// Restore enabled reminder IDs from SharedPreferences.
  Future<void> _loadPersistedReminders() async {
    final prefs = PreferencesService();
    final saved = await prefs.getStringList('calendar_reminder_ids') ?? [];
    // Clear first — CalendarService is a singleton, so without this,
    // IDs accumulate across tab rebuilds causing false-positive "enabled" state.
    _calendarService.enabledEventIds.clear();
    _calendarService.enabledEventIds.addAll(saved);
    if (mounted) setState(() {});
  }

  /// Prune stale reminder IDs — remove any that don't match a current
  /// upcoming event. This prevents old/expired event IDs from causing
  /// new events to appear pre-enabled ("Reminder removed" on first tap).
  Future<void> _pruneStaleReminders() async {
    if (_events.isEmpty || _calendarService.enabledEventIds.isEmpty) return;
    final currentIds = _events.map((e) => e.eventId).toSet();
    final stale = _calendarService.enabledEventIds
        .where((id) => !currentIds.contains(id))
        .toList();
    if (stale.isNotEmpty) {
      debugPrint('[Calendar] Pruning ${stale.length} stale reminder IDs');
      _calendarService.enabledEventIds.removeAll(stale);
      await _persistReminders();
      if (mounted) setState(() {});
    }
  }

  /// Persist the current enabled set.
  Future<void> _persistReminders() async {
    final prefs = PreferencesService();
    await prefs.setStringList(
      'calendar_reminder_ids',
      _calendarService.enabledEventIds.toList(),
    );
  }

  Future<void> _loadCalendar() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Eventide handles permission requests automatically
      final events = await _calendarService.getUpcomingEvents(days: 7);
      if (mounted) {
        setState(() {
          _events = events;
          _isLoading = false;
        });
        // Clean up stale reminder IDs after events load
        await _pruneStaleReminders();
      }
    } catch (e) {
      debugPrint('[Calendar] Load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Unable to load calendar. Please check permissions.';
        });
      }
    }
  }

  Future<void> _toggleReminder(KrakenCalendarEvent event) async {
    // Check if the event has already passed — use the largest interval
    final maxInterval = _selectedIntervals.reduce((a, b) => a > b ? a : b);
    final reminderTime = event.start.subtract(
      Duration(minutes: maxInterval),
    );
    final wasEnabled = _calendarService.enabledEventIds.contains(event.eventId);

    // If trying to enable a past event, show feedback and bail
    if (!wasEnabled && reminderTime.isBefore(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Can\'t set reminder — "${event.title}" has already started or is too soon.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Optimistic UI update — toggle immediately for instant feedback
    setState(() {
      if (wasEnabled) {
        _calendarService.enabledEventIds.remove(event.eventId);
      } else {
        _calendarService.enabledEventIds.add(event.eventId);
      }
    });

    try {
      if (wasEnabled) {
        await _calendarService.cancelReminder(event);
      } else {
        await _calendarService.scheduleReminder(event);
      }
      await _persistReminders();
    } catch (e) {
      // Revert on failure
      debugPrint('[Calendar] Reminder toggle failed: $e');
      if (mounted) {
        setState(() {
          if (wasEnabled) {
            _calendarService.enabledEventIds.add(event.eventId);
          } else {
            _calendarService.enabledEventIds.remove(event.eventId);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not set reminder: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return; // Don't show the success snackbar
    }

    if (mounted) {
      final nowEnabled = _calendarService.enabledEventIds.contains(event.eventId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nowEnabled
                ? 'Reminder set for "${event.title}"'
                : 'Reminder removed for "${event.title}"',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KrakenColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                children: [
                  Text('Upcoming Meetings',
                      style: KrakenText.displayLg()),
                  const Spacer(),
                  GestureDetector(
                    onTap: _loadCalendar,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: KrakenColors.surface,
                      ),
                      child: Icon(
                        Icons.refresh,
                        color: KrakenColors.accent,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Tap the bell to get a recording reminder before your meeting',
                style: KrakenText.bodySm(color: KrakenColors.textMuted),
              ),
            ),

            // ─── Reminder Interval Selector ───────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.timer_outlined, size: 14, color: KrakenColors.textMuted),
                  const SizedBox(width: 6),
                  Text('Remind:', style: KrakenText.caption(color: KrakenColors.textMuted)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _reminderOptions.map((minutes) {
                          final isSelected = _selectedIntervals.contains(minutes);
                          final label = minutes == 0 ? 'At start' : '${minutes}m';
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () => _toggleInterval(minutes),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? KrakenColors.accent.withAlpha(25)
                                      : KrakenColors.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? KrakenColors.accent.withAlpha(80)
                                        : KrakenColors.border,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isSelected) ...[
                                      Icon(Icons.check, size: 11, color: KrakenColors.accent),
                                      const SizedBox(width: 3),
                                    ],
                                    Text(
                                      label,
                                      style: KrakenText.caption(
                                        color: isSelected
                                            ? KrakenColors.accent
                                            : KrakenColors.textSecondary,
                                      ).copyWith(
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ─── Content ─────────────────────────────
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: KrakenColors.accent),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_events.isEmpty) {
      return _buildEmptyState();
    }

    return _buildEventsList();
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                color: KrakenColors.danger, size: 40),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: KrakenText.bodyMd(color: KrakenColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _loadCalendar,
              child: Text('Retry',
                  style: KrakenText.bodySm(color: KrakenColors.accent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KrakenColors.accent.withAlpha(15),
              ),
              child: Icon(
                Icons.event_available,
                color: KrakenColors.accent.withAlpha(120),
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No upcoming meetings',
              style: KrakenText.displayMd(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your next 7 days look clear. Meetings from your device calendar will appear here.',
              style: KrakenText.bodyMd(color: KrakenColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsList() {
    // Group events by day
    final Map<String, List<KrakenCalendarEvent>> grouped = {};
    final dateFormat = DateFormat('EEEE, MMM d');

    for (final event in _events) {
      final dayKey = dateFormat.format(event.start);
      grouped.putIfAbsent(dayKey, () => []).add(event);
    }

    return RefreshIndicator(
      color: KrakenColors.accent,
      onRefresh: _loadCalendar,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: grouped.length,
        itemBuilder: (context, sectionIndex) {
          final dayLabel = grouped.keys.elementAt(sectionIndex);
          final dayEvents = grouped[dayLabel]!;

          // Check if this is today or tomorrow for a special label
          String displayLabel = dayLabel;
          if (dayEvents.first.isToday) {
            displayLabel = 'Today — $dayLabel';
          } else if (dayEvents.first.isTomorrow) {
            displayLabel = 'Tomorrow — $dayLabel';
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sectionIndex > 0) const SizedBox(height: 8),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  displayLabel,
                  style: KrakenText.bodySm(color: KrakenColors.accent)
                      .copyWith(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
              ...dayEvents.map((event) => _buildEventCard(event)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEventCard(KrakenCalendarEvent event) {
    final timeFormat = DateFormat('h:mm a');
    final startStr = timeFormat.format(event.start);
    final endStr = timeFormat.format(event.end);
    final isReminderOn =
        _calendarService.enabledEventIds.contains(event.eventId);

    final isHappeningNow = event.isNow;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: KrakenColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHappeningNow
              ? KrakenColors.accent.withAlpha(60)
              : KrakenColors.border,
        ),
        boxShadow: isHappeningNow
            ? [
                BoxShadow(
                  color: KrakenColors.accent.withAlpha(15),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showEventDetails(event),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Time indicator
                Container(
                  width: 4,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: isHappeningNow
                        ? KrakenColors.onlineGreen
                        : KrakenColors.accent.withAlpha(60),
                  ),
                ),
                const SizedBox(width: 12),

                // Event info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.title,
                              style: KrakenText.bodyMd().copyWith(
                                  fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isHappeningNow)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: KrakenColors.onlineGreen.withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'NOW',
                                style: KrakenText.caption(
                                        color: KrakenColors.onlineGreen)
                                    .copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 9),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time,
                              size: 12,
                              color: KrakenColors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            '$startStr — $endStr',
                            style: KrakenText.caption(
                                color: KrakenColors.textSecondary),
                          ),
                          if (event.location != null &&
                              event.location!.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Icon(Icons.location_on_outlined,
                                size: 12,
                                color: KrakenColors.textMuted),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                event.location!,
                                style: KrakenText.caption(
                                    color: KrakenColors.textMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Reminder toggle
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _toggleReminder(event),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isReminderOn
                          ? KrakenColors.accent.withAlpha(25)
                          : KrakenColors.surfaceElevated,
                      border: Border.all(
                        color: isReminderOn
                            ? KrakenColors.accent.withAlpha(60)
                            : KrakenColors.border,
                      ),
                    ),
                    child: Icon(
                      isReminderOn
                          ? Icons.notifications_active
                          : Icons.notifications_none,
                      color: isReminderOn
                          ? KrakenColors.accent
                          : KrakenColors.textMuted,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEventDetails(KrakenCalendarEvent event) {
    final timeFormat = DateFormat('h:mm a');
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy');

    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          // Read live state on every rebuild — not a stale snapshot.
          final isReminderOn =
              _calendarService.enabledEventIds.contains(event.eventId);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: KrakenColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Title
                    Text(event.title,
                        style: KrakenText.displayMd()
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),

                    // Date + time
                    _detailRow(Icons.calendar_today,
                        dateFormat.format(event.start)),
                    const SizedBox(height: 6),
                    _detailRow(Icons.access_time,
                        '${timeFormat.format(event.start)} — ${timeFormat.format(event.end)}'),

                    if (event.location != null &&
                        event.location!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _detailRow(
                          Icons.location_on_outlined, event.location!),
                    ],

                    if (event.description != null &&
                        event.description!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        event.description!,
                        style: KrakenText.bodySm(
                            color: KrakenColors.textSecondary),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const SizedBox(height: 6),
                    _detailRow(Icons.calendar_view_day_outlined,
                        event.calendarName),

                    const SizedBox(height: 16),

                    // Reminder button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await _toggleReminder(event);
                          // Update sheet UI to reflect the toggle, then dismiss
                          setSheetState(() {});
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        icon: Icon(
                          isReminderOn
                              ? Icons.notifications_off_outlined
                              : Icons.notifications_active,
                        ),
                        label: Text(
                          isReminderOn
                              ? 'Remove Recording Reminder'
                              : 'Remind Me to Record',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isReminderOn
                              ? KrakenColors.danger.withAlpha(20)
                              : KrakenColors.accent,
                          foregroundColor: isReminderOn
                              ? KrakenColors.danger
                              : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: KrakenColors.textMuted),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: KrakenText.bodySm(color: KrakenColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
