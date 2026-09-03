// ═════════════════════════════════════════════════════════════════════════════
//  ArchiveAttendanceScreen
//  Accessible to: Class Incharge (their section only) + Admin (all sections)
//
//  Flow:
//   1. Shows attendance record count + estimated size for each section
//   2. Incharge sees only their own section(s)
//   3. Admin sees all sections
//   4. Tap "Export & Archive" → exports to Excel → confirms → deletes records
// ═════════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/excel_service.dart';
import '../../utils/app_theme.dart';

class ArchiveAttendanceScreen extends StatefulWidget {
  const ArchiveAttendanceScreen({super.key});
  @override
  State<ArchiveAttendanceScreen> createState() =>
      _ArchiveAttendanceScreenState();
}

class _ArchiveAttendanceScreenState extends State<ArchiveAttendanceScreen> {
  final _db    = DatabaseService();
  final _excel = ExcelService();

  bool   _loading  = true;
  bool   _isAdmin  = false;
  String _facultyId = '';

  // { 'A_3': {'section':'A','year':3,'records':12500,'est_bytes':3500000} }
  List<Map<String, dynamic>> _sections = [];
  final Set<String> _archiving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    _isAdmin   = auth.isAdmin;
    _facultyId = auth.faculty?.id ?? '';

    List<Map<String, dynamic>> summary =
        await _db.getAttendanceSummaryBySections();

    if (!_isAdmin) {
      // Only show sections where this faculty is class incharge
      final inchargeSections = await _db.getInchargeSections(_facultyId);
      final allowed = {
        for (final s in inchargeSections)
          '${s['section']}_${s['year']}': true
      };
      summary = summary
          .where((s) => allowed.containsKey('${s['section']}_${s['year']}'))
          .toList();
    }

