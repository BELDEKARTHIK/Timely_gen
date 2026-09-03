import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import 'archive_screen.dart';
import '../../services/notification_service.dart';
import '../../models/models.dart';
import '../../utils/app_theme.dart';
import '../../widgets/profile_dropdown.dart';
import '../../utils/responsive.dart';
import '../../widgets/ds.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/timetable_grid.dart';

class FacultyDashboard extends StatefulWidget {
  const FacultyDashboard({super.key});
  @override State<FacultyDashboard> createState() => _FacultyDashboardState();
}

class _FacultyDashboardState extends State<FacultyDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _db    = DatabaseService();
  final _notif = NotificationService();
  final _uuid  = const Uuid();

  List<TimetableEntry> _entries     = [];
  Map<String, String>  _subNames    = {};
  Map<String, String>  _facNames    = {};
  Map<String, bool>    _markedToday = {};
  bool _loaded     = false;
  bool _isIncharge = false;

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
      final fId = context.read<AuthService>().faculty?.id ?? '';
      final entries = await _db.getTimetableByFaculty(fId);
      final subs    = await _db.getAllSubjects();
      final fac     = await _db.getAllFaculty();
      final subMap  = {for (final s in subs) s.id: s.name};
      final facMap  = {for (final f in fac) f.id: f.name};
      final today   = DateTime.now();
      final marked  = <String, bool>{};
      for (final e in entries.where(
          (e) => e.dayOfWeek == today.weekday && e.specialLabel == null))
        marked[e.id] = await _db.hasMarkedSession(
            timetableEntryId: e.id, date: today);
      await _db.pruneOldAttendance(); // default: 180 days (one semester)
      if (!kIsWeb)
        await _notif.scheduleFacultyReminders(
            entries: entries, subjectNames: subMap, facultyId: fId);
      final inchargeSections = await _db.getInchargeSections(fId);
      if (!mounted) return;
      setState(() {
        _entries     = entries; _subNames = subMap;
        _facNames    = facMap;  _markedToday = marked;
        _loaded      = true;
        _isIncharge  = inchargeSections.isNotEmpty;
      });
  
    } catch (e) {
      debugPrint('_load error: $e');
      if (mounted) setState(() { _loaded = true; });
    }}

  Future<void> _refreshMarked() async {
    final today = DateTime.now();
    final map   = <String, bool>{};
    for (final e in _entries.where(
        (e) => e.dayOfWeek == today.weekday && e.specialLabel == null))
      map[e.id] = await _db.hasMarkedSession(
          timetableEntryId: e.id, date: today);
    if (!mounted) return;
    setState(() => _markedToday = map);
  }

  List<TimetableEntry> get _todayEntries {
    final dow = DateTime.now().weekday;
    if (dow > 6) return [];
    return _entries.where((e) =>
        e.dayOfWeek == dow && e.specialLabel == null).toList()
      ..sort((a, b) => a.periodNumber.compareTo(b.periodNumber));
  }

  @override
  Widget build(BuildContext context) {
    final faculty = context.watch<AuthService>().faculty!;
    final marked  = _markedToday.values.where((v) => v).length;
    final total   = _todayEntries.length;

    final navItems = buildNavEntries([
      (Icons.today_rounded,          'Today',     () => setState(() => _tab.animateTo(0))),
      (Icons.calendar_month_rounded, 'Timetable', () => setState(() => _tab.animateTo(1))),
      (Icons.history_rounded,        'History',   () => setState(() => _tab.animateTo(2))),
    ]);
    final logoutFn = () async {
      if (!kIsWeb)
        await _notif.cancelAllNotifications();
      if (context.mounted) context.read<AuthService>().logout();
    };
    final tabContent = !_loaded
        ? const DsLoader()
        : switch (_tab.index) {
            1 => TimetableGridWidget(entries: _entries,
                subjectNames: _subNames, facultyNames: _facNames,
                showFaculty: false),
            2 => _HistoryTab(db: _db, faculty: faculty,
                subNames: _subNames, uuid: _uuid, onRefresh: _load),
            _ => _TodayTab(entries: _todayEntries, subNames: _subNames,
                markedToday: _markedToday, db: _db, uuid: _uuid,
                faculty: faculty, onDone: _refreshMarked),
          };

    // ── Mobile layout ───────────────────────────────────────────────────────
    if (R.isMobile(context)) {
      return MobileShell(
        selectedIndex: _tab.index,
        items: navItems,
        userName: faculty.name,
        userSub: 'Faculty',
        onLogout: logoutFn,
        onChangePassword: () => _showChangePasswordDialog(context, faculty),
        topBar: _topBar(faculty, marked, total),
        body: tabContent,
      );
    }

    // ── Desktop layout ──────────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Row(children: [
        AppSidebar(
          selectedIndex: _tab.index,
          items: navItems,
          userName: faculty.name,
          userSub: 'Faculty',
          onLogout: logoutFn,
        ),
        Expanded(child: Column(children: [
          _topBar(faculty, marked, total),
          Expanded(child: tabContent),
        ])),
      ]),
    );
  }

  Widget _topBar(Faculty f, int marked, int total) => LayoutBuilder(
    builder: (context, constraints) {
      final isMob = constraints.maxWidth < 600;
      final profile = Builder(builder: (ctx) => ProfileDropdown(compact: isMob,
        name:     f.name,
        subtitle: 'Employee ID: ${f.employeeId}',
        gradient: AppTheme.purpleGradient,
        details:  [
          ('Name',        f.name),
          ('Employee ID', f.employeeId),
          ('Email',       f.email),
          ('Role',        f.isAdmin ? 'Admin' : 'Faculty'),
        ],
        onChangePassword: () => _showChangePasswordDialog(ctx, f),
        onLogout: () => context.read<AuthService>().logout(),
      ));

      return Container(
        height: 68,
        padding: EdgeInsets.symmetric(horizontal: isMob ? 14 : 28),
        decoration: BoxDecoration(
          color: AppTheme.sidebar,
          border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: Row(children: [
          // Greeting — shrinks on mobile
          Flexible(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hi, ${f.name.split(' ').first}! 👋',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.textPrimary,
                fontSize: isMob ? 15 : 20, fontWeight: FontWeight.w800)),
            Text(isMob ? f.employeeId : 'ID: ${f.employeeId}  •  Teaching dashboard',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ])),
          if (!isMob && total > 0) ...[
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: marked == total
                    ? AppTheme.emerald.withOpacity(0.12)
                    : AppTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: (marked == total
                    ? AppTheme.emerald : AppTheme.primary).withOpacity(0.3))),
              child: Text('$marked/$total today',
                style: TextStyle(
                  color: marked == total ? AppTheme.emerald : AppTheme.primaryLt,
                  fontWeight: FontWeight.w700, fontSize: 12))),
          ],
          const Spacer(),
          if (!isMob) ...[
            // Desktop: search + refresh + notifications
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
            // Mobile: just refresh icon
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
}

