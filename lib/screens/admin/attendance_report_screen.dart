import 'package:flutter/material.dart';
import '../../services/database_service.dart';
import '../../services/excel_service.dart';
import '../../models/models.dart';
import '../../utils/app_theme.dart';
import '../../utils/responsive.dart';

// ── Subject detail model ─────────────────────────────────────────────────────
class _SubDetail {
  final double pct;
  final int present, total;
  const _SubDetail(this.pct, this.present, this.total);
  int get needed => total == 0 ? 0
      : (0.75 * total - present).ceil().clamp(0, 999);
  // Classes to skip before dropping below 75%
  int get canSkip => present == 0 ? 0
      : ((present - 0.75 * total) / 0.75).floor().clamp(0, 999);
}

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});
  @override State<AttendanceReportScreen> createState() => _AttState();
}

class _AttState extends State<AttendanceReportScreen> {
  final _db      = DatabaseService();
  final _excel   = ExcelService();
  final _secCtrl = TextEditingController();

  int          _year       = 1;
  List<int>    _availYears = [1, 2, 3, 4];
  bool         _loading    = false;
  String?      _expandedId; // roll number of expanded student row

  List<Student>         _students = [];
  List<AttendanceRecord>_records  = [];
  List<Subject>         _subjects = [];
  Map<String, String>   _subNames = {};

  @override
  void initState() {
    super.initState();
    _loadYears();
  }

