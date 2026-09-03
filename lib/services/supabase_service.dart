// ══════════════════════════════════════════════════════════════════════════════
//  SupabaseService — Cloud sync for TimetableOS
//
//  HOW IT WORKS:
//  • Supabase is a free, open-source Firebase alternative backed by PostgreSQL
//  • All 6 tables mirror the local SQLite schema exactly
//  • Sync is one-way write (local → cloud) after each import / generate / mark
//  • On login, the app pulls fresh data from Supabase into local SQLite
//  • This means data is always available on ANY device with the same credentials
//
//  SETUP (one-time, takes 5 minutes):
//  1. Go to https://supabase.com → Create free project
//  2. Copy Project URL and anon key into SUPABASE_URL / SUPABASE_ANON_KEY below
//  3. Run the SQL in supabase_schema.sql in the Supabase SQL editor
//  4. Done — all devices share the same data
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'database_service.dart';

// ─── CONFIGURE THESE TWO VALUES ───────────────────────────────────────────────
const String SUPABASE_URL      = 'YOUR_SUPABASE_URL';   // e.g. https://xxxx.supabase.co
const String SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY'; // long JWT string from Supabase
// ──────────────────────────────────────────────────────────────────────────────

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  bool _initialized = false;
  bool _available   = false;

  SupabaseClient get _client => Supabase.instance.client;

  /// Returns true if Supabase is reachable (has real credentials + internet)
  bool get isAvailable => _available;

  // ── Initialise ─────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (SUPABASE_URL == 'YOUR_SUPABASE_URL') {
      debugPrint('SupabaseService: not configured — running offline only');
      return;
    }

    try {
      await Supabase.initialize(
        url:     SUPABASE_URL,
        anonKey: SUPABASE_ANON_KEY,
      );
      _available = true;
      debugPrint('SupabaseService: connected ✓');
    } catch (e) {
      debugPrint('SupabaseService: init failed — $e');
      _available = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  PUSH  local SQLite → Supabase  (called after import / generate / mark)
  // ══════════════════════════════════════════════════════════════════════════

  /// Push ALL data (full sync). Called after import or generate.
  Future<void> pushAll() async {
    if (!_available) return;
    try {
      final db = DatabaseService();
      await Future.wait([
        _pushFaculty(db),
        _pushStudents(db),
        _pushSubjects(db),
        _pushTimetableEntries(db),
        _pushSpecialSlots(db),
      ]);
      debugPrint('SupabaseService: full push done');
    } catch (e) {
      debugPrint('SupabaseService: pushAll error — $e');
    }
  }

  /// Push only attendance records for a specific date (called after marking)
  Future<void> pushAttendanceForDate(String date, String section, int year) async {
    if (!_available) return;
    try {
      final db = DatabaseService();
      final records = await db.getAttendanceByDateSectionYear(date, section, year);
      if (records.isEmpty) return;
      await _client
          .from('attendance_records')
          .upsert(records.map((r) => r.toMap()).toList(),
              onConflict: 'id');
      debugPrint('SupabaseService: pushed ${records.length} attendance records');
    } catch (e) {
      debugPrint('SupabaseService: pushAttendance error — $e');
    }
  }

  Future<void> _pushFaculty(DatabaseService db) async {
    final items = await db.getAllFaculty();
    if (items.isEmpty) return;
    await _client.from('faculty').upsert(
        items.map((f) => f.toMap()).toList(), onConflict: 'id');
  }

  Future<void> _pushStudents(DatabaseService db) async {
    final items = await db.getAllStudents();
    if (items.isEmpty) return;
    await _client.from('students').upsert(
        items.map((s) => s.toMap()).toList(), onConflict: 'id');
  }

  Future<void> _pushSubjects(DatabaseService db) async {
    final items = await db.getAllSubjects();
    if (items.isEmpty) return;
    await _client.from('subjects').upsert(
        items.map((s) => s.toMap()).toList(), onConflict: 'id');
  }

  Future<void> _pushTimetableEntries(DatabaseService db) async {
    final items = await db.getAllTimetableEntries();
    if (items.isEmpty) return;
    await _client.from('timetable_entries').upsert(
        items.map((e) => e.toMap()).toList(), onConflict: 'id');
  }

  Future<void> _pushSpecialSlots(DatabaseService db) async {
    final items = await db.getAllSpecialSlots();
    if (items.isEmpty) return;
    await _client.from('special_slots').upsert(
        items.map((s) => s.toMap()).toList(), onConflict: 'id');
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  PULL  Supabase → local SQLite  (called on login / app start)
  // ══════════════════════════════════════════════════════════════════════════

  /// Pull all cloud data into local SQLite. Called once on successful login.
  Future<SyncResult> pullAll() async {
    if (!_available) return SyncResult(synced: false, message: 'Offline mode');
    try {
      final db = DatabaseService();
      int counts = 0;

      // Faculty
      final facultyRows = await _client.from('faculty').select();
      if (facultyRows.isNotEmpty) {
        final faculty = facultyRows.map((r) => Faculty.fromMap(_fixMap(r))).toList();
        await db.insertManyFaculty(faculty);
        counts += faculty.length;
      }

      // Students
      final studentRows = await _client.from('students').select();
      if (studentRows.isNotEmpty) {
        final students = studentRows.map((r) => Student.fromMap(_fixMap(r))).toList();
        await db.insertManyStudents(students);
        counts += students.length;
      }

      // Subjects
      final subjectRows = await _client.from('subjects').select();
      if (subjectRows.isNotEmpty) {
        final subjects = subjectRows.map((r) => Subject.fromMap(_fixMap(r))).toList();
        await db.insertManySubjects(subjects);
        counts += subjects.length;
      }

      // Timetable entries
      final ttRows = await _client.from('timetable_entries').select();
      if (ttRows.isNotEmpty) {
        final entries = ttRows.map((r) => TimetableEntry.fromMap(_fixMap(r))).toList();
        await db.insertManyTimetableEntries(entries);
        counts += entries.length;
      }

      // Attendance records (only current semester — last 6 months)
      final sixMonthsAgo = DateTime.now().subtract(const Duration(days: 180));
      final attRows = await _client
          .from('attendance_records')
          .select()
          .gte('date', sixMonthsAgo.toIso8601String().substring(0, 10));
      if (attRows.isNotEmpty) {
        final records = attRows
            .map((r) => AttendanceRecord.fromMap(_fixMap(r)))
            .toList();
        await db.insertManyAttendanceRecords(records);
        counts += records.length;
      }

      // Special slots
      final ssRows = await _client.from('special_slots').select();
      if (ssRows.isNotEmpty) {
        final slots = ssRows.map((r) => SpecialSlot.fromMap(_fixMap(r))).toList();
        await db.insertManySpecialSlots(slots);
        counts += slots.length;
      }

      debugPrint('SupabaseService: pulled $counts records');
      return SyncResult(synced: true, message: 'Synced $counts records from cloud');
    } catch (e) {
      debugPrint('SupabaseService: pullAll error — $e');
      return SyncResult(synced: false, message: 'Sync failed: $e');
    }
  }

  /// Convert Supabase response map types to match SQLite (booleans → int etc.)
  Map<String, dynamic> _fixMap(Map<String, dynamic> m) {
    final fixed = <String, dynamic>{};
    for (final k in m.keys) {
      final v = m[k];
      if (v is bool) {
        fixed[k] = v ? 1 : 0;
      } else {
        fixed[k] = v;
      }
    }
    return fixed;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  PUSH SINGLE RECORDS  (granular updates)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> upsertFaculty(Faculty f) async {
    if (!_available) return;
    try {
      await _client.from('faculty').upsert(f.toMap(), onConflict: 'id');
    } catch (e) { debugPrint('upsertFaculty error: $e'); }
  }

  Future<void> upsertStudent(Student s) async {
    if (!_available) return;
    try {
      await _client.from('students').upsert(s.toMap(), onConflict: 'id');
    } catch (e) { debugPrint('upsertStudent error: $e'); }
  }

  Future<void> deleteAllTimetableEntries() async {
    if (!_available) return;
    try {
      await _client.from('timetable_entries').delete().neq('id', '');
    } catch (e) { debugPrint('deleteAllTimetableEntries error: $e'); }
  }

  Future<void> deleteAttendanceBySection(String section, int year) async {
    if (!_available) return;
    try {
      await _client.from('attendance_records')
          .delete()
          .eq('section', section)
          .eq('year', year);
    } catch (e) { debugPrint('deleteAttendanceBySection error: $e'); }
  }

  Future<void> updatePassword(String table, String id, String hash) async {
    if (!_available) return;
    try {
      await _client.from(table).update({'passwordHash': hash}).eq('id', id);
    } catch (e) { debugPrint('updatePassword error: $e'); }
  }
}

class SyncResult {
  final bool   synced;
  final String message;
  SyncResult({required this.synced, required this.message});
}
