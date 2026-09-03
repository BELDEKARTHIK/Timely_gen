import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'database_service.dart';
import 'security_helper.dart';
import 'supabase_service.dart';

enum UserRole { admin, faculty, student, none }

class AuthService extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();

  UserRole _role    = UserRole.none;
  Faculty? _faculty;
  Student? _student;

  UserRole get role     => _role;
  Faculty? get faculty  => _faculty;
  Student? get student  => _student;
  bool get isLoggedIn   => _role != UserRole.none;
  bool get isAdmin      => _role == UserRole.admin;
  bool get isFaculty    => _role == UserRole.faculty;
  bool get isStudent    => _role == UserRole.student;

  String? get currentUserId {
    if (_faculty != null) return _faculty!.id;
    if (_student != null) return _student!.id;
    return null;
  }

  // ── Faculty / Admin login ──────────────────────────────────────────────────
  // Input: Employee ID (e.g. TCH001) or email (admin fallback)
  // Password check order:
  //   1. SHA-256(employeeId:password) — new hashed passwords
  //   2. Plain text comparison — legacy (migrates on success)
  //   3. email fallback for admin
  Future<String?> loginFaculty(String employeeIdOrEmail, String password) async {
    final input = employeeIdOrEmail.trim();
    final rateLimitKey = 'faculty:${input.toUpperCase()}';

    // Rate limit check
    final blocked = SecurityHelper.checkRateLimit(rateLimitKey);
    if (blocked != null) return blocked;

    Faculty? f;
    f = await _db.getFacultyByEmployeeId(input.toUpperCase());
    f ??= await _db.getFacultyByEmail(input.toLowerCase());

    if (f == null) {
      SecurityHelper.recordFailure(rateLimitKey);
      return 'Invalid credentials.';
    }

    final stored = f.passwordHash;
    bool ok = false;

    // 1. Hashed check (new format)
    if (SecurityHelper.verify(password.trim(), f.employeeId, stored)) {
      ok = true;
    }
    // 2. Legacy plain-text or default (employeeId == password stored as-is)
    else if (stored == password.trim() || stored == f.employeeId) {
      ok = true;
      // Migrate to hashed password silently
      final newHash = SecurityHelper.hashPassword(password.trim(), f.employeeId);
      await _db.updateFacultyPassword(f.id, newHash);
      f.passwordHash = newHash;
    }

    if (!ok) {
      SecurityHelper.recordFailure(rateLimitKey);
      return 'Invalid credentials.';
    }

    SecurityHelper.recordSuccess(rateLimitKey);
    _faculty = f;
    _role    = f.isAdmin ? UserRole.admin : UserRole.faculty;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('session_type', f.isAdmin ? 'admin' : 'faculty');
    await prefs.setString('session_id', f.id);
    // Pull latest data from cloud on login
    _syncFromCloud();
    notifyListeners();
    return null; // null = success
  }

  // ── Student login ──────────────────────────────────────────────────────────
  // Default password: roll number (e.g. 23CS501)
  // Recovery key:    roll number + 'K'  (e.g. 23CS501K) — resets to default
  Future<String?> loginStudent(String rollNumber, String password) async {
    final roll = rollNumber.trim().toUpperCase();
    final rateLimitKey = 'student:$roll';

    final blocked = SecurityHelper.checkRateLimit(rateLimitKey);
    if (blocked != null) return blocked;

    final s = await _db.getStudentByRollNumber(roll);
    if (s == null) {
      SecurityHelper.recordFailure(rateLimitKey);
      // Show sample of stored roll numbers to help diagnose format issues
      final samples = await _db.getSampleRollNumbers(limit: 3);
      if (samples.isEmpty) {
        return 'No students imported yet. Ask your admin to import student data.';
      }
      return 'Roll number not found. '
          'Examples of stored rolls: ${samples.join(", ")}. '
          'Check the format matches exactly.';
    }

    final pwd = password.trim();
    bool ok = false;

    // Recovery key: rollNumber + 'K' resets password back to default
    if (pwd.toUpperCase() == '${roll}K') {
      // Reset to default (plain roll number)
      final defaultHash = SecurityHelper.hashPassword(roll, roll);
      await _db.updateStudentPassword(s.id, defaultHash);
      s.passwordHash = defaultHash;
      ok = true;
    }
    // Hashed check (normal flow)
    else if (s.passwordHash.isNotEmpty &&
        SecurityHelper.verify(pwd, roll, s.passwordHash)) {
      ok = true;
    }
    // Empty hash or legacy: default password = roll number
    else if (s.passwordHash.isEmpty && (pwd == roll || pwd.toUpperCase() == roll)) {
      ok = true;
      // Set hash on first login
      final newHash = SecurityHelper.hashPassword(roll, roll);
      await _db.updateStudentPassword(s.id, newHash);
      s.passwordHash = newHash;
    }

    if (!ok) {
      SecurityHelper.recordFailure(rateLimitKey);
      return 'Invalid password.';
    }

    SecurityHelper.recordSuccess(rateLimitKey);
    _student = s;
    _role    = UserRole.student;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('session_type', 'student');
    await prefs.setString('session_id', s.id);
    // Pull latest data from cloud on login
    _syncFromCloud();
    notifyListeners();
    return null; // null = success
  }

  // ── Change password — Faculty/Admin ───────────────────────────────────────
  Future<String?> changeFacultyPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final f = _faculty;
    if (f == null) return 'Not logged in.';

    // Validate new password strength
    final err = SecurityHelper.validatePassword(newPassword);
    if (err != null) return err;

    // Verify current password
    final stored = f.passwordHash;
    final currentOk =
        SecurityHelper.verify(currentPassword.trim(), f.employeeId, stored) ||
        stored == currentPassword.trim() ||
        stored == f.employeeId;
    if (!currentOk) return 'Current password is incorrect.';

    if (newPassword.trim() == currentPassword.trim()) {
      return 'New password must differ from the current password.';
    }

    final newHash = SecurityHelper.hashPassword(newPassword.trim(), f.employeeId);
    await _db.updateFacultyPassword(f.id, newHash);
    _faculty!.passwordHash = newHash;
    // Sync password change to cloud
    SupabaseService().updatePassword('faculty', f.id, newHash);
    notifyListeners();
    return null;
  }

  // ── Change password — Student ──────────────────────────────────────────────
  Future<String?> changeStudentPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final s = _student;
    if (s == null) return 'Not logged in.';

    final roll = s.rollNumber.toUpperCase();

    final err = SecurityHelper.validatePassword(newPassword);
    if (err != null) return err;

    // Verify current password
    final stored = s.passwordHash;
    final currentOk =
        SecurityHelper.verify(currentPassword.trim(), roll, stored) ||
        (stored.isEmpty && currentPassword.trim().toUpperCase() == roll);
    if (!currentOk) return 'Current password is incorrect.';

    if (newPassword.trim() == currentPassword.trim()) {
      return 'New password must differ from the current password.';
    }

    final newHash = SecurityHelper.hashPassword(newPassword.trim(), roll);
    await _db.updateStudentPassword(s.id, newHash);
    _student!.passwordHash = newHash;
    // Sync password change to cloud
    SupabaseService().updatePassword('students', s.id, newHash);
    notifyListeners();
    return null;
  }

  // ── Restore session ────────────────────────────────────────────────────────
  Future<void> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final type  = prefs.getString('session_type');
      final id    = prefs.getString('session_id');
      if (type == null || id == null) return;

      if (type == 'admin' || type == 'faculty') {
        final f = await _db.getFacultyById(id);
        if (f != null) {
          _faculty = f;
          _role    = f.isAdmin ? UserRole.admin : UserRole.faculty;
        }
      } else if (type == 'student') {
        final rows = await _db.getAllStudents();
        final s = rows.cast<Student?>().firstWhere(
            (st) => st?.id == id, orElse: () => null);
        if (s != null) {
          _student = s;
          _role    = UserRole.student;
        }
      }
    } catch (_) {
      // Session restore failed (DB unavailable) — stay logged out
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  /// Pull cloud data into local SQLite in the background after login.
  void _syncFromCloud() {
    SupabaseService().pullAll().then((result) {
      if (result.synced) {
        // Notify listeners so dashboards reload with fresh data
        SchedulerBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
      }
    }).catchError((e) {
      debugPrint('Background sync error: $e');
    });
  }

  Future<void> logout() async {
    _role    = UserRole.none;
    _faculty = null;
    _student = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_type');
    await prefs.remove('session_id');
    notifyListeners();
  }
}
