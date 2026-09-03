import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/models.dart';
import '../../utils/app_theme.dart';
import '../../widgets/profile_dropdown.dart';
import '../../utils/responsive.dart';
import '../../widgets/ds.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/timetable_grid.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});
  @override State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _db = DatabaseService();

  List<TimetableEntry>   _entries  = [];
  Map<String, String>    _subNames = {};
  Map<String, String>    _facNames = {};
  List<AttendanceRecord> _records  = [];
  List<Subject>          _subjects = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this,
        animationDuration: Duration.zero);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final s = context.read<AuthService>().student!;
      final entries  = await _db.getTimetableBySection(s.section, s.year);
      final subjects = await _db.getSubjectsBySection(s.section, s.year);
      final faculty  = await _db.getAllFaculty();
      final records  = await _db.getAttendanceForStudent(s.id);
      if (!mounted) return;
      setState(() {
        _entries  = entries;
        _subNames = {for (final x in subjects) x.id: x.name};
        _facNames = {for (final x in faculty)  x.id: x.name};
        _records  = records;
        _subjects = subjects;
        _loaded   = true;
      });
  
    } catch (e) {
      debugPrint('_load error: $e');
      if (mounted) setState(() { _loaded = true; });
    }}

  // Overall attendance %
  double get _overallPct {
    if (_records.isEmpty) return 0;
    return _records.where((r) => r.isPresent).length / _records.length * 100;
  }

  // Per-subject attendance
  Map<String, _SubAtt> get _perSubject {
    final map = <String, _SubAtt>{};
    for (final sub in _subjects) {
      final r = _records.where((r) => r.subjectId == sub.id).toList();
      map[sub.id] = _SubAtt(
        name:  sub.name,
        total: r.length,
        present: r.where((r) => r.isPresent).length,
      );
    }
    return map;
  }

  // Today's entries
  List<TimetableEntry> get _todayEntries {
    final dow = DateTime.now().weekday;
    if (dow > 6) return [];
    return _entries
        .where((e) => e.dayOfWeek == dow && e.specialLabel == null)
        .toList()
      ..sort((a, b) => a.periodNumber.compareTo(b.periodNumber));
  }

  @override
  Widget build(BuildContext context) {
    final student = context.watch<AuthService>().student!;
    final navItems = buildNavEntries([
      (Icons.dashboard_rounded,      'Overview',   () => setState(() => _tab.animateTo(0))),
      (Icons.calendar_month_rounded, 'Timetable',  () => setState(() => _tab.animateTo(1))),
      (Icons.bar_chart_rounded,      'Attendance', () => setState(() => _tab.animateTo(2))),
    ]);
    Widget tabContent;
    if (!_loaded) {
      tabContent = const DsLoader();
    } else {
      switch (_tab.index) {
        case 1:  tabContent = _buildTimetableTab();  break;
        case 2:  tabContent = _buildAttendanceTab(); break;
        default: tabContent = _buildOverview(student);
      }
    }

    // ── Mobile ──────────────────────────────────────────────────────────────
    if (R.isMobile(context)) {
      return MobileShell(
        selectedIndex: _tab.index,
        items: navItems,
        userName: student.name,
        userSub: '${student.section} · Year ${student.year}',
        onLogout: context.read<AuthService>().logout,
        onChangePassword: () => _showStudentChangePasswordDialog(context, student),
        topBar: _topBar(student),
        body: tabContent,
      );
    }

    // ── Desktop ─────────────────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Row(children: [
        AppSidebar(
          selectedIndex: _tab.index,
          items: navItems,
          userName: student.name,
          userSub: '${student.section} · Year ${student.year}',
          onLogout: context.read<AuthService>().logout,
        ),
        Expanded(child: Column(children: [
          _topBar(student),
          Expanded(child: tabContent),
        ])),
      ]),
    );
  }

  Widget _topBar(Student student) => LayoutBuilder(
    builder: (context, constraints) {
      final isMob = constraints.maxWidth < 600;
      final profile = Builder(builder: (ctx) => ProfileDropdown(compact: isMob,
        name:     student.name,
        subtitle: 'Roll No: ${student.rollNumber}',
        gradient: AppTheme.orangeGradient,
        details:  [
          ('Name',      student.name),
          ('Roll No',   student.rollNumber),
          ('Section',   student.section),
          ('Year',      'Year ${student.year}'),
          ('Batch',     'Batch ${student.batch}'),
        ],
        onChangePassword: () => _showStudentChangePasswordDialog(ctx, student),
        onLogout: () => context.read<AuthService>().logout(),
      ));

      return Container(
        height: 68,
        padding: EdgeInsets.symmetric(horizontal: isMob ? 14 : 28),
        decoration: BoxDecoration(
          color: AppTheme.sidebar,
          border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: Row(children: [
          Flexible(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hi, ${student.name.split(' ').first}! 👋',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.textPrimary,
                fontSize: isMob ? 15 : 20, fontWeight: FontWeight.w800)),
            Text(isMob
                ? '${student.section} • Yr${student.year} • ${student.rollNumber}'
                : '${student.section} • Year ${student.year} • ${student.rollNumber}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ])),
          const Spacer(),
          if (!isMob) ...[
            Container(
              width: 180, height: 36,
              decoration: BoxDecoration(
                color: AppTheme.cardAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border)),
              child: const Row(children: [
                SizedBox(width: 10),
                Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 14),
                SizedBox(width: 7),
                Text('Search...', style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 12)),
              ])),
            const SizedBox(width: 8),
            Container(width: 34, height: 34,
              decoration: BoxDecoration(
                color: AppTheme.cardAlt,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppTheme.border)),
              child: IconButton(
                icon: const Icon(Icons.refresh_rounded,
                  color: AppTheme.textSecondary, size: 15),
                onPressed: _load, padding: EdgeInsets.zero)),
            const SizedBox(width: 8),
            Container(width: 34, height: 34,
              decoration: BoxDecoration(
                color: AppTheme.cardAlt,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppTheme.border)),
              child: const Icon(Icons.notifications_none_rounded,
                color: AppTheme.textSecondary, size: 16)),
            const SizedBox(width: 12),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                color: AppTheme.textSecondary, size: 18),
              onPressed: _load, padding: EdgeInsets.zero),
            const SizedBox(width: 4),
          ],
          profile,
        ]),
      );
    },
  );

  
  // ── Overview Tab ──────────────────────────────────────────────────────────
  Widget _buildOverview(Student student) {
    final overall   = _overallPct;
    final attColor  = overall >= 75 ? AppTheme.emerald
        : overall >= 60 ? AppTheme.amber : AppTheme.rose;
    final today     = _todayEntries;
    final perSub    = _perSubject;
    final lowSubs   = perSub.values
        .where((a) => a.total > 0 && a.pct < 75).length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Attendance summary card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Attendance Overview',
              style: TextStyle(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Column(children: [
                Text('${overall.toStringAsFixed(1)}%',
                  style: TextStyle(color: attColor,
                    fontSize: 32, fontWeight: FontWeight.w900)),
                const Text('Overall', style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 11)),
              ])),
              const SizedBox(width: 16),
              Expanded(child: Column(children: [
                Text('${_records.where((r) => r.isPresent).length}',
                  style: const TextStyle(color: AppTheme.textPrimary,
                    fontSize: 24, fontWeight: FontWeight.w800)),
                const Text('Present', style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 11)),
              ])),
              Expanded(child: Column(children: [
                Text('${_records.where((r) => !r.isPresent).length}',
                  style: const TextStyle(color: AppTheme.rose,
                    fontSize: 24, fontWeight: FontWeight.w800)),
                const Text('Absent', style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 11)),
              ])),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: overall / 100,
                minHeight: 8,
                backgroundColor: AppTheme.cardAlt,
                valueColor: AlwaysStoppedAnimation(attColor))),
            if (overall < 75) ...[
              const SizedBox(height: 8),
              Text(
                'You need ${((_records.length * 0.75 - _records.where((r) => r.isPresent).length) / 0.25).ceil()} more classes to reach 75%',
                style: const TextStyle(
                  color: AppTheme.amber, fontSize: 11)),
            ],
          ])),
        const SizedBox(height: 14),

        // Low attendance warning
        if (lowSubs > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.rose.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.rose.withOpacity(0.25))),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                color: AppTheme.rose, size: 16),
              const SizedBox(width: 8),
              Text('$lowSubs subject${lowSubs > 1 ? "s" : ""} below 75% — at risk',
                style: const TextStyle(
                  color: AppTheme.rose, fontSize: 12,
                  fontWeight: FontWeight.w600)),
            ])),

        // Today's classes
        const Text("Today's Classes",
          style: TextStyle(color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        if (today.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border)),
            child: const Center(child: Text('No classes today',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12))))
        else
          ...today.map((e) {
            final sub  = _subNames[e.subjectId] ?? 'Subject';
            final slot = TimeSlot.getByNumber(e.periodNumber);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border)),
              child: Row(children: [
                Container(
                  width: 6, height: 40,
                  decoration: BoxDecoration(
                    color: e.isLab
                        ? AppTheme.labColor : AppTheme.theoryColor,
                    borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sub, style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600, fontSize: 12)),
                    Text('P${e.periodNumber}'
                      + (slot != null
                          ? '  ${slot.startTime} – ${slot.endTime}'
                          : ''),
                      style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11)),
                  ])),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: (e.isLab
                        ? AppTheme.labColor
                        : AppTheme.theoryColor).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5)),
                  child: Text(e.isLab ? 'LAB' : 'LEC',
                    style: TextStyle(
                      color: e.isLab
                          ? AppTheme.labColor : AppTheme.theoryColor,
                      fontSize: 9, fontWeight: FontWeight.w800))),
              ]));
          }),
      ],
    );
  }

  // ── Timetable Tab ──────────────────────────────────────────────────────────
  Widget _buildTimetableTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TimetableGridWidget(
        entries: _entries,
        subjectNames: _subNames,
        facultyNames: _facNames,
        showFaculty: true,
      ),
    );
  }

  // ── Attendance Tab ─────────────────────────────────────────────────────────
  Widget _buildAttendanceTab() {
    final perSub = _perSubject;
    if (perSub.isEmpty) {
      return const Center(child: Text('No attendance data yet.',
        style: TextStyle(color: AppTheme.textMuted)));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: perSub.entries.map((kv) {
        final a        = kv.value;
        final pct      = a.total == 0 ? 0.0 : a.pct;
        final color    = pct >= 75 ? AppTheme.emerald
            : pct >= 60 ? AppTheme.amber : AppTheme.rose;
        final need     = a.total == 0 ? 0
            : (0.75 * a.total - a.present).ceil().clamp(0, 999);
        final canSkip  = a.total == 0 ? 0
            : ((a.present - 0.75 * a.total) / 0.75).floor().clamp(0, 999);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(a.name,
                  style: const TextStyle(color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600, fontSize: 12))),
                Text('${pct.toStringAsFixed(1)}%',
                  style: TextStyle(color: color,
                    fontWeight: FontWeight.w800, fontSize: 13)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Text('${a.present} present / ${a.total} total',
                  style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11)),
                const Spacer(),
                if (pct < 75 && need > 0)
                  Text('Need $need more',
                    style: const TextStyle(
                      color: AppTheme.rose, fontSize: 10.5))
                else if (pct >= 75 && canSkip > 0)
                  Text('Can skip $canSkip',
                    style: const TextStyle(
                      color: AppTheme.emerald, fontSize: 10.5)),
              ]),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: a.total == 0 ? 0 : pct / 100,
                  minHeight: 6,
                  backgroundColor: AppTheme.cardAlt,
                  valueColor: AlwaysStoppedAnimation(color))),
            ]));
      }).toList(),
    );
  }
}

