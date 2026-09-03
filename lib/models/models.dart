// ─────────────────────────────────────────────
//  ALL DATA MODELS
// ─────────────────────────────────────────────

// ── Time Slot Constants ───────────────────────
class TimeSlot {
  static const List<PeriodSlot> periods = [
    PeriodSlot(1, '9:15 AM',  '10:10 AM', false),
    PeriodSlot(2, '10:10 AM', '11:00 AM', false),
    PeriodSlot(0, '11:00 AM', '11:10 AM', true,  label: 'Short Break'),
    PeriodSlot(3, '11:10 AM', '12:00 PM', false),
    PeriodSlot(4, '12:00 PM', '12:50 PM', false),
    PeriodSlot(0, '12:50 PM', '1:30 PM',  true,  label: 'Lunch Break'),
    PeriodSlot(5, '1:30 PM',  '2:20 PM',  false),
    PeriodSlot(6, '2:20 PM',  '3:10 PM',  false),
    PeriodSlot(7, '3:10 PM',  '4:00 PM',  false),
  ];

  static List<PeriodSlot> get teachingPeriods =>
      periods.where((p) => !p.isBreak).toList();

  static PeriodSlot? getByNumber(int num) {
    for (final p in periods) {
      if (!p.isBreak && p.number == num) return p;
    }
    return null;
  }

  // Lab blocks: Morning = periods 2,3,4 | Afternoon = periods 5,6,7
  static const List<int> morningLabPeriods    = [2, 3, 4];
  static const List<int> afternoonLabPeriods  = [5, 6, 7];

  static bool isValidLabBlock(List<int> periodNums) {
    final sorted = List<int>.from(periodNums)..sort();
    return listEquals(sorted, morningLabPeriods) ||
           listEquals(sorted, afternoonLabPeriods);
  }

  static bool listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class PeriodSlot {
  final int    number;
  final String startTime;
  final String endTime;
  final bool   isBreak;
  final String label;

  const PeriodSlot(this.number, this.startTime, this.endTime, this.isBreak,
      {this.label = ''});

  String get displayLabel => isBreak ? label : 'Period $number';

  // Returns DateTime for today at this slot's start time
  DateTime startDateTime(DateTime date) => _parseTime(date, startTime);
  DateTime endDateTime(DateTime date)   => _parseTime(date, endTime);

  DateTime _parseTime(DateTime date, String t) {
    final parts  = t.replaceAll(' AM', '').replaceAll(' PM', '').split(':');
    int hour     = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    final isPm   = t.contains('PM') && hour != 12;
    if (isPm) hour += 12;
    if (t.contains('AM') && hour == 12) hour = 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }
}

// ── Faculty ───────────────────────────────────
class Faculty {
  final String  id;           // internal UUID (primary key)
  String        employeeId;   // college-assigned Employee ID (unique, stable)
  String        name;
  String        email;
  String        passwordHash; // = employeeId by default (faculty logs in with empId)
  bool          isAdmin;

  Faculty({
    required this.id,
    required this.employeeId,
    required this.name,
    required this.email,
    required this.passwordHash,
    this.isAdmin = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'employeeId': employeeId, 'name': name, 'email': email,
    'passwordHash': passwordHash, 'isAdmin': isAdmin ? 1 : 0,
  };

  factory Faculty.fromMap(Map<String, dynamic> m) => Faculty(
    id:           (m['id']           ?? '') as String,
    employeeId:   (m['employeeId']   ?? '') as String,
    name:         (m['name']         ?? '') as String,
    email:        (m['email']        ?? '') as String,
    passwordHash: (m['passwordHash'] ?? '') as String,
    isAdmin:      m['isAdmin'] == 1,
  );
}

// ── Student ───────────────────────────────────
class Student {
  final String id;
  String       rollNumber;
  String       name;
  String       section;
  int          year;
  int          batch;        // 1 or 2
  String       passwordHash; // SHA-256; default = hash(rollNumber); recovery = hash(rollNumber+'K')