void _showChangePasswordDialog(BuildContext context, Faculty f) {
  final currCtrl = TextEditingController();
  final newCtrl  = TextEditingController();
  final confCtrl = TextEditingController();
  bool obscureCurr = true, obscureNew = true, obscureConf = true;
  String? errMsg;
  bool isDefault = f.passwordHash == f.employeeId ||
      f.passwordHash.isEmpty;

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
          if (isDefault)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.amber.withOpacity(0.35))),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded,
                  color: AppTheme.amber, size: 14),
                const SizedBox(width: 6),
                const Expanded(child: Text(
                  'You are using the default password. Please change it.',
                  style: TextStyle(color: AppTheme.textSecondary,
                    fontSize: 11, height: 1.3))),
              ])),
        ]),
        content: SizedBox(width: 340, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PwdField(ctrl: currCtrl, label: 'Current Password',
              obscure: obscureCurr,
              onToggle: () => setS(() => obscureCurr = !obscureCurr)),
            const SizedBox(height: 12),
            _PwdField(ctrl: newCtrl, label: 'New Password',
              obscure: obscureNew,
              onToggle: () => setS(() => obscureNew = !obscureNew),
              hint: 'Min 6 chars, include a number or symbol'),
            const SizedBox(height: 12),
            _PwdField(ctrl: confCtrl, label: 'Confirm New Password',
              obscure: obscureConf,
              onToggle: () => setS(() => obscureConf = !obscureConf)),
            if (errMsg != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.error.withOpacity(0.3))),
                child: Row(children: [
                  Icon(Icons.error_outline_rounded,
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
              final err = await auth.changeFacultyPassword(
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
                  content: const Text('Password changed successfully!',
                    style: TextStyle(color: Colors.white)),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))));
              }
            },
            child: const Text('Change Password')),
        ])),
  );
}

