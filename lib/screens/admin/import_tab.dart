import 'package:flutter/material.dart';
import '../../services/database_service.dart';
import '../../services/supabase_service.dart';
import '../../services/excel_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/responsive.dart';
import '../../widgets/dash_card.dart';

class ImportTab extends StatefulWidget {
  const ImportTab({super.key});
  @override State<ImportTab> createState() => ImportTabState();
}


class ImportTabState extends State<ImportTab> {
  final _db    = DatabaseService();
  final _excel = ExcelService();
  bool   _loading      = false;
  String _status       = '';
  bool   _statusOk     = true;
  bool   _dlLoading    = false;
  String _dlStatus     = '';
  bool   _dlStatusOk   = true;

  // ── Data counts ──────────────────────────────────────────────────────────
  int  _facultyCount   = 0;
  int  _subjectCount   = 0;
  int  _studentCount   = 0;
  int  _timetableCount = 0;
  bool _deleting       = false;

  void _set(String msg, {bool ok = true}) =>
    setState(() { _status = msg; _statusOk = ok; _loading = false; });

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  /// Called by parent when this tab becomes active
  void refresh() => _loadCounts();

  Future<void> _loadCounts() async {
    final fac  = await _db.getAllFaculty();
    final subs = await _db.getAllSubjects();
    final stus = await _db.getAllStudents();
    final tt   = await _db.getTimetableCount();
    if (!mounted) return;
    setState(() {
      _facultyCount   = fac.where((f) => !f.isAdmin).length;
      _subjectCount   = subs.length;
      _studentCount   = stus.length;
      _timetableCount = tt;
    });
  }

  Future<void> _clearFacultySubjects() async {
    final ttNote = _timetableCount > 0
        ? '\n\n⚠ A timetable with $_timetableCount slots exists. '
          'You should also delete it from the Generate tab before re-generating.'
        : '';
    final confirmed = await _confirm(
      'Clear Faculty & Subjects?',
      'This will delete:\n'
      '• $_facultyCount faculty members\n'
      '• $_subjectCount subjects\n\n'
      'Timetable and attendance records will NOT be deleted.$ttNote\n\n'
      'You can re-import fresh data immediately after.');
    if (!confirmed) return;
    setState(() => _deleting = true);
    await _db.deleteAllSubjects();
    await _db.deleteAllFaculty();
    await _loadCounts();
    if (!mounted) return;
    setState(() => _deleting = false);
    _set('✅ Faculty and subjects cleared. Re-import new data, then regenerate the timetable.');
  }

  Future<void> _clearStudents() async {
    final confirmed = await _confirm(
      'Clear Students?',
      'This will delete:\n'
      '• $_studentCount students\n\n'
      'Attendance records will NOT be deleted.\n'
      'You can re-import fresh data immediately after.');
    if (!confirmed) return;
    setState(() => _deleting = true);
    await _db.deleteAllStudents();
    await _loadCounts();
    if (!mounted) return;
    setState(() => _deleting = false);
    _set('✅ Students cleared. Re-import new student data.');
  }

