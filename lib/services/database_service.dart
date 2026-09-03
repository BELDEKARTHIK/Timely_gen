import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';
import 'security_helper.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    try {
      final dbPath = await getDatabasesPath();
      // On web, dbPath may be empty — use just the filename (IndexedDB key)
      final path = dbPath.isEmpty ? 'timetable.db' : join(dbPath, 'timetable.db');
      return await openDatabase(
        path, version: 6,
        onCreate: _createTables,
        onUpgrade: _onUpgrade,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception(
          'Database open timed out. On web, ensure sqlite3.wasm is available.'),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      for (final col in [
        'ALTER TABLE attendance_records ADD COLUMN timetableEntryId TEXT NOT NULL DEFAULT ""',
        'ALTER TABLE attendance_records ADD COLUMN batch INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE attendance_records ADD COLUMN dayOfWeek INTEGER NOT NULL DEFAULT 1',
      ]) { try { await db.execute(col); } catch(_) {} }
    }
    if (oldV < 3) {
      // Add performance indices for existing databases
      final indices = [
        'CREATE INDEX IF NOT EXISTS idx_subjects_sec_yr ON subjects(section, year)',
        'CREATE INDEX IF NOT EXISTS idx_tt_sec_yr ON timetable_entries(section, year)',
        'CREATE INDEX IF NOT EXISTS idx_tt_faculty ON timetable_entries(facultyId)',
        'CREATE INDEX IF NOT EXISTS idx_att_student ON attendance_records(studentId)',
        'CREATE INDEX IF NOT EXISTS idx_att_subject ON attendance_records(subjectId)',
        'CREATE INDEX IF NOT EXISTS idx_att_entry ON attendance_records(timetableEntryId)',
        'CREATE INDEX IF NOT EXISTS idx_ss_sec_yr ON special_slots(section, year)',
        'CREATE INDEX IF NOT EXISTS idx_subjects_year ON subjects(year)',
        'CREATE INDEX IF NOT EXISTS idx_students_sec_yr ON students(section, year)',
      ];
      for (final idx in indices) { try { await db.execute(idx); } catch(_) {} }
    }
    if (oldV < 4) {
      // Add employeeId column to faculty — existing rows get empty string,
      // admin account gets 'ADMIN' as employeeId
      try {
        await db.execute(
            "ALTER TABLE faculty ADD COLUMN employeeId TEXT NOT NULL DEFAULT ''");
        await db.execute(
            "UPDATE faculty SET employeeId = 'ADMIN' WHERE isAdmin = 1");
        await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_faculty_empid ON faculty(employeeId)');
      } catch(_) {}
    }
    if (oldV < 5) {
      for (final col in [
        "ALTER TABLE subjects ADD COLUMN preference TEXT DEFAULT ''",
        "ALTER TABLE subjects ADD COLUMN labDividedIntoBatches INTEGER DEFAULT 0",
        "ALTER TABLE subjects ADD COLUMN batch2FacultyId TEXT",
      ]) { try { await db.execute(col); } catch(_) {} }
    }
    if (oldV < 6) {
      // Add passwordHash to students (empty = use default = hash(rollNumber))
      // Add passwordHash to faculty was already TEXT; we leave existing values
      // intact — they'll be migrated to hashed form on first successful login.
      try {
        await db.execute(
            "ALTER TABLE students ADD COLUMN passwordHash TEXT NOT NULL DEFAULT ''");
      } catch(_) {}
    }
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE faculty (
        id TEXT PRIMARY KEY,
        employeeId TEXT UNIQUE NOT NULL DEFAULT '',
        name TEXT, email TEXT,
        passwordHash TEXT, isAdmin INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE students (
        id TEXT PRIMARY KEY, rollNumber TEXT UNIQUE, name TEXT,
        section TEXT, year INTEGER, batch INTEGER,
        passwordHash TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE subjects (
        id TEXT PRIMARY KEY, name TEXT, code TEXT,
        section TEXT, year INTEGER, facultyId TEXT,
        type TEXT, periodsPerWeek INTEGER, isIncharge INTEGER,
        batch INTEGER, labDividedIntoBatches INTEGER,
        preference TEXT, batch2FacultyId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE timetable_entries (
        id TEXT PRIMARY KEY, section TEXT, year INTEGER,
        dayOfWeek INTEGER, periodNumber INTEGER,
        subjectId TEXT, facultyId TEXT,
        isLab INTEGER DEFAULT 0, batch INTEGER DEFAULT 0,
        specialLabel TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE attendance_records (
        id TEXT PRIMARY KEY, studentId TEXT, subjectId TEXT,
        facultyId TEXT, section TEXT, periodNumber INTEGER,
        date TEXT, isPresent INTEGER,
        timetableEntryId TEXT NOT NULL DEFAULT "",
        batch INTEGER NOT NULL DEFAULT 0,
        dayOfWeek INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE special_slots (
        id TEXT PRIMARY KEY, section TEXT, year INTEGER,
        dayOfWeek INTEGER, periodNumber INTEGER, label TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY, value TEXT
      )
    ''');

    // ── Performance indices ───────────────────────────────────────────────
    // These dramatically speed up queries on large datasets (20 sections)
    await db.execute(
        'CREATE INDEX idx_subjects_sec_yr ON subjects(section, year)');
    await db.execute(
        'CREATE INDEX idx_tt_sec_yr ON timetable_entries(section, year)');
    await db.execute(
        'CREATE INDEX idx_tt_faculty ON timetable_entries(facultyId)');
    await db.execute(
        'CREATE INDEX idx_att_student ON attendance_records(studentId)');
    await db.execute(
        'CREATE INDEX idx_att_subject ON attendance_records(subjectId)');
    await db.execute(
        'CREATE INDEX idx_att_entry ON attendance_records(timetableEntryId)');
    await db.execute(
        'CREATE INDEX idx_ss_sec_yr ON special_slots(section, year)');
    await db.execute(
        'CREATE INDEX idx_subjects_year ON subjects(year)');
    await db.execute(
        'CREATE INDEX idx_students_sec_yr ON students(section, year)');

    // Default admin
    await db.insert('faculty', {
      'id': 'admin_001',
      'employeeId': 'ADMIN',
      'name': 'Admin',
      'email': 'admin@college.edu',
      // Default: admin123  — hashed with SHA-256(ADMIN:admin123)
      'passwordHash': SecurityHelper.hashPassword('admin123', 'ADMIN'),
      'isAdmin': 1,
    });
  }

  // ── Faculty ─────────────────────────────────
  Future<void> insertFaculty(Faculty f) async =>
      (await db).insert('faculty', f.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Faculty>> getAllFaculty() async {
    final rows = await (await db).query('faculty');
    return rows.map(Faculty.fromMap).toList();
  }

  Future<Faculty?> getFacultyByEmployeeId(String employeeId) async {
    final rows = await (await db).query('faculty',
        where: 'employeeId = ?', whereArgs: [employeeId]);
    if (rows.isEmpty) return null;
    return Faculty.fromMap(rows.first);
  }

  Future<Faculty?> getFacultyByEmail(String email) async {
    final rows = await (await db).query('faculty', where: 'email = ?', whereArgs: [email]);
    return rows.isEmpty ? null : Faculty.fromMap(rows.first);
  }

  Future<Faculty?> getFacultyById(String id) async {
    final rows = await (await db).query('faculty', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Faculty.fromMap(rows.first);
  }

  // ── Students ─────────────────────────────────
  /// Returns first N roll numbers stored — for debugging login issues
  Future<List<String>> getSampleRollNumbers({int limit = 5}) async {
    final rows = await (await db).query('students',
        columns: ['rollNumber'], limit: limit, orderBy: 'rollNumber ASC');
    return rows.map((r) => r['rollNumber'] as String).toList();
  }

  Future<void> insertStudent(Student s) async =>
      (await db).insert('students', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Student>> getAllStudents() async {
    final rows = await (await db).query('students');
    return rows.map(Student.fromMap).toList();
  }

  Future<Student?> getStudentByRollNumber(String roll) async {
    // Normalize to uppercase for consistent matching
    final normalized = roll.trim().toUpperCase();
    // Try exact match first, then case-insensitive
    var rows = await (await db).query('students',
        where: 'rollNumber = ?', whereArgs: [normalized]);
    if (rows.isEmpty) {
      // Fallback: case-insensitive search (handles legacy imported data)
      rows = await (await db).query('students',
          where: 'UPPER(rollNumber) = ?', whereArgs: [normalized]);
    }
    return rows.isEmpty ? null : Student.fromMap(rows.first);
  }

  Future<List<Student>> getStudentsBySection(String section, int year) async {
    final rows = await (await db).query('students',
        where: 'section = ? AND year = ?', whereArgs: [section, year]);
    return rows.map(Student.fromMap).toList();
  }

  // ── Subjects ──────────────────────────────────
  Future<void> insertSubject(Subject s) async =>
      (await db).insert('subjects', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Subject>> getAllSubjects() async {
    final rows = await (await db).query('subjects');
    return rows.map(Subject.fromMap).toList();
  }

  Future<List<Subject>> getSubjectsByYear(int year) async {
    final rows = await (await db).query('subjects',
        where: 'year = ?', whereArgs: [year]);
    return rows.map(Subject.fromMap).toList();
  }

  Future<List<int>> getDistinctYears() async {
    final rows = await (await db).rawQuery(
        'SELECT DISTINCT year FROM subjects ORDER BY year');
    return rows.map((r) => r['year'] as int).toList();
  }

  Future<void> updateFacultyPassword(String facultyId, String newHash) async {
    await (await db).update('faculty', {'passwordHash': newHash},
        where: 'id = ?', whereArgs: [facultyId]);
  }

  Future<void> updateStudentPassword(String studentId, String newHash) async {
    await (await db).update('students', {'passwordHash': newHash},
        where: 'id = ?', whereArgs: [studentId]);
  }

  Future<List<String>> getDistinctSections() async {
    final rows = await (await db).rawQuery(
        "SELECT DISTINCT section || '_' || year as key FROM subjects ORDER BY year, section");
    return rows.map((r) => r['key'] as String).toList();
  }


  /// Returns list of {section, year} from imported subjects — drives all dropdowns
  Future<List<Map<String, dynamic>>> getSectionYearPairs() async {
    final rows = await (await db).rawQuery(
        'SELECT DISTINCT section, year FROM subjects ORDER BY year ASC, section ASC');
    return rows.map((r) => {
      'section': r['section'] as String,
      'year':    r['year']    as int,
    }).toList();
  }

  /// Returns distinct sections for a given year — drives section dropdown after year pick
  Future<List<String>> getSectionsForYear(int year) async {
    final rows = await (await db).rawQuery(
        'SELECT DISTINCT section FROM subjects WHERE year = ? ORDER BY section ASC',
        [year]);
    return rows.map((r) => r['section'] as String).toList();
  }
  Future<void> clearTimetableByYear(int year) async {
    await (await db).delete('timetable_entries',
        where: 'year = ?', whereArgs: [year]);
    await (await db).delete('special_slots',
        where: 'year = ?', whereArgs: [year]);
  }

  Future<int> getTimetableCountByYear(int year) async {
    final rows = await (await db).rawQuery(
        'SELECT COUNT(*) as c FROM timetable_entries WHERE year = ?', [year]);
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<List<Subject>> getSubjectsBySection(String section, int year) async {
    final rows = await (await db).query('subjects',
        where: 'section = ? AND year = ?', whereArgs: [section, year]);
    return rows.map(Subject.fromMap).toList();
  }

  Future<List<Subject>> getSubjectsByFaculty(String facultyId) async {
    final rows = await (await db).query('subjects', where: 'facultyId = ?', whereArgs: [facultyId]);
    return rows.map(Subject.fromMap).toList();
  }

  // ── Timetable ─────────────────────────────────
  Future<void> insertTimetableEntry(TimetableEntry e) async =>
      (await db).insert('timetable_entries', e.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> clearTimetable(String section, int year) async {
    final d = await db;
    await d.delete('timetable_entries',
        where: 'section = ? AND year = ?', whereArgs: [section, year]);
    // Also clear special slots so they're regenerated fresh next time
    await d.delete('special_slots',
        where: 'section = ? AND year = ?', whereArgs: [section, year]);
  }

  Future<void> clearAllTimetables() async =>
      (await db).delete('timetable_entries');

  // ── Full data reset helpers ────────────────────────────────────────────────
  Future<void> deleteAllSubjects() async =>
      (await db).delete('subjects');

  Future<void> deleteAllStudents() async =>
      (await db).delete('students');

  Future<void> deleteAllFaculty() async {
    final d = await db;
    // Keep the default admin account — delete imported faculty only
    await d.delete('faculty', where: 'isAdmin = ?', whereArgs: [0]);
  }

  Future<void> deleteAllAttendance() async =>
      (await db).delete('attendance_records');

  /// Wipes timetable + subjects + students + non-admin faculty + attendance.
  /// Admin account is preserved so the user can still log in.
  Future<void> resetAllData() async {
    final d = await db;
    final b = d.batch();
    b.delete('timetable_entries');
    b.delete('special_slots');
    b.delete('subjects');
    b.delete('students');
    b.delete('attendance_records');
    b.delete('faculty', where: 'isAdmin = ?', whereArgs: [0]);
    await b.commit(noResult: true);
  }

  /// Returns count of timetable entries currently stored.
  Future<int> getTimetableCount() async {
    final rows = await (await db).rawQuery(
        'SELECT COUNT(*) as c FROM timetable_entries');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<List<TimetableEntry>> getTimetableBySection(String section, int year) async {
    final rows = await (await db).query('timetable_entries',
        where: 'section = ? AND year = ?', whereArgs: [section, year],
        orderBy: 'dayOfWeek, periodNumber');
    return rows.map(TimetableEntry.fromMap).toList();
  }

  Future<List<TimetableEntry>> getTimetableByFaculty(String facultyId) async {
    final rows = await (await db).query('timetable_entries',
        where: 'facultyId = ?', whereArgs: [facultyId],
        orderBy: 'dayOfWeek, periodNumber');
    return rows.map(TimetableEntry.fromMap).toList();
  }

  Future<List<TimetableEntry>> getAllTimetableEntries() async {
    final rows = await (await db).query('timetable_entries');
    return rows.map(TimetableEntry.fromMap).toList();
  }

  // ── Attendance ────────────────────────────────
  Future<void> insertAttendance(AttendanceRecord r) async =>
      (await db).insert('attendance_records', r.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<AttendanceRecord>> getAttendanceForStudent(String studentId) async {
    final rows = await (await db).query('attendance_records',
        where: 'studentId = ?', whereArgs: [studentId], orderBy: 'date DESC');
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  Future<List<AttendanceRecord>> getAttendanceBySubject(
      String subjectId, String studentId) async {
    final rows = await (await db).query('attendance_records',
        where: 'subjectId = ? AND studentId = ?',
        whereArgs: [subjectId, studentId]);
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  Future<List<AttendanceRecord>> getAttendanceByDateSection(
      DateTime date, String section, int period) async {
    final rows = await (await db).query('attendance_records',
        where: 'section = ? AND periodNumber = ? AND date LIKE ?',
        whereArgs: [section, period, '${date.toIso8601String().substring(0, 10)}%']);
    return rows.map(AttendanceRecord.fromMap).toList();
  }
  /// Fetch all attendance records for a given date string + section + year
  /// Used by Supabase push after marking attendance
  Future<List<AttendanceRecord>> getAttendanceByDateSectionYear(
      String dateStr, String section, int year) async {
    final rows = await (await db).query('attendance_records',
        where: 'section = ? AND date = ?',
        whereArgs: [section, dateStr]);
    return rows.map(AttendanceRecord.fromMap).toList();
  }



  Future<List<AttendanceRecord>> getAttendanceByFacultyDate(
      String facultyId, DateTime date) async {
    final rows = await (await db).query('attendance_records',
        where: 'facultyId = ? AND date LIKE ?',
        whereArgs: [facultyId, '${date.toIso8601String().substring(0, 10)}%']);
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  // ── Special Slots ─────────────────────────────
  Future<void> clearAllSpecialSlots() async =>
      (await db).delete('special_slots');

  Future<void> insertSpecialSlot(SpecialSlot s) async =>
      (await db).insert('special_slots', s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<SpecialSlot>> getSpecialSlots(String section, int year) async {
    final rows = await (await db).query('special_slots',
        where: 'section = ? AND year = ?', whereArgs: [section, year]);
    return rows.map(SpecialSlot.fromMap).toList();
  }

  Future<List<SpecialSlot>> getAllSpecialSlots() async {
    final rows = await (await db).query('special_slots');
    return rows.map(SpecialSlot.fromMap).toList();
  }

  // ── Settings ──────────────────────────────────
  Future<void> setSetting(String key, String value) async =>
      (await db).insert('app_settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<String?> getSetting(String key) async {
    final rows = await (await db).query('app_settings',
        where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  // ── Bulk inserts ──────────────────────────────
  Future<void> insertManyTimetableEntries(List<TimetableEntry> entries) async {
    final batch = (await db).batch();
    for (final e in entries) {
      batch.insert('timetable_entries', e.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> insertManyAttendance(List<AttendanceRecord> records) async {
    final batch = (await db).batch();
    for (final r in records) {
      batch.insert('attendance_records', r.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> insertManyStudents(List<Student> students) async {
    final d = await db;
    final txn = d.batch();
    for (final s in students) {
      txn.insert('students', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await txn.commit(noResult: true);
  }

  Future<void> insertManyFaculty(List<Faculty> faculty) async {
    if (faculty.isEmpty) return;
    final d = await db;
    final txn = d.batch();
    // Remove all previously imported (non-admin) faculty before inserting fresh.
    // This prevents ghost records from old imports mixing with new ones.
    txn.delete('faculty', where: 'isAdmin = ?', whereArgs: [0]);
    for (final f in faculty) {
      txn.insert('faculty', f.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await txn.commit(noResult: true);
  }

  /// Clears all existing subjects for the sections being imported,
  /// then inserts fresh rows. This prevents stale subjects (e.g. with
  /// empty preference) from remaining alongside new ones.
  Future<void> insertManySubjects(List<Subject> subjects) async {
    if (subjects.isEmpty) return;
    final d = await db;

    // Collect unique section+year combos from the incoming data
    final sectionYears = subjects
        .map((s) => '${s.section}_${s.year}')
        .toSet();

    final txn = d.batch();

    // Delete old subjects for these sections first (avoids stale preference rows)
    for (final sy in sectionYears) {
      final parts = sy.split('_');
      txn.delete('subjects',
          where: 'section = ? AND year = ?',
          whereArgs: [parts[0], int.parse(parts[1])]);
    }

    // Insert fresh subjects
    for (final s in subjects) {
      txn.insert('subjects', s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await txn.commit(noResult: true);
  }

  // ── Attendance: session-aware queries ─────────────────────────────────────

  /// True if faculty already submitted for this timetable entry on this date.
  Future<void> insertManyAttendanceRecords(List<AttendanceRecord> records) async {
    if (records.isEmpty) return;
    final d = await db;
    final txn = d.batch();
    for (final r in records) {
      txn.insert('attendance_records', r.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await txn.commit(noResult: true);
  }

  Future<void> insertManySpecialSlots(List<SpecialSlot> slots) async {
    if (slots.isEmpty) return;
    final d = await db;
    final txn = d.batch();
    for (final s in slots) {
      txn.insert('special_slots', s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await txn.commit(noResult: true);
  }


  Future<bool> hasMarkedSession({
    required String   timetableEntryId,
    required DateTime date,
  }) async {
    final ds = date.toIso8601String().substring(0, 10);
    final rows = await (await db).query('attendance_records',
      where: 'timetableEntryId = ? AND date LIKE ?',
      whereArgs: [timetableEntryId, '$ds%'], limit: 1);
    return rows.isNotEmpty;
  }

  /// All records for one session + date (for editing).
  Future<List<AttendanceRecord>> getSessionRecords({
    required String   timetableEntryId,
    required DateTime date,
  }) async {
    final ds = date.toIso8601String().substring(0, 10);
    final rows = await (await db).query('attendance_records',
      where: 'timetableEntryId = ? AND date LIKE ?',
      whereArgs: [timetableEntryId, '$ds%'], orderBy: 'studentId');
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  /// All records for a faculty between two dates.
  Future<List<AttendanceRecord>> getAttendanceByFacultyRange({
    required String   facultyId,
    required DateTime from,
    required DateTime to,
  }) async {
    final f = from.toIso8601String().substring(0, 10);
    final t = to.toIso8601String().substring(0, 10);
    final rows = await (await db).query('attendance_records',
      where: 'facultyId = ? AND date >= ? AND date <= ?',
      whereArgs: [facultyId, f, '${t}T23:59:59'],
      orderBy: 'date DESC, periodNumber ASC');
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  /// Distinct sessions a faculty has marked (grouped by entry+date).
  Future<List<Map<String, dynamic>>> getMarkedSessions({
    required String   facultyId,
    required DateTime from,
    required DateTime to,
  }) async {
    final f = from.toIso8601String().substring(0, 10);
    final t = to.toIso8601String().substring(0, 10);
    final sql = '''
      SELECT timetableEntryId, section, periodNumber, subjectId, batch,
             substr(date,1,10) AS dateKey,
             SUM(isPresent)    AS presentCount,
             COUNT(*)          AS totalCount
      FROM attendance_records
      WHERE facultyId = ? AND date >= ? AND date <= ?
      GROUP BY timetableEntryId, dateKey
      ORDER BY dateKey DESC, periodNumber ASC
    ''';
    return (await (await db).rawQuery(sql, [facultyId, f, '${t}T23:59:59'])).toList();
  }

  /// Delete records older than [days] days.
  /// Default is 180 days (one full semester).
  /// Call with days=365 for a full academic year retention.
  Future<void> pruneOldAttendance({int days = 180}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final cs = cutoff.toIso8601String().substring(0, 10);
    await (await db).delete('attendance_records', where: 'date < ?', whereArgs: [cs]);
  }

  /// Update a single record's presence.
  Future<void> updateAttendancePresence(String id, bool isPresent) async =>
    (await db).update('attendance_records', {'isPresent': isPresent ? 1 : 0},
      where: 'id = ?', whereArgs: [id]);

  /// Delete all records for a session (before re-submission).
  Future<void> deleteSessionRecords({
    required String   timetableEntryId,
    required DateTime date,
  }) async {
    final ds = date.toIso8601String().substring(0, 10);
    await (await db).delete('attendance_records',
      where: 'timetableEntryId = ? AND date LIKE ?',
      whereArgs: [timetableEntryId, '$ds%']);
  }
  // ── Archive / Storage Management ─────────────────────────────────────────

  /// Count attendance records for a section+year.
  Future<int> countAttendanceBySection(String section, int year) async {
    final students = await getStudentsBySection(section, year);
    if (students.isEmpty) return 0;
    final ids = students.map((s) => "'${s.id}'").join(',');
    final result = await (await db).rawQuery(
        'SELECT COUNT(*) as cnt FROM attendance_records WHERE studentId IN ($ids)');
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// All attendance records for a section+year (export before delete).
  Future<List<AttendanceRecord>> getAttendanceBySection(
      String section, int year) async {
    final students = await getStudentsBySection(section, year);
    if (students.isEmpty) return [];
    final ids = students.map((s) => "'${s.id}'").join(',');
    final rows = await (await db).rawQuery(
        'SELECT * FROM attendance_records '
        'WHERE studentId IN ($ids) ORDER BY date, periodNumber');
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  /// Delete all attendance for a section+year. Export first!
  Future<int> deleteAttendanceBySection(String section, int year) async {
    final students = await getStudentsBySection(section, year);
    if (students.isEmpty) return 0;
    final ids = students.map((s) => "'${s.id}'").join(',');
    return (await db).rawDelete(
        'DELETE FROM attendance_records WHERE studentId IN ($ids)');
  }

  /// Attendance storage summary per section.
  Future<List<Map<String, dynamic>>> getAttendanceSummaryBySections() async {
    const sql = """
      SELECT s.section, s.year,
             COUNT(*) AS records,
             CAST(COUNT(*) * 280 AS INTEGER) AS est_bytes
      FROM attendance_records a
      JOIN students s ON s.id = a.studentId
      GROUP BY s.section, s.year
      ORDER BY s.year, s.section
    """;
    return (await (await db).rawQuery(sql)).toList();
  }

  /// Get sections where a faculty is the class incharge.
  Future<List<Map<String, dynamic>>> getInchargeSections(
      String facultyId) async {
    final rows = await (await db).query('subjects',
        columns: ['section', 'year'],
        where: 'facultyId = ? AND isIncharge = 1',
        whereArgs: [facultyId]);
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final r in rows) {
      final key = '${r['section']}_${r['year']}';
      if (seen.add(key)) result.add({'section': r['section'], 'year': r['year']});
    }
    return result;
  }

}