# Automated Conflict-Free College Timetable & Attendance Management System

A full-featured Android Flutter application for managing college timetables and attendance.

---

## Features

- **Greedy Constraint-Based Timetable Generation** — conflict-free scheduling enforcing all hard constraints
- **Excel Import/Export** — import faculty/subject/student data; export timetables and attendance reports
- **Period-wise Attendance** — faculty mark attendance per period; students track their stats
- **Local Notifications** — reminders 5 min before class starts and 10 min before end for attendance marking (works when app is closed)
- **Offline-first** — SQLite local database, no server required
- **Three dashboards** — Admin, Faculty, Student

---

## Project Structure

```
lib/
├── main.dart                          # App entry point + routing
├── models/
│   └── models.dart                    # All data models + TimeSlot constants
├── services/
│   ├── database_service.dart          # SQLite CRUD operations
│   ├── auth_service.dart              # Login + session management
│   ├── excel_service.dart             # Import/export Excel
│   └── notification_service.dart     # flutter_local_notifications scheduling
├── algorithms/
│   └── timetable_scheduler.dart       # Greedy CSP scheduling algorithm
├── screens/
│   ├── login_screen.dart
│   ├── admin/
│   │   ├── admin_dashboard.dart       # Import, Generate, View, Reports tabs
│   │   └── attendance_report_screen.dart
│   ├── faculty/
│   │   └── faculty_dashboard.dart     # Today, Timetable, Attendance tabs
│   └── student/
│       └── student_dashboard.dart     # Overview, Timetable, Attendance tabs
├── widgets/
│   └── timetable_grid.dart            # Color-coded timetable grid widget
└── utils/
    └── app_theme.dart                 # Material Design theme + colors
```

---

## Algorithm — Greedy Constraint-Based Scheduling

File: `lib/algorithms/timetable_scheduler.dart`

### Phases
1. **Pre-reserve** special slots (NPTEL, Mentoring, Sports)
2. **Sort subjects** — Labs first (need contiguous blocks), then by `periodsPerWeek` descending
3. **Greedy placement** — for each subject, iterate days (Mon–Fri) × periods, place only when ALL constraints pass
4. **Lab block atomic placement** — labs consume either the morning block (P2,P3,P4) or afternoon block (P5,P6,P7) as a unit
5. **Relaxed pass** — if periods couldn't be placed (due to continuous-avoidance rule), retry without that constraint

### Hard Constraints Enforced

| Constraint | Implementation |
|---|---|
| Faculty clash | `facultySlots` Set — key = `facultyId_day_period` |
| Section clash | `sectionSlots` Set — key = `section_year_day_period_batch` |
| Daily subject limit | Per-day counter, max = 2 |
| Continuous subject avoidance | Track `lastPeriodOnDay`, reject if `period == last+1` |
| Lab block rule | Only morning (P2,P3,P4) or afternoon (P5,P6,P7) |
| Lab batch rule | Batch 1 and Batch 2 can share same block if different faculty |
| Reserved slots | Pre-populated into `sectionSlots` before scheduling |
| Breaks | Periods 0 (break) never appear in `_allPeriods` list |
| Periods per week | Loop exits when `placed == periodsPerWeek` |

---

## Daily Schedule

| Period | Time | Notes |
|---|---|---|
| Period 1 | 9:15 – 10:10 | |
| Period 2 | 10:10 – 11:00 | Morning lab start |
| Short Break | 11:00 – 11:10 | Never scheduled |
| Period 3 | 11:10 – 12:00 | |
| Period 4 | 12:00 – 12:50 | Morning lab end |
| Lunch Break | 12:50 – 1:30 | Never scheduled |
| Period 5 | 1:30 – 2:20 | Afternoon lab start |
| Period 6 | 2:20 – 3:10 | |
| Period 7 | 3:10 – 4:00 | Afternoon lab end |

---

## Excel Templates

### Faculty Sheet Columns
```
Faculty Name | Subject | Section | Year | Type | Periods Per Week |
Is Incharge | Batch | Email | Preference | Lab Divided Into 2 Batches
```

### Student Sheet Columns
```
Roll Number | Student Name | Section | Year | Batch
```

---

## Setup

### Prerequisites
- Flutter SDK 3.x
- Android SDK (min API 21)
- Java 17

### Install
```bash
cd timetable_app
flutter pub get
flutter run
```

### Build APK
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## Default Admin Login

| Field | Value |
|---|---|
| Email | admin@college.edu |
| Password | admin123 |

---

## Notifications

Scheduled automatically after faculty logs in:
- **5 min before class starts** — "Class Starting Soon"
- **10 min before class ends** — "Mark Attendance Now"

Notifications persist across app restarts via exact alarms (Android).  
Requires `SCHEDULE_EXACT_ALARM` permission (Android 12+).

---

## Dependencies (pubspec.yaml)

| Package | Purpose |
|---|---|
| `sqflite` | Local SQLite database |
| `excel` | Excel import/export |
| `file_picker` | File selection |
| `flutter_local_notifications` | Scheduled notifications |
| `timezone` | Timezone-aware scheduling |
| `provider` | State management |
| `fl_chart` | Pie/bar charts in student dashboard |
| `shared_preferences` | Session persistence |
| `permission_handler` | Runtime permissions |
| `uuid` | Unique ID generation |
| `table_calendar` | Calendar widget |