  Student({
    required this.id,
    required this.rollNumber,
    required this.name,
    required this.section,
    required this.year,
    required this.batch,
    this.passwordHash = '',  // set to hash(rollNumber) on first login
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'rollNumber': rollNumber, 'name': name,
    'section': section, 'year': year, 'batch': batch,
    'passwordHash': passwordHash,
  };

  factory Student.fromMap(Map<String, dynamic> m) => Student(
    id:           (m['id']           ?? '') as String,
    rollNumber:   (m['rollNumber']   ?? '') as String,
    passwordHash: (m['passwordHash'] ?? '') as String,
    name: (m['name'] ?? '') as String,
    section: (m['section'] ?? '') as String,
    year: (m['year'] as int?) ?? 1,
    batch: (m['batch'] as int?) ?? 1,
  );
}

// ── Subject ───────────────────────────────────
class Subject {
  final String  id;
  String        name;
  String        code;
  String        section;
  int           year;
  String        facultyId;
  String        type; // 'Theory' or 'Lab'
  int           periodsPerWeek;
  bool          isIncharge;
  int           batch; // 0 = all, 1 = batch1, 2 = batch2
  bool          labDividedIntoBatches;
  String        preference; // day/time preference hint
  String?       batch2FacultyId; // if lab split

  Subject({
    required this.id,
    required this.name,
    required this.code,
    required this.section,
    required this.year,
    required this.facultyId,
    required this.type,
    required this.periodsPerWeek,
    this.isIncharge = false,
    this.batch = 0,
    this.labDividedIntoBatches = false,
    this.preference = '',
    this.batch2FacultyId,
  });

  bool get isLab => type == 'Lab';

  /// Returns preferred NPTEL/Sports day (1=Mon..6=Sat) from the
  /// preference string. Returns null if no valid day found.
  /// Example values: "Monday", "Wednesday", "Friday", "Saturday"
  int? get preferredNptelDay {
    final p = preference.trim().toLowerCase();
    const map = {
      'monday':1,'tuesday':2,'wednesday':3,'thursday':4,'friday':5,'saturday':6,
      'mon':1,'tue':2,'wed':3,'thu':4,'fri':5,'sat':6,
    };
    return map[p];
  }

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'code': code,
    'section': section, 'year': year,
    'facultyId': facultyId, 'type': type,
    'periodsPerWeek': periodsPerWeek,
    'isIncharge': isIncharge ? 1 : 0,
    'batch': batch,
    'labDividedIntoBatches': labDividedIntoBatches ? 1 : 0,
    'preference': preference,
    'batch2FacultyId': batch2FacultyId,
  };

  factory Subject.fromMap(Map<String, dynamic> m) => Subject(
    id: (m['id'] ?? '') as String,
    name: (m['name'] ?? '') as String,
    code: (m['code'] ?? '') as String,
    section: (m['section'] ?? '') as String,
    year: (m['year'] as int?) ?? 1,
    facultyId: (m['facultyId'] ?? '') as String,
    type: (m['type'] ?? 'Theory') as String,
    periodsPerWeek: (m['periodsPerWeek'] as int?) ?? 4,
    isIncharge: m['isIncharge'] == 1,
    batch: (m['batch'] as int?) ?? 0,
    labDividedIntoBatches: m['labDividedIntoBatches'] == 1,
    preference: (m['preference'] ?? '') as String,
    batch2FacultyId: m['batch2FacultyId'] as String?,
  );
}

// ── Timetable Entry ───────────────────────────
class TimetableEntry {
  final String id;
  String       section;
  int          year;
  int          dayOfWeek; // 1=Mon … 5=Fri
  int          periodNumber;
  String       subjectId;
  String       facultyId;
  bool         isLab;
  int          batch; // 0 = all, 1, 2
  String?      specialLabel; // NPTEL, Mentoring, Sports