// Reusable password text field widget used in the change-password dialog
class _PwdField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  final String? hint;
  const _PwdField({
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
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint ?? 'Enter $label',
          hintStyle: const TextStyle(
            color: AppTheme.textMuted, fontSize: 12),
          contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: IconButton(
            icon: Icon(obscure
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
              size: 16, color: AppTheme.textMuted),
            onPressed: onToggle,
            padding: EdgeInsets.zero))),
    ]);
  }
}

// ── Today Tab ────────────────────────────────────────────────────────────
class _TodayTab extends StatelessWidget {
  final List<TimetableEntry> entries;
  final Map<String, String>  subNames;
  final Map<String, bool>    markedToday;
  final DatabaseService      db;
  final Uuid                 uuid;
  final Faculty              faculty;
  final VoidCallback         onDone;

  const _TodayTab({required this.entries, required this.subNames,
    required this.markedToday, required this.db, required this.uuid,
    required this.faculty, required this.onDone});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppTheme.emerald.withOpacity(0.1),
            shape: BoxShape.circle),
          child: const Icon(Icons.celebration_rounded,
              color: AppTheme.emerald, size: 28)),
        const SizedBox(height: 14),
        const Text('No classes today!', style: TextStyle(
            color: AppTheme.textPrimary, fontSize: 18,
            fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Enjoy your free day 🎉',
            style: TextStyle(color: AppTheme.textSecondary)),
      ]));

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final e      = entries[i];
        final slot   = TimeSlot.getByNumber(e.periodNumber);
        final sub    = subNames[e.subjectId] ?? 'Unknown';
        final marked = markedToday[e.id] ?? false;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: marked
                    ? AppTheme.emerald.withOpacity(0.3) : AppTheme.border)),
          child: Row(children: [
            // Period badge
            Container(width: 52, height: 52,
              decoration: BoxDecoration(
                gradient: AppTheme.purpleGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                  color: AppTheme.purple.withOpacity(0.3),
                  blurRadius: 10, offset: const Offset(0, 4))]),
              child: Center(child: Text('P${e.periodNumber}',
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w800, fontSize: 14)))),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sub, style: const TextStyle(color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(Icons.schedule_rounded,
                      size: 12, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text('${slot?.startTime ?? ''}–${slot?.endTime ?? ''}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(width: 10),
                  Icon(Icons.class_rounded,
                      size: 12, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text('${e.section} Yr${e.year}'
                      '${e.batch > 0 ? " B${e.batch}" : ""}',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ]),
              ],
            )),
            GestureDetector(
              onTap: () => Navigator.push(
                ctx, MaterialPageRoute(
                  builder: (_) => MarkAttendanceScreen(
                    entry: e, subjectName: sub, db: db, uuid: uuid,
                    faculty: faculty, sessionDate: DateTime.now(),
                    alreadyMarked: marked))).then((_) => onDone()),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  gradient: marked ? null : AppTheme.purpleGradient,
                  color: marked ? AppTheme.cardAlt : null,
                  borderRadius: BorderRadius.circular(10),
                  border: marked ? Border.all(color: AppTheme.border) : null),
                child: Text(marked ? 'Edit' : 'Mark',
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w700, fontSize: 13))),
            ),
          ]),
        );
      },
    );
  }
}