    if (mounted) setState(() { _sections = summary; _loading = false; });
  }

  Future<void> _archive(String section, int year) async {
    final key = '${section}_$year';

    // Confirm
    final confirmed = await _showConfirmDialog(section, year);
    if (!confirmed) return;

    setState(() => _archiving.add(key));

    try {
      // 1. Fetch all records
      final records  = await _db.getAttendanceBySection(section, year);
      final students = await _db.getStudentsBySection(section, year);
      final subjects = await _db.getSubjectsBySection(section, year);

      final studentMap = {for (final s in students) s.id: s};
      final subjectMap = {for (final s in subjects) s.id: s.name};

      // 2. Build Excel
      final bytes = _buildExcel(records, studentMap, subjectMap, section, year);

      // 3. Save / download Excel
      final filename = 'Attendance_${section}_Yr${year}_Archive_'
          '${DateTime.now().year}.xlsx';
      await _excel.saveXlsxFile(filename, bytes);

      // 4. Delete from DB
      final deleted = await _db.deleteAttendanceBySection(section, year);

      // 5. Reload
      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppTheme.success,
          content: Text(
            'Archived $deleted records for Section $section Yr$year. '
            'Excel saved as $filename',
            style: const TextStyle(color: Colors.white)),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppTheme.error,
          content: Text('Archive failed: $e',
            style: const TextStyle(color: Colors.white)),
          behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _archiving.remove(key));
    }
  }

  Uint8List _buildExcel(
    List<AttendanceRecord> records,
    Map<String, Student> students,
    Map<String, String> subjects,
    String section, int year,
  ) {
    // Group by student → subject
    final perStudent = <String, Map<String, _SubAtt>>{};
    for (final r in records) {
      perStudent.putIfAbsent(r.studentId, () => {});
      perStudent[r.studentId]!.putIfAbsent(
          r.subjectId, () => _SubAtt());
      if (r.isPresent) {
        perStudent[r.studentId]![r.subjectId]!.present++;
      }
      perStudent[r.studentId]![r.subjectId]!.total++;
    }

    final subjectIds = subjects.keys.toList();
    final headers = [
      'Roll No', 'Name', 'Section', 'Year', 'Batch',
      ...subjectIds.map((id) => subjects[id] ?? id),
      'Overall %',
    ];

    final rows = <List<dynamic>>[];
    final sortedStudents = students.values.toList()
      ..sort((a, b) => a.rollNumber.compareTo(b.rollNumber));

    for (final s in sortedStudents) {
      final attMap = perStudent[s.id] ?? {};
      int totalPresent = 0, totalClasses = 0;
      final subCols = subjectIds.map((sid) {
        final a = attMap[sid];
        if (a == null) return '0/0 (0%)';
        totalPresent += a.present;
        totalClasses += a.total;
        final pct = a.total == 0 ? 0.0 : a.present / a.total * 100;
        return '${a.present}/${a.total} (${pct.toStringAsFixed(0)}%)';
      }).toList();
      final overall = totalClasses == 0
          ? '0%' : '${(totalPresent / totalClasses * 100).toStringAsFixed(1)}%';
      rows.add([s.rollNumber, s.name, s.section, s.year, s.batch,
                ...subCols, overall]);
    }

    return _excel.buildXlsx(
        sheetName: 'Sec $section Yr$year Archive',
        headers:   headers,
        rows:      rows);
  }

  Future<bool> _showConfirmDialog(String section, int year) async {
    final rec = _sections.firstWhere(
        (s) => s['section'] == section && s['year'] == year,
        orElse: () => {});
    final count = rec['records'] ?? 0;
    final mb    = ((rec['est_bytes'] ?? 0) as int) / (1024 * 1024);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.border)),
        title: const Text('Archive Attendance',
          style: TextStyle(color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          _InfoRow('Section', 'Section $section — Year $year'),
          _InfoRow('Records', '$count attendance records'),
          _InfoRow('Space freed', '~${mb.toStringAsFixed(1)} MB'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.amber.withOpacity(0.3))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              const Icon(Icons.warning_amber_rounded,
                color: AppTheme.amber, size: 16),
              const SizedBox(width: 8),
              const Expanded(child: Text(
                'The Excel file will be saved/downloaded BEFORE deletion. '
                'This action cannot be undone.',
                style: TextStyle(color: AppTheme.textSecondary,
                  fontSize: 11.5, height: 1.4))),
            ])),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
              style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Export & Delete')),
        ]));
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.sidebar,
        foregroundColor: AppTheme.textPrimary,
        title: const Text('Archive Attendance',
          style: TextStyle(
            color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.border)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sections.isEmpty
              ? _emptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _headerCard(),
                    const SizedBox(height: 14),
                    ..._sections.map(_sectionCard),
                  ]),
    );
  }

  Widget _headerCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.primary.withOpacity(0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.primary.withOpacity(0.2))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline_rounded,
        color: AppTheme.primaryLt, size: 16),
      const SizedBox(width: 10),
      const Expanded(child: Text(
        'Archiving exports attendance to Excel then deletes it from the '
        'device database — freeing storage. Do this at the end of each '
        'academic year. Exported files are saved to your Downloads folder.',
        style: TextStyle(color: AppTheme.textSecondary,
          fontSize: 11.5, height: 1.5))),
    ]));

  Widget _sectionCard(Map<String, dynamic> s) {
    final section  = s['section'] as String;
    final year     = s['year'] as int;
    final records  = (s['records'] as int?) ?? 0;
    final bytes    = (s['est_bytes'] as int?) ?? 0;
    final mb       = bytes / (1024 * 1024);
    final key      = '${section}_$year';
    final busy     = _archiving.contains(key);

    Color sizeColor = AppTheme.emerald;
    if (mb > 300) sizeColor = AppTheme.error;
    else if (mb > 100) sizeColor = AppTheme.amber;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border)),
      child: Row(children: [
        // Section badge
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            gradient: AppTheme.purpleGradient,
            borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(section,
            style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 18)))),
        const SizedBox(width: 12),
        // Info
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Section $section — Year $year',
            style: const TextStyle(color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.format_list_numbered_rounded,
              color: AppTheme.textMuted, size: 12),
            const SizedBox(width: 4),
            Text('${_fmt(records)} records',
              style: const TextStyle(color: AppTheme.textSecondary,
                fontSize: 11)),
            const SizedBox(width: 12),
            Icon(Icons.storage_rounded, color: sizeColor, size: 12),
            const SizedBox(width: 4),
            Text('~${mb.toStringAsFixed(0)} MB',
              style: TextStyle(color: sizeColor,
                fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ])),
        // Archive button
        busy
            ? const SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error.withOpacity(0.12),
                  foregroundColor: AppTheme.error,
                  elevation: 0,
                  side: BorderSide(
                    color: AppTheme.error.withOpacity(0.3)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8)),
                onPressed: () => _archive(section, year),
                icon: const Icon(Icons.archive_outlined, size: 14),
                label: const Text('Archive',
                  style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700))),
      ]));
  }

  Widget _emptyState() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 64, height: 64,
      decoration: BoxDecoration(
        color: AppTheme.emerald.withOpacity(0.1),
        shape: BoxShape.circle),
      child: const Icon(Icons.check_circle_outline_rounded,
        color: AppTheme.emerald, size: 30)),
    const SizedBox(height: 16),
    const Text('No attendance data to archive',
      style: TextStyle(color: AppTheme.textPrimary,
        fontWeight: FontWeight.w700, fontSize: 15)),
    const SizedBox(height: 6),
    const Text('Your database is clean and lean 🎉',
      style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
  ]));

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }
}

class _SubAtt {
  int present = 0, total = 0;
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label,
        style: const TextStyle(color: AppTheme.textMuted,
          fontSize: 11.5, fontWeight: FontWeight.w600))),
      Expanded(child: Text(value,
        style: const TextStyle(color: AppTheme.textPrimary,
          fontSize: 11.5))),
    ]));
}