  TimetableEntry({
    required this.id,
    required this.section,
    required this.year,
    required this.dayOfWeek,
    required this.periodNumber,
    required this.subjectId,
    required this.facultyId,
    this.isLab = false,
    this.batch = 0,
    this.specialLabel,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'section': section, 'year': year,
    'dayOfWeek': dayOfWeek, 'periodNumber': periodNumber,
    'subjectId': subjectId, 'facultyId': facultyId,
    'isLab': isLab ? 1 : 0, 'batch': batch,
    'specialLabel': specialLabel,
  };

  factory TimetableEntry.fromMap(Map<String, dynamic> m) => TimetableEntry(
    id: m['id'], section: m['section'], year: m['year'],
    dayOfWeek: m['dayOfWeek'], periodNumber: m['periodNumber'],
    subjectId: m['subjectId'], facultyId: m['facultyId'],
    isLab: m['isLab'] == 1, batch: m['batch'],
    specialLabel: m['specialLabel'],
  );
}

// ── Attendance Record ─────────────────────────
class AttendanceRecord {
  final String id;
  String       studentId;
  String       subjectId;
  String       facultyId;
  String       section;
  int          periodNumber;
  DateTime     date;
  bool         isPresent;
  // v2 additions — uniquely identify the timetable session
  String       timetableEntryId; // which TimetableEntry this was for
  int          batch;            // 0=full class, 1=batch1, 2=batch2
  int          dayOfWeek;        // 1=Mon..6=Sat

  AttendanceRecord({
    required this.id,
    required this.studentId,
    required this.subjectId,
    required this.facultyId,
    required this.section,
    required this.periodNumber,
    required this.date,
    required this.isPresent,
    this.timetableEntryId = '',
    this.batch            = 0,
    this.dayOfWeek        = 1,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'studentId': studentId, 'subjectId': subjectId,
    'facultyId': facultyId, 'section': section,
    'periodNumber': periodNumber,
    'date': date.toIso8601String(), 'isPresent': isPresent ? 1 : 0,
    'timetableEntryId': timetableEntryId,
    'batch': batch,
    'dayOfWeek': dayOfWeek,
  };

  factory AttendanceRecord.fromMap(Map<String, dynamic> m) => AttendanceRecord(
    id:               m['id'],
    studentId:        m['studentId'],
    subjectId:        m['subjectId'],
    facultyId:        m['facultyId'],
    section:          m['section'],
    periodNumber:     m['periodNumber'],
    date:             DateTime.parse(m['date']),
    isPresent:        m['isPresent'] == 1,
    timetableEntryId: (m['timetableEntryId'] ?? '') as String,
    batch:            (m['batch'] as int?) ?? 0,
    dayOfWeek:        (m['dayOfWeek'] as int?) ?? 1,
  );

  /// Date string used for DB queries: "yyyy-MM-dd"
  String get dateKey => date.toIso8601String().substring(0, 10);
}

// ── Notification Schedule ─────────────────────
class NotificationSchedule {
  final int    id;
  String       title;
  String       body;
  DateTime     scheduledTime;
  String       payload;
  bool         isRepeating;

  NotificationSchedule({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledTime,
    required this.payload,
    this.isRepeating = false,
  });
}

// ── Special Slot ──────────────────────────────
class SpecialSlot {
  final String id;
  String       section;
  int          year;
  int          dayOfWeek;
  int          periodNumber;
  String       label; // NPTEL / Mentoring / Sports

  SpecialSlot({
    required this.id, required this.section, required this.year,
    required this.dayOfWeek, required this.periodNumber, required this.label,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'section': section, 'year': year,
    'dayOfWeek': dayOfWeek, 'periodNumber': periodNumber, 'label': label,
  };

  factory SpecialSlot.fromMap(Map<String, dynamic> m) => SpecialSlot(
    id: m['id'], section: m['section'], year: m['year'],
    dayOfWeek: m['dayOfWeek'], periodNumber: m['periodNumber'], label: m['label'],
  );
}