// ── Mark Attendance Screen ────────────────────────────────────────────────
class MarkAttendanceScreen extends StatefulWidget {
  final TimetableEntry  entry;
  final String          subjectName;
  final DatabaseService db;
  final Uuid            uuid;
  final Faculty         faculty;
  final DateTime        sessionDate;
  final bool            alreadyMarked;

  const MarkAttendanceScreen({super.key,
    required this.entry, required this.subjectName,
    required this.db, required this.uuid, required this.faculty,
    required this.sessionDate, this.alreadyMarked = false});

  @override State<MarkAttendanceScreen> createState() => _MarkState();
}

class _MarkState extends State<MarkAttendanceScreen> {
  List<Student>     _students = [];
  Map<String, bool> _att      = {};
  bool _loading   = true;
  bool _submitted = false;

  @override
  void initState() { super.initState(); _loadStudents(); }

  Future<void> _loadStudents() async {
    final all = await widget.db.getStudentsBySection(
        widget.entry.section, widget.entry.year);
    final students = widget.entry.batch == 0
        ? all : all.where((s) => s.batch == widget.entry.batch).toList();
    Map<String, bool> existing = {};
    if (widget.alreadyMarked) {
      final recs = await widget.db.getSessionRecords(
          timetableEntryId: widget.entry.id, date: widget.sessionDate);
      existing = {for (final r in recs) r.studentId: r.isPresent};
    }
    if (!mounted) return;
    setState(() {
      _students = students;
      _att = {for (final s in students) s.id: existing[s.id] ?? true};
      _loading  = false;
    });
  }

