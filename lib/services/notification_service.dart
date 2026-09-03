// ═══════════════════════════════════════════════════════════════════════════
//  NotificationService
//
//  Android / iOS : full implementation
//    • Faculty: 5 min BEFORE class starts + 10 min BEFORE class ENDS (take attendance)
//    • Student:  5 min BEFORE class starts + low-attendance warnings
//  Windows / macOS / Linux / Web : silent no-op
//
//  Windows NuGet-free approach:
//  flutter_local_notifications is in pubspec but
//  flutter_local_notifications_windows is overridden with a local stub
//  (packages/flutter_local_notifications_windows/) that has no C++ code.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/models.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // True only on Android & iOS
  bool get _isMobile {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
           defaultTargetPlatform == TargetPlatform.iOS;
  }

  // ── Notification channel IDs ───────────────────────────────────────────────
  static const _chStart      = 'tt_class_start';
  static const _chAttendance = 'tt_attendance';
  static const _chLowAtt     = 'tt_low_att';
  static const _chGeneral    = 'tt_general';

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (!_isMobile || _initialized) return;
    tz.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS     = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: iOS),
      onDidReceiveNotificationResponse: (_) {},
    );
    _initialized = true;
  }

  // ── Request permissions ────────────────────────────────────────────────────
  Future<void> requestPermissions() async {
    if (!_isMobile) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  FACULTY NOTIFICATIONS
  //  For each class entry belonging to the faculty:
  //    1. "Class starting" — 5 min BEFORE start time
  //    2. "Take attendance" — 10 min BEFORE end time
  //       (for labs that span multiple periods, uses the LAST period's end)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<int> scheduleFacultyReminders({
    required List<TimetableEntry> entries,
    required Map<String, String>  subjectNames,
    required String               facultyId,
  }) async {
    if (!_isMobile || !_initialized) return 0;
    await _plugin.cancelAll();

    int id = 0;
    final now  = tz.TZDateTime.now(tz.local);
    final mine = entries.where((e) => e.facultyId == facultyId).toList();

    // Group lab batches: same subject+day+section share end time
    // For conflict-free grouping: key = dayOfWeek + subjectId + section
    final processed = <String>{};

    for (final e in mine) {
      final sub  = subjectNames[e.subjectId] ?? 'Class';
      final slot = TimeSlot.getByNumber(e.periodNumber);
      if (slot == null) continue;

      // ── 1. Start reminder — 5 min before ─────────────────────────────────
      final startDt = _tzFromTime(now, e.dayOfWeek, slot.startTime);
      final startReminderDt = startDt.subtract(const Duration(minutes: 5));
      if (startReminderDt.isAfter(now)) {
        final typeLabel = e.isLab
            ? 'Lab${e.batch > 0 ? " (B${e.batch})" : ""}'
            : 'Lecture';
        await _plugin.zonedSchedule(
          id++,
          '\u23f0 Class starting in 5 min',
          '$sub \u2014 $typeLabel',
          startReminderDt,
          _details(_chStart, 'Class Start Reminders',
              'Notifies 5 min before class starts', high: false),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }

      // ── 2. Attendance reminder — 10 min before end ────────────────────────
      // For labs spanning multiple consecutive periods, find the last period.
      // Use a key so we only schedule ONE attendance reminder per lab block.
      final attKey = '${e.dayOfWeek}_${e.subjectId}_${e.section}_${e.batch}';
      if (processed.contains(attKey)) continue;
      processed.add(attKey);

      // Find the last period of this subject on this day
      final sameSubjectPeriods = mine
          .where((x) =>
              x.dayOfWeek == e.dayOfWeek &&
              x.subjectId == e.subjectId &&
              x.section   == e.section &&
              x.batch     == e.batch)
          .map((x) => x.periodNumber)
          .toList()
        ..sort();

      final lastPeriodNum = sameSubjectPeriods.last;
      final lastSlot = TimeSlot.getByNumber(lastPeriodNum);
      if (lastSlot == null) continue;

      final endDt = _tzFromTime(now, e.dayOfWeek, lastSlot.endTime);
      final attReminderDt = endDt.subtract(const Duration(minutes: 10));
      if (attReminderDt.isAfter(now)) {
        final periodRange = sameSubjectPeriods.length > 1
            ? 'P${sameSubjectPeriods.first}\u2013P${sameSubjectPeriods.last}'
            : 'P${sameSubjectPeriods.first}';
        await _plugin.zonedSchedule(
          id++,
          '\u2705 Take Attendance Now',
          '$sub ($periodRange) ends in 10 min \u2014 mark attendance',
          attReminderDt,
          _details(_chAttendance, 'Attendance Reminders',
              'Notifies 10 min before class ends to take attendance',
              high: true),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    }
    return id;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  STUDENT NOTIFICATIONS
  //    • 5 min BEFORE each class starts
  //    • Immediate low-attendance warnings for any subject below 75%
  // ═══════════════════════════════════════════════════════════════════════════
  Future<int> scheduleStudentReminders({
    required List<TimetableEntry>    entries,
    required Map<String, String>     subjectNames,
    required Map<String, double>     attendancePcts,
    required String                  studentId,
  }) async {
    if (!_isMobile || !_initialized) return 0;
    await _plugin.cancelAll();

    int id = 0;
    final now = tz.TZDateTime.now(tz.local);

    // Low-attendance warnings — shown immediately
    for (final kv in attendancePcts.entries) {
      if (kv.value < 75) {
        final sub = subjectNames[kv.key] ?? 'Subject';
        await _plugin.show(
          id++,
          '\u26a0\ufe0f Low Attendance: $sub',
          '${kv.value.toStringAsFixed(0)}% \u2014 need 75% for exam eligibility',
          _details(_chLowAtt, 'Attendance Alerts',
              'Low attendance warnings', high: true),
        );
      }
    }

    // Class start reminders — 5 min before
    final seen = <String>{};
    for (final e in entries) {
      final slot = TimeSlot.getByNumber(e.periodNumber);
      if (slot == null) continue;

      // For batch labs, remind once per subject per day
      final key = '${e.dayOfWeek}_${e.subjectId}';
      if (seen.contains(key)) continue;
      seen.add(key);

      final sub = subjectNames[e.subjectId] ?? 'Class';
      final startDt = _tzFromTime(now, e.dayOfWeek, slot.startTime);
      final reminderDt = startDt.subtract(const Duration(minutes: 5));
      if (!reminderDt.isAfter(now)) continue;

      await _plugin.zonedSchedule(
        100 + id++,
        '\u23f0 Class in 5 min',
        '$sub \u2014 P${e.periodNumber} at ${slot.startTime}',
        reminderDt,
        _details(_chStart, 'Class Start Reminders',
            'Notifies 5 min before class starts', high: false),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
    return id;
  }

  // ── Immediate notification ─────────────────────────────────────────────────
  Future<void> showNow({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isMobile || !_initialized) return;
    await _plugin.show(999, title, body,
        _details(_chGeneral, 'General', 'General notifications'),
        payload: payload);
  }

  Future<void> showImmediateNotification({
    required String title,
    required String body,
  }) => showNow(title: title, body: body);

  Future<void> cancelAllNotifications() async {
    if (!_isMobile || !_initialized) return;
    await _plugin.cancelAll();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  // Parse a time string like "9:15 AM" or "2:20 PM" → tz.TZDateTime on next
  // occurrence of weekday after `from`.
  tz.TZDateTime _tzFromTime(tz.TZDateTime from, int weekday, String timeStr) {
    final t     = timeStr.trim();
    final isPM  = t.contains('PM');
    final clean = t.replaceAll('AM', '').replaceAll('PM', '').trim();
    final parts = clean.split(':');
    int h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    if (isPM && h != 12) h += 12;
    if (!isPM && h == 12) h = 0;

    var dt = tz.TZDateTime(tz.local, from.year, from.month, from.day, h, m);
    // Advance to the correct weekday
    while (dt.weekday != weekday || !dt.isAfter(from)) {
      dt = dt.add(const Duration(days: 1));
    }
    return dt;
  }

  NotificationDetails _details(
      String channelId, String channelName, String desc,
      {bool high = false}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId, channelName,
        channelDescription: desc,
        importance: high ? Importance.max : Importance.defaultImportance,
        priority: high ? Priority.high : Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
        playSound: high,
        enableVibration: high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: high,
      ),
    );
  }
}
