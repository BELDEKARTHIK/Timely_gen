import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/database_service.dart';
import 'utils/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/faculty/faculty_dashboard.dart';
import 'screens/student/student_dashboard.dart';
import 'services/db_init.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise database factory for the current platform
  await DbInit.init();

  // Initialise Supabase cloud sync
  await SupabaseService().init();

  // Pre-warm the database — on web this loads sqlite3.wasm + sqflite_sw.js
  // If those files are missing, we show a helpful error instead of a blank screen.
  String? dbError;
  try {
    await DatabaseService().db;
  } catch (e) {
    dbError = e.toString();
    debugPrint('DB pre-warm error: $e');
  }

  // Notifications — mobile/desktop only
  if (!kIsWeb) {
    try {
      final notifService = NotificationService();
      await notifService.init();
      await notifService.requestPermissions();
    } catch (_) {}
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthService()..restoreSession(),
      child: TimetableApp(dbError: dbError),
    ),
  );
}

class TimetableApp extends StatelessWidget {
  final String? dbError;
  const TimetableApp({super.key, this.dbError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TimetableOS',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(accessibleNavigation: false),
        child: child!,
      ),
      home: _AppShell(dbError: dbError),
    );
  }
}

class _AppShell extends StatefulWidget {
  final String? dbError;
  const _AppShell({this.dbError});
  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Skip waiting frames if DB already failed — show error immediately
    if (widget.dbError != null) {
      _ready = false; // stays false so we show error splash
      return;
    }
    _waitFrames(3);
  }

  void _waitFrames(int n) {
    if (n <= 0) {
      if (mounted) setState(() => _ready = true);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _waitFrames(n - 1));
  }

  @override
  Widget build(BuildContext context) {
    // ── DB error — show setup instructions ──────────────────────────────────
    if (widget.dbError != null) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    gradient: AppTheme.purpleGradient,
                    borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.school_rounded,
                      color: Colors.white, size: 30)),
                const SizedBox(height: 20),
                const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFF39C12), size: 36),
                const SizedBox(height: 12),
                const Text('Web Database Setup Required',
                  style: TextStyle(color: Colors.white,
                    fontSize: 18, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text(
                  'The SQLite web worker files are missing.\n'
                  'Run this command ONCE in your project folder:',
                  style: TextStyle(color: Color(0xFF8888AA), fontSize: 13),
                  textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF6C63FF))),
                  child: const SelectableText(
                    'dart run sqflite_common_ffi_web:setup',
                    style: TextStyle(
                      color: Color(0xFFA8D8FF),
                      fontSize: 14,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center)),
                const SizedBox(height: 12),
                const Text('Then restart with: flutter run -d chrome',
                  style: TextStyle(
                    color: Color(0xFF6C63FF), fontSize: 13)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2E),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    widget.dbError!.length > 120
                        ? '${widget.dbError!.substring(0, 120)}…'
                        : widget.dbError!,
                    style: const TextStyle(
                      color: Color(0xFF666688), fontSize: 11,
                      fontFamily: 'monospace'),
                    textAlign: TextAlign.center)),
              ],
            ),
          ),
        ),
      );
    }

    // ── Splash / loading ─────────────────────────────────────────────────────
    if (!_ready) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  gradient: AppTheme.purpleGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                    color: AppTheme.purple.withOpacity(0.4),
                    blurRadius: 20, offset: const Offset(0, 8))]),
                child: const Icon(Icons.school_rounded,
                    color: Colors.white, size: 28)),
              const SizedBox(height: 20),
              const SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(
                    color: AppTheme.purple, strokeWidth: 2)),
              const SizedBox(height: 12),
              const Text('Loading database...',
                style: TextStyle(
                  color: Color(0xFF8888AA), fontSize: 12)),
            ],
          ),
        ),
      );
    }

    // ── Route to correct dashboard ───────────────────────────────────────────
    final auth = context.watch<AuthService>();
    if (!auth.isLoggedIn) return const LoginScreen();

    switch (auth.role) {
      case UserRole.admin:   return const AdminDashboard();
      case UserRole.faculty: return const FacultyDashboard();
      case UserRole.student: return const StudentDashboard();
      default:               return const LoginScreen();
    }
  }
}