  Future<void> _submit() async {
    if (widget.alreadyMarked) await widget.db.deleteSessionRecords(
        timetableEntryId: widget.entry.id, date: widget.sessionDate);
    final records = _students.map((s) => AttendanceRecord(
      id: widget.uuid.v4(), studentId: s.id,
      subjectId: widget.entry.subjectId, facultyId: widget.faculty.id,
      section: widget.entry.section, periodNumber: widget.entry.periodNumber,
      date: widget.sessionDate, isPresent: _att[s.id] ?? false,
      timetableEntryId: widget.entry.id, batch: widget.entry.batch,
      dayOfWeek: widget.entry.dayOfWeek)).toList();
    await widget.db.insertManyAttendance(records);
    setState(() => _submitted = true);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pres  = _att.values.where((v) => v).length;
    final total = _students.length;
    final d     = widget.sessionDate;

    final isMob = R.isMobile(context);

    // ── Shared info panel content ─────────────────────────────────────────
    final infoContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppTheme.cardAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border)),
            child: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 16))),
        const SizedBox(height: 18),
        Container(width: 44, height: 44,
          decoration: BoxDecoration(
            gradient: AppTheme.purpleGradient,
            borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.how_to_reg_rounded,
              color: Colors.white, size: 22)),
        const SizedBox(height: 12),
        Text(widget.subjectName, style: const TextStyle(
            color: AppTheme.textPrimary, fontSize: 16,
            fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        _infoRow(Icons.schedule_rounded, 'Period ${widget.entry.periodNumber}'),
        const SizedBox(height: 5),
        _infoRow(Icons.class_rounded, '${widget.entry.section} · Yr${widget.entry.year}'),
        const SizedBox(height: 5),
        _infoRow(Icons.calendar_today_rounded, '${d.day}/${d.month}/${d.year}'),
        if (widget.entry.batch > 0) ...[
          const SizedBox(height: 5),
          _infoRow(Icons.group_rounded, 'Batch ${widget.entry.batch}'),
        ],
        if (widget.alreadyMarked) ...[
          const SizedBox(height: 12),
          DsPill('Editing', color: AppTheme.amber, filled: true),
        ],
        const SizedBox(height: 16),
        // Stats card
        DsCard(elevated: true, padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(child: _stat2('Total',   '$total',              AppTheme.purple)),
            Expanded(child: _stat2('Present', '$pres',               AppTheme.emerald)),
            Expanded(child: _stat2('Absent',  '${total - pres}',     AppTheme.rose)),
            Expanded(child: _stat2('%',       total > 0
                ? '${(pres/total*100).toStringAsFixed(0)}%' : '–',  AppTheme.amber)),
          ])),
        const SizedBox(height: 12),
        // All/None buttons
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () => setState(() { for (final k in _att.keys) _att[k] = true; }),
            child: Container(height: 36, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.emerald.withOpacity(0.12),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppTheme.emerald.withOpacity(0.3))),
              child: const Text('All ✓', style: TextStyle(
                  color: AppTheme.emerald, fontWeight: FontWeight.w700, fontSize: 12))))),
          const SizedBox(width: 6),
          Expanded(child: GestureDetector(
            onTap: () => setState(() { for (final k in _att.keys) _att[k] = false; }),
            child: Container(height: 36, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.rose.withOpacity(0.10),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppTheme.rose.withOpacity(0.3))),
              child: const Text('All ✗', style: TextStyle(
                  color: AppTheme.rose, fontWeight: FontWeight.w700, fontSize: 12))))),
        ]),
        const SizedBox(height: 12),
        // Submit
        GestureDetector(
          onTap: _submitted ? null : _submit,
          child: Container(height: 46, alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppTheme.purpleGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(
                color: AppTheme.purple.withOpacity(0.35),
                blurRadius: 12, offset: const Offset(0, 4))]),
            child: Text(widget.alreadyMarked ? 'Update' : 'Submit',
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w800, fontSize: 14)))),
      ]);

    // ── Student list ──────────────────────────────────────────────────────
    final studentList = _loading ? const DsLoader()
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _students.length,
            itemBuilder: (ctx, i) {
              final s  = _students[i];
              final ok = _att[s.id] ?? false;
              return GestureDetector(
                onTap: () => setState(() => _att[s.id] = !ok),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: ok ? AppTheme.emerald.withOpacity(0.06) : AppTheme.surface,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                        color: ok ? AppTheme.emerald.withOpacity(0.3) : AppTheme.border)),
                  child: Row(children: [
                    Container(width: 36, height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ok ? AppTheme.emerald.withOpacity(0.12) : AppTheme.rose.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(9)),
                      child: Text(
                        s.rollNumber.length >= 2
                            ? s.rollNumber.substring(s.rollNumber.length - 2)
                            : s.rollNumber,
                        style: TextStyle(
                            color: ok ? AppTheme.emerald : AppTheme.rose,
                            fontWeight: FontWeight.w800, fontSize: 11))),
                    const SizedBox(width: 11),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700)),
                        Text(s.rollNumber, style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11)),
                      ])),
                    Container(width: 26, height: 26,
                      decoration: BoxDecoration(
                        color: ok ? AppTheme.emerald : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: ok ? AppTheme.emerald : AppTheme.border)),
                      child: ok ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 13) : null),
                  ]),
                ),
              );
            });

    // ── Mobile: stacked vertically with bottom-sheet-style header ────────
    if (isMob) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        body: SafeArea(child: Column(children: [
          // Compact header
          Container(
            color: AppTheme.sidebar,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: infoContent),
          // Student list fills rest
          Expanded(child: studentList),
        ])),
      );
    }

    // ── Desktop: original side-panel + list ──────────────────────────────
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Row(children: [
        Container(width: 260, color: AppTheme.sidebar,
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SingleChildScrollView(child: infoContent)),
            ])),
        Expanded(child: studentList),
      ]),
    );
  }

  Widget _infoRow(IconData ic, String txt) => Row(children: [
    Icon(ic, size: 13, color: AppTheme.textMuted),
    const SizedBox(width: 6),
    Text(txt, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
  ]);

  Widget _stat(String l, String v, Color c) => Row(children: [
    Expanded(child: Text(l, style: const TextStyle(
        color: AppTheme.textSecondary, fontSize: 12))),
    Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 14)),
  ]);

  Widget _stat2(String l, String v, Color c) => Column(children: [
    Text(v, style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w800)),
    Text(l, style: const TextStyle(color: AppTheme.textMuted, fontSize: 9.5)),
  ]);
}