// ── Change password dialog (student) ──────────────────────────────────────────
void _showStudentChangePasswordDialog(BuildContext context, Student student) {
  final currCtrl = TextEditingController();
  final newCtrl  = TextEditingController();
  final confCtrl = TextEditingController();
  bool obscureCurr = true, obscureNew = true, obscureConf = true;
  String? errMsg;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.border)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Change Password',
            style: TextStyle(color: AppTheme.textPrimary,
              fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.primary.withOpacity(0.2))),
            child: Text(
              'Forgot password? Log in using your roll number + K\n'
              'e.g. ${student.rollNumber}K  — this resets to default.',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 10.5, height: 1.4))),
        ]),
        content: SizedBox(width: 340, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StudentPwdField(ctrl: currCtrl,
              label: 'Current Password',
              obscure: obscureCurr,
              onToggle: () => setS(() => obscureCurr = !obscureCurr)),
            const SizedBox(height: 12),
            _StudentPwdField(ctrl: newCtrl, label: 'New Password',
              obscure: obscureNew,
              onToggle: () => setS(() => obscureNew = !obscureNew),
              hint: 'Min 6 chars, include a number or symbol'),
            const SizedBox(height: 12),
            _StudentPwdField(ctrl: confCtrl,
              label: 'Confirm New Password',
              obscure: obscureConf,
              onToggle: () => setS(() => obscureConf = !obscureConf)),
            if (errMsg != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.error.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded,
                    color: AppTheme.error, size: 14),
                  const SizedBox(width: 7),
                  Expanded(child: Text(errMsg!,
                    style: const TextStyle(
                      color: AppTheme.error, fontSize: 11.5))),
                ])),
            ],
          ])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
              style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              if (newCtrl.text.trim() != confCtrl.text.trim()) {
                setS(() => errMsg = 'Passwords do not match.');
                return;
              }
              final auth = context.read<AuthService>();
              final err = await auth.changeStudentPassword(
                currentPassword: currCtrl.text.trim(),
                newPassword: newCtrl.text.trim(),
              );
              if (!ctx.mounted) return;
              if (err != null) {
                setS(() => errMsg = err);
              } else {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: AppTheme.success,
                  content: const Text('Password changed!',
                    style: TextStyle(color: Colors.white)),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))));
              }
            },
            child: const Text('Change')),
        ])));
}

class _StudentPwdField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  final String? hint;
  const _StudentPwdField({
    required this.ctrl, required this.label,
    required this.obscure, required this.onToggle,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
        color: AppTheme.textSecondary, fontSize: 11.5,
        fontWeight: FontWeight.w600)),
      const SizedBox(height: 5),
      TextField(
        controller: ctrl, obscureText: obscure,
        style: const TextStyle(
          color: AppTheme.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint ?? 'Enter $label',
          hintStyle: const TextStyle(
            color: AppTheme.textMuted, fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
              size: 16, color: AppTheme.textMuted),
            onPressed: onToggle,
            padding: EdgeInsets.zero))),
    ]);
  }
}

class _SubAtt {
  final String name;
  final int total, present;
  const _SubAtt({required this.name, required this.total, required this.present});
  double get pct => total == 0 ? 0 : present / total * 100;
}