  @override
  void dispose() {
    _secCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadYears() async {
    final yrs = await _db.getDistinctYears();
    if (!mounted) return;
    setState(() {
      if (yrs.isNotEmpty) {
        _availYears = yrs;
        if (!yrs.contains(_year)) _year = yrs.first;
      }
    });
  }

  Future<void> _load() async {
    try {
      final sec = _secCtrl.text.trim().toUpperCase();
      if (sec.isEmpty) return;
      setState(() { _loading = true; _expandedId = null; });
      final students = await _db.getStudentsBySection(sec, _year);
      final subjects = await _db.getSubjectsBySection(sec, _year);
      final allRecs  = <AttendanceRecord>[];
      for (final s in students) {
        allRecs.addAll(await _db.getAttendanceForStudent(s.id));
      }
      if (!mounted) return;
      setState(() {
        _students = students;
        _subjects = subjects.where((s) => !s.isLab || s.batch == 0).toList();
        _records  = allRecs;
        _subNames = {for (final s in subjects) s.id: s.name};
        _loading  = false;
      });
  
    } catch (e) {
      debugPrint('attendance report _load error: $e');
      if (mounted) setState(() { _loading = false; });
    }}

  Future<void> _export() async {
    final path = await _excel.exportAttendance(
      students: _students, records: _records,
      subjectNames: _subNames,
      section: _secCtrl.text.trim().toUpperCase());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(path != null ? '✅ Exported: $path' : '❌ Export failed')));
  }

  // ── Per-student per-subject attendance ──────────────────────────────────
  Map<String, _SubDetail> _subjectDetails(String studentId) {
    final map = <String, _SubDetail>{};
    for (final sub in _subjects) {
      final r = _records.where((r) =>
          r.studentId == studentId && r.subjectId == sub.id).toList();
      final pres  = r.where((r) => r.isPresent).length;
      final total = r.length;
      final pct   = total == 0 ? 0.0 : pres / total * 100;
      map[sub.id] = _SubDetail(pct, pres, total);
    }
    return map;
  }

  double _overallPct(String studentId) {
    final r = _records.where((r) => r.studentId == studentId).toList();
    if (r.isEmpty) return 0.0;
    return r.where((r) => r.isPresent).length / r.length * 100;
  }

  @override
  Widget build(BuildContext context) {
    final isMob = R.isMobile(context);
    final low   = _students.where((s) => _overallPct(s.id) < 75).length;
    final pad   = isMob ? 14.0 : 28.0;

    return Padding(
      padding: EdgeInsets.all(pad),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header + controls ──────────────────────────────────────────────
        isMob ? _mobileHeader() : _desktopHeader(),
        const SizedBox(height: 16),

        // ── Content ───────────────────────────────────────────────────────
        if (_loading)
          const Expanded(child: Center(
              child: CircularProgressIndicator(color: AppTheme.primaryLt)))
        else if (_students.isEmpty)
          _emptyState()
        else ...[
          // Summary row
          _SummaryRow(total: _students.length, low: low),
          const SizedBox(height: 14),
          // Student list
          Expanded(child: ListView.builder(
            itemCount: _students.length,
            itemBuilder: (_, i) {
              final s     = _students[i];
              final pct   = _overallPct(s.id);
              final isExp = _expandedId == s.rollNumber;
              return _StudentCard(
                student:   s,
                overallPct: pct,
                subjectDetails: isExp ? _subjectDetails(s.id) : {},
                subjects:  _subjects,
                expanded:  isExp,
                onTap: () => setState(() =>
                    _expandedId = isExp ? null : s.rollNumber),
              );
            })),
        ],
      ]),
    );
  }

  // ── Desktop header ───────────────────────────────────────────────────────
  Widget _desktopHeader() => Row(children: [
    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Attendance Reports', style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 18, fontWeight: FontWeight.w700)),
      SizedBox(height: 2),
      Text('Tap a student to see per-subject breakdown',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
    ]),
    const Spacer(),
    SizedBox(width: 140, child: _sectionField()),
    const SizedBox(width: 10),
    _yearDropdown(),
    const SizedBox(width: 10),
    _gradBtn('Load', Icons.search_rounded, _load),
    const SizedBox(width: 8),
    IconButton(
      icon: Icon(Icons.download_rounded,
          color: _records.isNotEmpty ? AppTheme.primaryLt : AppTheme.textMuted),
      onPressed: _records.isNotEmpty ? _export : null,
      tooltip: 'Export CSV'),
  ]);

  // ── Mobile header ────────────────────────────────────────────────────────
  Widget _mobileHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Attendance Reports', style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _sectionField()),
        const SizedBox(width: 8),
        _yearDropdown(),
        const SizedBox(width: 8),
        _gradBtn('Load', Icons.search_rounded, _load),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: _records.isNotEmpty ? _export : null,
          child: Container(
            width: 38, height: 40,
            decoration: BoxDecoration(
              color: _records.isNotEmpty
                  ? AppTheme.primary.withOpacity(0.12)
                  : AppTheme.cardAlt,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: _records.isNotEmpty
                    ? AppTheme.primary.withOpacity(0.3)
                    : AppTheme.border)),
            child: Icon(Icons.download_rounded,
              color: _records.isNotEmpty
                  ? AppTheme.primaryLt : AppTheme.textMuted,
              size: 16))),
      ]),
    ]);

  Widget _sectionField() => TextField(
    controller: _secCtrl,
    textCapitalization: TextCapitalization.characters,
    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
    decoration: const InputDecoration(
      hintText: 'Section  e.g. A',
      prefixIcon: Icon(Icons.class_rounded, size: 16),
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)));

  Widget _yearDropdown() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.border)),
    child: DropdownButtonHideUnderline(child: DropdownButton<int>(
      value: _year, dropdownColor: AppTheme.card,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      items: _availYears.map((y) => DropdownMenuItem(
          value: y, child: Text('Year $y'))).toList(),
      onChanged: (v) => setState(() {
        _year = v ?? 1;
        _students = []; _records = []; _subjects = [];
      }))));

  Widget _emptyState() => Expanded(child: Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(width: 60, height: 60,
        decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.1), shape: BoxShape.circle),
        child: const Icon(Icons.bar_chart_rounded,
            color: AppTheme.primaryLt, size: 28)),
      const SizedBox(height: 14),
      const Text('Enter a section and tap Load',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      const SizedBox(height: 4),
      const Text('Tap any student row to see per-subject breakdown',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
    ])));
}

