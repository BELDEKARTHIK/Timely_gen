// ══════════════════════════════════════════════════════════════════════════════
//  DataManagementScreen — Admin's complete data control panel
//
//  Sections:
//   1. Storage Overview   — DB size per section, total
//   2. Archive Attendance — export + delete per section
//   3. Danger Zone        — clear timetable / reset all data
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/excel_service.dart';
import '../../models/models.dart';
import '../../utils/app_theme.dart';
import '../faculty/archive_screen.dart';

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});
  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  final _db    = DatabaseService();
  final _excel = ExcelService();
  bool _loading = true;

  int    _totalRecords  = 0;
  int    _totalEstBytes = 0;
  List<Map<String, dynamic>> _sections = [];

  // Archive busy set
  final Set<String> _archiving = {};
  bool _clearingAtt  = false;
  bool _clearingTT   = false;
  bool _resettingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final summary = await _db.getAttendanceSummaryBySections();
    int totalRec = 0, totalBytes = 0;
    for (final s in summary) {
      totalRec   += (s['records']   as int? ?? 0);
      totalBytes += (s['est_bytes'] as int? ?? 0);
    }
    setState(() {
      _sections      = summary;
      _totalRecords  = totalRec;
      _totalEstBytes = totalBytes;
      _loading       = false;
    });
  }

  // ── Archive one section ───────────────────────────────────────────────────
  Future<void> _archiveSection(String section, int year) async {
    final key = '${section}_$year';
    final rec = _sections.firstWhere(
        (s) => s['section'] == section && s['year'] == year,
        orElse: () => {});
    final count = rec['records'] as int? ?? 0;
    final mb    = ((rec['est_bytes'] as int? ?? 0)) / (1024 * 1024);

    final ok = await _confirm(
      title: 'Archive Section $section — Year $year',
      body:  '$count records (~${mb.toStringAsFixed(0)} MB) will be exported '
             'to Excel then deleted from the database.',
      action: 'Export & Delete',
      color:  AppTheme.error,
    );
    if (!ok) return;

    setState(() => _archiving.add(key));
    try {
      final records  = await _db.getAttendanceBySection(section, year);
      final students = await _db.getStudentsBySection(section, year);
      final subjects = await _db.getSubjectsBySection(section, year);
      final bytes    = _buildExcel(records,
          {for (final s in students) s.id: s},
          {for (final s in subjects) s.id: s.name},
          section, year);
      final fname = 'Attendance_${section}_Yr${year}_'
          '${DateTime.now().year}.xlsx';
      await _excel.saveXlsxFile(fname, bytes);
      final deleted = await _db.deleteAttendanceBySection(section, year);
      await _load();
      _snack('Archived $deleted records for $section Yr$year → $fname',
          AppTheme.success);
    } catch (e) {
      _snack('Archive failed: $e', AppTheme.error);
    } finally {
      setState(() => _archiving.remove(key));
    }
  }

  // ── Clear ALL attendance ──────────────────────────────────────────────────
  Future<void> _clearAllAttendance() async {
    final ok = await _confirm(
      title:  'Clear ALL Attendance',
      body:   '$_totalRecords records across ${_sections.length} sections '
              'will be permanently deleted.\n\n'
              'Export each section first from the table below.',
      action: 'Delete All Attendance',
      color:  AppTheme.error,
    );
    if (!ok) return;
    setState(() => _clearingAtt = true);
    await _db.deleteAllAttendance();
    await _load();
    setState(() => _clearingAtt = false);
    _snack('All attendance records cleared', AppTheme.success);
  }

  // ── Clear timetable ───────────────────────────────────────────────────────
  Future<void> _clearTimetable() async {
    final ok = await _confirm(
      title:  'Clear Timetable',
      body:   'All timetable entries and special slots will be deleted. '
              'Faculty, students and subjects are kept. '
              'You can regenerate the timetable after.',
      action: 'Clear Timetable',
      color:  AppTheme.amber,
    );
    if (!ok) return;
    setState(() => _clearingTT = true);
    await _db.clearAllTimetables();
    await _db.clearAllSpecialSlots();
    setState(() => _clearingTT = false);
    _snack('Timetable cleared. You can regenerate from Generate tab.',
        AppTheme.success);
  }

  // ── Reset ALL data ────────────────────────────────────────────────────────
  Future<void> _resetAll() async {
    // Double confirm for destructive action
    final ok1 = await _confirm(
      title:  'Reset ALL Data',
      body:   'This will delete ALL:\n'
              '• Timetable entries\n'
              '• All attendance records\n'
              '• All subjects\n'
              '• All students\n'
              '• All faculty (except Admin)\n\n'
              'The admin account is preserved.',
      action: 'Yes, Reset Everything',
      color:  AppTheme.error,
    );
    if (!ok1) return;
    final ok2 = await _confirm(
      title:  'Are you absolutely sure?',
      body:   'This cannot be undone. All college data will be erased.',
      action: 'RESET ALL DATA',
      color:  AppTheme.error,
    );
    if (!ok2) return;
    setState(() => _resettingAll = true);
    await _db.resetAllData();
    await _load();
    setState(() => _resettingAll = false);
    _snack('All data reset. Import fresh data to start again.',
        AppTheme.success);
  }

  // ── Build Excel bytes ─────────────────────────────────────────────────────
  Uint8List _buildExcel(
    List<AttendanceRecord> records,
    Map<String, Student> students,
    Map<String, String> subjects,
    String section, int year,
  ) {
    final perStudent = <String, Map<String, _SA>>{};
    for (final r in records) {
      perStudent.putIfAbsent(r.studentId, () => {});
      perStudent[r.studentId]!.putIfAbsent(r.subjectId, () => _SA());
      if (r.isPresent) perStudent[r.studentId]![r.subjectId]!.p++;
      perStudent[r.studentId]![r.subjectId]!.t++;
    }
    final subIds = subjects.keys.toList();
    final headers = ['Roll No', 'Name', ...subIds.map((id) => subjects[id] ?? id), 'Overall %'];
    final sortedStudents = students.values.toList()
      ..sort((a, b) => a.rollNumber.compareTo(b.rollNumber));
    final rows = sortedStudents.map((s) {
      int tp = 0, tt = 0;
      final cols = subIds.map((sid) {
        final a = perStudent[s.id]?[sid];
        if (a == null) return '0/0';
        tp += a.p; tt += a.t;
        return '${a.p}/${a.t} (${a.t == 0 ? 0 : (a.p / a.t * 100).round()}%)';
      }).toList();
      return [s.rollNumber, s.name, ...cols,
          tt == 0 ? '0%' : '${(tp / tt * 100).toStringAsFixed(1)}%'];
    }).toList();
    return _excel.buildXlsx(
        sheetName: 'Sec $section Yr$year',
        headers:   headers,
        rows:      rows);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Future<bool> _confirm({
    required String title, required String body,
    required String action, required Color color,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.border)),
        title: Text(title, style: const TextStyle(
          color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
        content: Text(body, style: const TextStyle(
          color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
              style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action)),
        ]));
    return r ?? false;
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4)));
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n/1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n/1000).toStringAsFixed(0)}K';
    return '$n';
  }

  String _fmtMb(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb < 1) return '< 1 MB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  Color _sizeColor(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb > 300) return AppTheme.error;
    if (mb > 100) return AppTheme.amber;
    return AppTheme.emerald;
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final totalMb = _totalEstBytes / (1024 * 1024);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 1. STORAGE OVERVIEW ─────────────────────────────────────────────
        _sectionHeader(Icons.storage_rounded, 'Storage Overview', AppTheme.primary),
        const SizedBox(height: 10),
        _overviewCard(totalMb),
        const SizedBox(height: 20),

        // ── 2. ARCHIVE ATTENDANCE ────────────────────────────────────────────
        _sectionHeader(Icons.archive_outlined, 'Archive Attendance by Section',
            AppTheme.amber),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppTheme.amber.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.amber.withOpacity(0.25))),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded, color: AppTheme.amber, size: 14),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Export attendance to Excel, then delete from database. '
              'Do this at the end of each academic year to free storage.',
              style: TextStyle(color: AppTheme.textSecondary,
                fontSize: 11.5, height: 1.4))),
          ])),
        if (_sections.isEmpty)
          _emptyAttCard()
        else
          ..._sections.map(_sectionRow),
        const SizedBox(height: 20),

        // ── 3. DANGER ZONE ───────────────────────────────────────────────────
        _sectionHeader(Icons.warning_amber_rounded, 'Danger Zone', AppTheme.error),
        const SizedBox(height: 10),
        _dangerCard(),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _sectionHeader(IconData icon, String title, Color color) =>
      Row(children: [
        Container(width: 28, height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 14)),
        const SizedBox(width: 10),
        Text(title, style: TextStyle(
          color: color, fontSize: 13,
          fontWeight: FontWeight.w800)),
      ]);

  Widget _overviewCard(double totalMb) {
    final statusColor = totalMb > 300 ? AppTheme.error
        : totalMb > 100 ? AppTheme.amber : AppTheme.emerald;
    final statusText  = totalMb > 300 ? 'Archive old sections soon'
        : totalMb > 100 ? 'Consider archiving'
        : 'Storage healthy';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border)),
      child: Column(children: [
        Row(children: [
          Expanded(child: _statBox('Total Records',
              _fmt(_totalRecords), AppTheme.primary)),
          const SizedBox(width: 12),
          Expanded(child: _statBox('Est. DB Size',
              _fmtMb(_totalEstBytes), statusColor)),
          const SizedBox(width: 12),
          Expanded(child: _statBox('Sections',
              '${_sections.length}', AppTheme.emerald)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (totalMb / 500).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppTheme.cardAlt,
            valueColor: AlwaysStoppedAnimation(statusColor))),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(statusText, style: TextStyle(
            color: statusColor, fontSize: 11.5,
            fontWeight: FontWeight.w600)),
          Text('${totalMb.toStringAsFixed(0)} / 500 MB guide',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ]),
      ]));
  }

  Widget _statBox(String label, String value, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(value, style: TextStyle(
            color: color, fontSize: 20,
            fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(
            color: AppTheme.textMuted, fontSize: 10.5),
            textAlign: TextAlign.center),
        ]));

  Widget _emptyAttCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.border)),
    child: Row(children: [
      const Icon(Icons.check_circle_outline_rounded,
        color: AppTheme.emerald, size: 20),
      const SizedBox(width: 10),
      const Text('No attendance data found — database is clean!',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
    ]));

  Widget _sectionRow(Map<String, dynamic> s) {
    final section = s['section'] as String;
    final year    = s['year'] as int;
    final records = (s['records'] as int?) ?? 0;
    final bytes   = (s['est_bytes'] as int?) ?? 0;
    final key     = '${section}_$year';
    final busy    = _archiving.contains(key);
    final col     = _sizeColor(bytes);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border)),
      child: Row(children: [
        Container(width: 38, height: 38,
          decoration: BoxDecoration(
            gradient: AppTheme.purpleGradient,
            borderRadius: BorderRadius.circular(9)),
          child: Center(child: Text(section,
            style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 15)))),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Section $section — Year $year',
            style: const TextStyle(color: AppTheme.textPrimary,
              fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Row(children: [
            Text('${_fmt(records)} records',
              style: const TextStyle(
                color: AppTheme.textMuted, fontSize: 11)),
            const SizedBox(width: 10),
            Text(_fmtMb(bytes),
              style: TextStyle(color: col,
                fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ])),
        busy
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  backgroundColor: AppTheme.error.withOpacity(0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: AppTheme.error.withOpacity(0.25))),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6)),
                onPressed: () => _archiveSection(section, year),
                icon: const Icon(Icons.download_outlined, size: 13),
                label: const Text('Archive',
                  style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700))),
      ]));
  }

  Widget _dangerCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.error.withOpacity(0.25))),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Clear All Attendance
        _dangerRow(
          icon:    Icons.delete_sweep_rounded,
          title:   'Clear ALL Attendance',
          sub:     'Delete all ${_fmt(_totalRecords)} attendance records across '
                   'all sections. Export each section first.',
          color:   AppTheme.error,
          label:   'Clear Attendance',
          loading: _clearingAtt,
          onTap:   _clearAllAttendance,
        ),
        const Divider(color: AppTheme.border, height: 24),
        // Clear Timetable
        _dangerRow(
          icon:    Icons.grid_off_rounded,
          title:   'Clear Timetable',
          sub:     'Remove all timetable entries and special slots. '
                   'Faculty, students and subjects are kept.',
          color:   AppTheme.amber,
          label:   'Clear Timetable',
          loading: _clearingTT,
          onTap:   _clearTimetable,
        ),
        const Divider(color: AppTheme.border, height: 24),
        // Reset All
        _dangerRow(
          icon:    Icons.restore_rounded,
          title:   'Reset ALL Data',
          sub:     'Wipe everything — timetable, attendance, subjects, '
                   'students, all faculty except Admin.',
          color:   AppTheme.error,
          label:   'Reset Everything',
          loading: _resettingAll,
          onTap:   _resetAll,
          bold:    true,
        ),
      ]));

  Widget _dangerRow({
    required IconData icon,
    required String title, required String sub,
    required Color color, required String label,
    required bool loading, required VoidCallback onTap,
    bool bold = false,
  }) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 36, height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(9)),
      child: Icon(icon, color: color, size: 17)),
    const SizedBox(width: 12),
    Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(
        color: bold ? AppTheme.error : AppTheme.textPrimary,
        fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text(sub, style: const TextStyle(
        color: AppTheme.textMuted, fontSize: 11, height: 1.4)),
    ])),
    const SizedBox(width: 10),
    loading
        ? SizedBox(width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: color))
        : ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color.withOpacity(0.12),
              foregroundColor: color,
              elevation: 0,
              side: BorderSide(color: color.withOpacity(0.30)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 8)),
            onPressed: onTap,
            child: Text(label,
              style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700))),
  ]);
}

class _SA { int p = 0, t = 0; }