  Future<bool> _confirm(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border)),
        title: Text(title, style: const TextStyle(
          color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(body, style: const TextStyle(
          color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
              style: TextStyle(color: AppTheme.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
              style: TextStyle(color: AppTheme.rose,
                fontWeight: FontWeight.w700))),
        ]));
    return result ?? false;
  }

  Future<void> _downloadTemplate(String type) async {
    setState(() { _dlLoading = true; _dlStatus = ''; });
    try {
      final path = type == 'faculty'
          ? await _excel.downloadFacultyTemplate()
          : await _excel.downloadStudentTemplate();
      if (path != null) {
        setState(() {
          _dlLoading = false;
          _dlStatus  = '✅ Saved: $path';
          _dlStatusOk = true;
        });
      } else {
        setState(() {
          _dlLoading  = false;
          _dlStatus   = '❌ Download failed.';
          _dlStatusOk = false;
        });
      }
    } catch (e) {
      setState(() {
        _dlLoading  = false;
        _dlStatus   = '❌ $e';
        _dlStatusOk = false;
      });
    }
  }

  Future<void> _import(String type) async {
    setState(() { _loading = true; _status = 'Opening file picker…'; });
    try {
      final file = await _excel.pickAndLoadExcel();
      if (file == null) { _set('No file selected.', ok: false); return; }
      final sheet = await _pickSheet(file.sheetNames);
      if (sheet == null) { _set('Cancelled.', ok: false); return; }
      setState(() => _status = 'Importing "$sheet"…');
      if (type == 'faculty') {
        final rows = _excel.parseFacultySheet(file, sheet);
        if (rows.isEmpty) { _set('No data found. Check headers.', ok: false); return; }
        final data = _excel.convertFacultyRows(rows);
        await _db.insertManyFaculty(data.faculty);
        await _db.insertManySubjects(data.subjects);
        _set('✅ ${data.faculty.length} faculty, ${data.subjects.length} subjects imported!');
        SupabaseService().pushAll(); // sync to cloud
        _loadCounts();
      } else {
        final students = _excel.parseStudentSheet(file, sheet);
        if (students.isEmpty) { _set('No students found.', ok: false); return; }
        await _db.insertManyStudents(students);
        _set('✅ ${students.length} students imported!');
        SupabaseService().pushAll(); // sync to cloud
        _loadCounts();
      }
    } catch (e) {
      _set('❌ ${e.toString().replaceAll("Exception: ", "")}', ok: false);
    }
  }

  Future<String?> _pickSheet(List<String> sheets) async {
    if (sheets.length == 1) return sheets.first;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.border)),
        title: const Text('Select Sheet', style: TextStyle(
            color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: sheets.map((s) => ListTile(
            leading: Container(width: 32, height: 32,
              decoration: BoxDecoration(gradient: AppTheme.purpleGradient,
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.table_chart_rounded, color: Colors.white, size: 16)),
            title: Text(s, style: const TextStyle(color: AppTheme.textPrimary)),
            onTap: () => Navigator.pop(ctx, s))).toList()),
        actions: [TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'))]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = R.isMobile(context) ? 14.0 : 28.0;
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: 'Import Data'),
        const SizedBox(height: 6),
        const Text('Upload Excel files to populate faculty, subjects and students',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 20),

        // ── Step 1: Download Templates ─────────────────────────────────
        InfoCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 32, height: 32,
              decoration: BoxDecoration(
                gradient: AppTheme.cyanGradient,
                borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.download_rounded, color: Colors.white, size: 16)),
            const SizedBox(width: 12),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Step 1 — Download Templates', style: TextStyle(
                  color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                Text('Download, fill in your data, then upload below.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              ])),
          ]),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (ctx, box) {
            final isMob = box.maxWidth < 460;
            final btnA = _TemplateBtn(
              label: 'Faculty & Subjects Template',
              icon: Icons.people_alt_rounded,
              gradient: AppTheme.purpleGradient,
              loading: _dlLoading,
              onTap: _dlLoading ? null : () => _downloadTemplate('faculty'));
            final btnB = _TemplateBtn(
              label: 'Students Template',
              icon: Icons.school_rounded,
              gradient: AppTheme.orangeGradient,
              loading: _dlLoading,
              onTap: _dlLoading ? null : () => _downloadTemplate('student'));
            if (isMob) return Column(children: [btnA, const SizedBox(height: 8), btnB]);
            return Row(children: [
              Expanded(child: btnA),
              const SizedBox(width: 10),
              Expanded(child: btnB),
            ]);
          }),
          if (_dlLoading) ...[
            const SizedBox(height: 10),
            Row(children: [
              const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryLt)),
              const SizedBox(width: 10),
              const Text('Generating template…',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ]),
          ] else if (_dlStatus.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _dlStatusOk
                    ? AppTheme.success.withOpacity(0.08)
                    : AppTheme.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: (_dlStatusOk
                    ? AppTheme.success : AppTheme.error).withOpacity(0.25))),
              child: Row(children: [
                Icon(_dlStatusOk ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                  color: _dlStatusOk ? AppTheme.success : AppTheme.error, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(_dlStatus, style: TextStyle(
                  color: _dlStatusOk ? AppTheme.success : AppTheme.error,
                  fontSize: 11.5, fontWeight: FontWeight.w600))),
              ])),
          ],
        ])),
        const SizedBox(height: 16),

        // ── Step 2: Upload ─────────────────────────────────────────────
        InfoCard(child: Row(children: [
          Container(width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: AppTheme.purpleGradient,
              borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.upload_file_rounded, color: Colors.white, size: 16)),
          const SizedBox(width: 12),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Step 2 — Upload Filled Templates', style: TextStyle(
              color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
            Text('Select your completed .xlsx file to import.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ]),
        ])),
        const SizedBox(height: 14),

        // Import cards — side by side on desktop, stacked on mobile
        LayoutBuilder(builder: (ctx, box) {
          final isMob = box.maxWidth < 500;
          final cardA = _ImportCard(
            icon: Icons.people_alt_rounded,
            title: 'Faculty & Subjects',
            subtitle: 'faculty_subjects.xlsx',
            description: 'Imports faculty members, their subjects, sections, and scheduling preferences.',
            gradient: AppTheme.purpleGradient,
            loading: _loading,
            onTap: _loading ? null : () => _import('faculty'));
          final cardB = _ImportCard(
            icon: Icons.school_rounded,
            title: 'Students',
            subtitle: 'students_data.xlsx',
            description: 'Imports student roll numbers, names, sections, years, and batch assignments.',
            gradient: AppTheme.orangeGradient,
            loading: _loading,
            onTap: _loading ? null : () => _import('student'));
          if (isMob) {
            return Column(children: [cardA, const SizedBox(height: 14), cardB]);
          }
          return Row(children: [
            Expanded(child: cardA),
            const SizedBox(width: 16),
            Expanded(child: cardB),
          ]);
        }),

        const SizedBox(height: 20),

        // ── Step 3: Manage / Clear Data ───────────────────────────────────
        InfoCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 32, height: 32,
              decoration: BoxDecoration(
                gradient: AppTheme.orangeGradient,
                borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.manage_accounts_rounded,
                color: Colors.white, size: 16)),
            const SizedBox(width: 12),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Step 3 — Manage Imported Data',
                  style: TextStyle(color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700, fontSize: 13)),
                Text('Clear existing data to re-import fresh records.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              ])),
          ]),
          const SizedBox(height: 14),

          // Timetable status note
          if (_timetableCount > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.amber.withOpacity(0.07),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppTheme.amber.withOpacity(0.25))),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                  color: AppTheme.amber, size: 14),
                const SizedBox(width: 9),
                Expanded(child: Text(
                  'A timetable with $_timetableCount slots is already generated. '
                  'Delete it from the Generate tab before re-importing and regenerating.',
                  style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11, height: 1.4))),
              ])),

          // Faculty & subjects card
          _DataSummaryCard(
            icon: Icons.people_alt_rounded,
            gradient: AppTheme.purpleGradient,
            title: 'Faculty & Subjects',
            counts: '$_facultyCount faculty  •  $_subjectCount subjects',
            hasData: _facultyCount > 0 || _subjectCount > 0,
            deleting: _deleting,
            onClear: _deleting ? null : _clearFacultySubjects),
          const SizedBox(height: 10),

          // Students card
          _DataSummaryCard(
            icon: Icons.school_rounded,
            gradient: AppTheme.orangeGradient,
            title: 'Students',
            counts: '$_studentCount students',
            hasData: _studentCount > 0,
            deleting: _deleting,
            onClear: _deleting ? null : _clearStudents),
        ])),

        const SizedBox(height: 20),

        // Status
        if (_loading)
          InfoCard(child: Row(children: [
            const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryLt)),
            const SizedBox(width: 16),
            Text(_status, style: const TextStyle(color: AppTheme.textSecondary)),
          ]))
        else if (_status.isNotEmpty)
          InfoCard(child: Row(children: [
            Container(width: 36, height: 36,
              decoration: BoxDecoration(
                color: (_statusOk ? AppTheme.success : AppTheme.error).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
              child: Icon(_statusOk ? Icons.check_rounded : Icons.close_rounded,
                color: _statusOk ? AppTheme.success : AppTheme.error, size: 20)),
            const SizedBox(width: 14),
            Expanded(child: Text(_status, style: TextStyle(
              color: _statusOk ? AppTheme.success : AppTheme.error,
              fontWeight: FontWeight.w600, fontSize: 13))),
          ])),

        const SizedBox(height: 24),

        // Column headers reference
        InfoCard(child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: Container(width: 32, height: 32,
              decoration: BoxDecoration(gradient: AppTheme.cyanGradient,
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.table_rows_rounded, color: Colors.white, size: 15)),
            title: const Text('Required Column Headers',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
            iconColor: AppTheme.textSecondary,
            collapsedIconColor: AppTheme.textSecondary,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Divider(color: AppTheme.border),
                  const SizedBox(height: 10),
                  _colSection('Faculty Sheet', ['Employee ID','Faculty Name',
                    'Subject','Section','Year','Type','Periods Per Week',
                    'Is Incharge','Batch','Email','Preference',
                    'Lab Divided Into 2 Batches']),
                  const SizedBox(height: 10),
                  // Employee ID explanation
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.emerald.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.emerald.withOpacity(0.22))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.badge_rounded,
                            color: AppTheme.emerald, size: 12),
                          const SizedBox(width: 6),
                          const Text('Employee ID column — unique faculty key',
                            style: TextStyle(color: AppTheme.emerald,
                              fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 5),
                        const Text(
                          'Each faculty must have a stable Employee ID (e.g. TCH001). '
                          'This prevents duplicates when the same faculty teaches '
                          'multiple subjects — even if the name is spelled differently '
                          'across rows. Faculty login: Employee ID as both username '
                          'and default password.',
                          style: TextStyle(color: AppTheme.textSecondary,
                            fontSize: 10.5, height: 1.4)),
                      ])),
                  const SizedBox(height: 10),
                  // Preference column explanation
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.amber.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.amber.withOpacity(0.25))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.calendar_today_rounded,
                            color: AppTheme.amber, size: 12),
                          const SizedBox(width: 6),
                          const Text('Preference column — NPTEL / Sports day',
                            style: TextStyle(color: AppTheme.amber,
                              fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 5),
                        const Text(
                          'Set the weekday when P5–P7 (1:30–4:00 PM) are reserved '
                          'for NPTEL/Mentoring + Sports for that section. '
                          'All rows of the same Section + Year must use the same day.',
                          style: TextStyle(color: AppTheme.textSecondary,
                            fontSize: 10.5, height: 1.4)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 4,
                          children: ['Monday','Tuesday','Wednesday',
                                     'Thursday','Friday','Saturday']
                            .map((d) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: AppTheme.primary.withOpacity(0.28))),
                              child: Text(d, style: const TextStyle(
                                color: AppTheme.primaryLt,
                                fontSize: 9.5, fontWeight: FontWeight.w600))))
                            .toList()),
                        const SizedBox(height: 5),
                        const Text('Leave empty → defaults to Saturday.',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                      ])),
                  const SizedBox(height: 16),
                  _colSection('Student Sheet', ['Roll Number','Student Name',
                    'Section','Year','Batch']),
                ])),
            ]))),

        const SizedBox(height: 20),

        // Windows instructions
        InfoCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 32, height: 32,
              decoration: BoxDecoration(gradient: AppTheme.greenGradient,
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.laptop_windows_rounded, color: Colors.white, size: 16)),
            const SizedBox(width: 12),
            const Text('Windows Import Guide', style: TextStyle(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
          const SizedBox(height: 14),
          ...[
            '1. Place your .xlsx file somewhere accessible (e.g. Desktop)',
            '2. Tap the Import button above',
            '3. Navigate to the file in the file picker dialog',
            '4. Select it and the import will begin automatically',
          ].map((t) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Container(width: 5, height: 5,
                decoration: BoxDecoration(color: AppTheme.primaryLt, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(t, style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12))),
            ]))),
        ])),
      ]),
    );
  }

  Widget _colSection(String title, List<String> cols) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(color: AppTheme.textSecondary,
          fontWeight: FontWeight.w700, fontSize: 11)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6,
        children: cols.map((c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.cardAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.border)),
          child: Text(c, style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.w500)))).toList()),
    ]);
}