// ── Summary row ───────────────────────────────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  final int total, low;
  const _SummaryRow({required this.total, required this.low});

  @override
  Widget build(BuildContext context) => Row(children: [
    _card('Total', '$total', Icons.people_rounded,    AppTheme.purpleGradient),
    const SizedBox(width: 10),
    _card('Below 75%', '$low', Icons.warning_rounded, AppTheme.orangeGradient),
    const SizedBox(width: 10),
    _card('Above 75%', '${total - low}',
        Icons.check_circle_rounded, AppTheme.greenGradient),
  ]);

  Widget _card(String label, String value, IconData icon,
      LinearGradient grad) =>
    Expanded(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: grad, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
          color: grad.colors.first.withOpacity(0.28),
          blurRadius: 12, offset: const Offset(0, 5))]),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(
              color: Colors.white.withOpacity(0.8), fontSize: 10)),
        ]),
      ])));
}

// ── Student card with expandable per-subject breakdown ────────────────────────
class _StudentCard extends StatelessWidget {
  final Student              student;
  final double               overallPct;
  final Map<String, _SubDetail> subjectDetails;
  final List<Subject>        subjects;
  final bool                 expanded;
  final VoidCallback         onTap;

  const _StudentCard({
    required this.student,    required this.overallPct,
    required this.subjectDetails,required this.subjects,
    required this.expanded,   required this.onTap,
  });

  Color _color(double pct) =>
      pct >= 75 ? AppTheme.success
      : pct >= 50 ? AppTheme.warning
      : AppTheme.error;

  @override
  Widget build(BuildContext context) {
    final c = _color(overallPct);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: expanded
              ? AppTheme.primary.withOpacity(0.06)
              : AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: expanded
                ? AppTheme.primary.withOpacity(0.28)
                : overallPct < 75
                    ? AppTheme.error.withOpacity(0.22)
                    : AppTheme.border,
            width: expanded ? 1.3 : 1.0)),
        child: Column(children: [
          // ── Main row ───────────────────────────────────────────────────
          Row(children: [
            // Percentage badge
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: c.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.withOpacity(0.3))),
              child: Center(child: Text(
                '${overallPct.toStringAsFixed(0)}%',
                style: TextStyle(color: c,
                    fontWeight: FontWeight.w800, fontSize: 11)))),
            const SizedBox(width: 12),
            // Name + roll
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.name, style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700, fontSize: 13),
                  overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${student.rollNumber}  •  Batch ${student.batch}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11)),
                const SizedBox(height: 6),
                // Overall progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: overallPct / 100,
                    minHeight: 4,
                    backgroundColor: c.withOpacity(0.10),
                    valueColor: AlwaysStoppedAnimation(c))),
              ])),
            const SizedBox(width: 8),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: AppTheme.textMuted, size: 18),
          ]),

          // ── Expanded: per-subject breakdown ───────────────────────────
          if (expanded && subjectDetails.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: AppTheme.border, height: 1),
            const SizedBox(height: 10),
            ...subjects.map((sub) {
              final pct = subjectPcts[sub.id] ?? 0.0;
              final sc  = _color(pct);
              // How many more classes needed to reach 75%
              final recs = subjectPcts.isNotEmpty;
              String need = '';
              if (pct < 75) {
                // present count back-calculated from pct and records
                // We don't have direct count here, so show percentage shortfall
                final shortfall = 75.0 - pct;
                need = '${shortfall.toStringAsFixed(0)}% below target';
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(children: [
                  Expanded(child: Text(sub.name,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11),
                    overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  SizedBox(width: 90, child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct / 100,
                      minHeight: 6,
                      backgroundColor: sc.withOpacity(0.10),
                      valueColor: AlwaysStoppedAnimation(sc)))),
                  const SizedBox(width: 8),
                  SizedBox(width: 38, child: Text(
                    '${pct.toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: sc, fontSize: 11,
                        fontWeight: FontWeight.w700))),
                ]));
            }),
          ],
        ]),
      ),
    );
  }
}

// ── Gradient button ───────────────────────────────────────────────────────────
Widget _gradBtn(String label, IconData icon, VoidCallback onTap) =>
  GestureDetector(
    onTap: onTap,
    child: Container(
      height: 40, padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: AppTheme.purpleGradient,
        borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 15),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
      ])));