// ── History Tab ──────────────────────────────────────────────────────────
class _HistoryTab extends StatefulWidget {
  final DatabaseService db; final Faculty faculty;
  final Map<String, String> subNames; final Uuid uuid;
  final VoidCallback onRefresh;
  const _HistoryTab({required this.db, required this.faculty,
      required this.subNames, required this.uuid, required this.onRefresh});
  @override State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final to = DateTime.now();
    final s  = await widget.db.getMarkedSessions(
        facultyId: widget.faculty.id,
        from: to.subtract(const Duration(days: 31)), to: to);
    if (mounted) setState(() { _sessions = s; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const DsLoader();
    if (_sessions.isEmpty) return const Center(
        child: Text('No records in the past month',
            style: TextStyle(color: AppTheme.textSecondary)));

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final s in _sessions)
      grouped.putIfAbsent(s['dateKey'] as String, () => []).add(s);
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: dates.length,
      itemBuilder: (ctx, di) {
        final dk   = dates[di];
        final sess = grouped[dk]!;
        final p    = dk.split('-');
        final dt   = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
        final now  = DateTime.now();
        final diff = DateTime(now.year, now.month, now.day)
            .difference(DateTime(dt.year, dt.month, dt.day)).inDays;
        final label = diff == 0 ? 'Today'
            : diff == 1 ? 'Yesterday'
            : '${dt.day}/${dt.month}/${dt.year}';

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  gradient: AppTheme.purpleGradient,
                  borderRadius: BorderRadius.circular(20)),
                child: Text(label, style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700,
                    fontSize: 11))),
              const SizedBox(width: 8),
              Text('${sess.length} session(s)',
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 12)),
            ])),
          ...sess.map((s) {
            final pres    = s['presentCount'] as int;
            final tot     = s['totalCount']   as int;
            final pct     = tot > 0 ? pres / tot * 100 : 0.0;
            final color   = pct >= 75 ? AppTheme.emerald
                : pct >= 50 ? AppTheme.amber : AppTheme.rose;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border)),
              child: Row(children: [
                Container(width: 44, height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12)),
                  child: Text('${pct.toStringAsFixed(0)}%',
                      style: TextStyle(color: color,
                          fontWeight: FontWeight.w800, fontSize: 11))),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.subNames[s['subjectId']] ?? '—',
                        style: const TextStyle(color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700)),
                    Text('P${s['periodNumber']}  ·  ${s['section']}'
                        '${(s['batch'] as int) > 0 ? " B${s['batch']}" : ""}'
                        '  ·  $pres/$tot',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11)),
                  ])),
                GestureDetector(
                  onTap: () async {
                    final entry = TimetableEntry(
                      id: s['timetableEntryId'] as String,
                      section: s['section'] as String,
                      year: 3, dayOfWeek: dt.weekday,
                      periodNumber: s['periodNumber'] as int,
                      subjectId: s['subjectId'] as String,
                      facultyId: widget.faculty.id,
                      isLab: false, batch: s['batch'] as int);
                    await Navigator.push(ctx, MaterialPageRoute(
                        builder: (_) => MarkAttendanceScreen(
                          entry: entry,
                          subjectName: widget.subNames[entry.subjectId]
                              ?? entry.subjectId,
                          db: widget.db, uuid: widget.uuid,
                          faculty: widget.faculty, sessionDate: dt,
                          alreadyMarked: true)));
                    _load();
                  },
                  child: DsPill('Edit', color: AppTheme.purple)),
              ]),
            );
          }),
        ]);
      },
    );
  }
}