class _TemplateBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final LinearGradient gradient;
  final bool loading;
  final VoidCallback? onTap;
  const _TemplateBtn({required this.label, required this.icon,
      required this.gradient, required this.loading, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: onTap != null ? gradient : null,
        color: onTap != null ? null : AppTheme.cardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border.withOpacity(0.5))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(loading ? Icons.hourglass_empty_rounded : Icons.download_rounded,
          color: Colors.white, size: 15),
        const SizedBox(width: 8),
        Flexible(child: Text(label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5))),
      ]),
    ),
  );
}

class _DataSummaryCard extends StatelessWidget {
  final IconData icon;
  final LinearGradient gradient;
  final String title, counts;
  final bool hasData, deleting;
  final VoidCallback? onClear;

  const _DataSummaryCard({
    required this.icon, required this.gradient,
    required this.title, required this.counts,
    required this.hasData, required this.deleting,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border)),
      child: Row(children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(
            gradient: hasData ? gradient : null,
            color: hasData ? null : AppTheme.card,
            borderRadius: BorderRadius.circular(9)),
          child: Icon(icon,
            color: hasData ? Colors.white : AppTheme.textMuted, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700, fontSize: 12.5)),
            Text(
              hasData ? counts : 'No data imported',
              style: TextStyle(
                color: hasData ? AppTheme.textSecondary : AppTheme.textMuted,
                fontSize: 11)),
          ])),
        GestureDetector(
            onTap: hasData ? onClear : null,
            child: Container(
              height: 32, width: 32,
              decoration: BoxDecoration(
                color: hasData
                    ? AppTheme.rose.withOpacity(0.10)
                    : AppTheme.cardAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasData
                      ? AppTheme.rose.withOpacity(0.3)
                      : AppTheme.border)),
              child: deleting
                ? const Padding(
                    padding: EdgeInsets.all(7),
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.rose))
                : Icon(Icons.delete_outline_rounded,
                    color: hasData ? AppTheme.rose : AppTheme.textMuted,
                    size: 16))),
      ]),
    );
  }
}

class _ImportCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle, description;
  final LinearGradient gradient;
  final bool loading;
  final VoidCallback? onTap;
  const _ImportCard({required this.icon, required this.title,
    required this.subtitle, required this.description,
    required this.gradient, required this.loading, this.onTap});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 48, height: 48,
          decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: Colors.white, size: 24)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700, fontSize: 14)),
          Text(subtitle, style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 11)),
        ])),
      ]),
      const SizedBox(height: 14),
      Text(description, style: const TextStyle(
          color: AppTheme.textSecondary, fontSize: 12, height: 1.5)),
      const SizedBox(height: 18),
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 42, alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: onTap != null ? gradient : null,
            color: onTap != null ? null : AppTheme.cardAlt,
            borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.upload_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            const Text('Import File', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ]))),
    ]));
}
