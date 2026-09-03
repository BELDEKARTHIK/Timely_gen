import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/excel_service.dart';
import '../../algorithms/timetable_scheduler.dart';
import '../../models/models.dart';
import '../../utils/app_theme.dart';
import '../../widgets/profile_dropdown.dart';
import '../../utils/responsive.dart';
import '../../widgets/timetable_grid.dart';
import 'import_tab.dart';
import 'data_management_screen.dart';
import '../../services/supabase_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ROOT SHELL
// ═══════════════════════════════════════════════════════════════════════════════
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {


  final _db         = DatabaseService();
  final _excel      = ExcelService();
  final _importKey  = GlobalKey<ImportTabState>();
  int _sel = 0;

  bool         _gen      = false;
  String       _msg      = '';
  bool         _ok       = true;
  List<String> _warn     = [];
  int _fc = 0, _sc = 0, _subc = 0, _ec = 0;

  // ── Generation mode & progress ─────────────────────────────────────────
  String  _genMode     = 'all';   // 'all' | 'year' | 'section'
  int     _genYear     = 1;       // selected year for year-wise / section mode
  String  _genSection  = '';      // selected section for section mode
  List<int>    _availYears    = [];  // years that have imported subjects
  List<String> _availSections = []; // sections for selected year
  double  _progress    = 0.0;     // 0.0 – 1.0
  String  _progressLbl = '';      // "Scheduling Section A Yr1…"
  int     _progressDone= 0;
  int     _progressTotal= 0;
  List<String> _satFallbackSections = []; // sections that fell back to Saturday

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final f   = await _db.getAllFaculty();
      final s   = await _db.getAllStudents();
      final sub = await _db.getAllSubjects();
      final t   = await _db.getAllTimetableEntries();
      final yrs = await _db.getDistinctYears();
      if (!mounted) return;
      final secs = await _db.getSectionsForYear(
          yrs.isNotEmpty ? _genYear : 1);
      setState(() {
        _fc = f.length; _sc = s.length;
        _subc = sub.length; _ec = t.length;
        _availYears = yrs;
        if (yrs.isNotEmpty && !yrs.contains(_genYear)) _genYear = yrs.first;
        _availSections = secs;
        if (secs.isNotEmpty && !secs.contains(_genSection)) _genSection = secs.first;
      });
  
    } catch (e) {
      debugPrint('admin _loadStats error: $e');
    }}

  Future<void> _generate() async {
    setState(() {
      _gen = true; _msg = ''; _warn = [];
      _progress = 0.0; _progressLbl = 'Loading subjects…';
      _progressDone = 0; _progressTotal = 0;
      _satFallbackSections = [];
    });

    try {
      // ── Load subjects based on mode ─────────────────────────────────────
      final List<Subject> subjects;
      final String modeLabel;
      if (_genMode == 'section') {
        subjects = await _db.getSubjectsBySection(_genSection, _genYear);
        modeLabel = 'Section $_genSection Year $_genYear';
        if (subjects.isEmpty) {
          setState(() { _gen = false;
            _msg = 'No subjects for Section $_genSection Year $_genYear. Check import.';
            _ok = false; });
          return;
        }
        await _db.clearTimetable(_genSection, _genYear);
      } else if (_genMode == 'year') {
        subjects = await _db.getSubjectsByYear(_genYear);
        modeLabel = 'Year $_genYear';
        if (subjects.isEmpty) {
          setState(() { _gen = false;
            _msg = 'No subjects found for Year $_genYear. Import data first.';
            _ok = false; });
          return;
        }
        await _db.clearTimetableByYear(_genYear);
      } else {
        subjects = await _db.getAllSubjects();
        modeLabel = 'All Years';
        if (subjects.isEmpty) {
          setState(() { _gen = false;
            _msg = 'No subjects found. Import data first.'; _ok = false; });
          return;
        }
        await _db.clearAllTimetables();
        await _db.clearAllSpecialSlots();
      }

      // ── Insert special slots — NPTEL day from section preference ──────────
      // Each section can specify its preferred NPTEL/Sports day in the
      // Preference column (e.g. "Wednesday"). P5-P7 on that day are reserved.
      // Fallback: Saturday if no valid preference found.
      final sectionYears = subjects.map((s) => '${s.section}_${s.year}').toSet();
      for (final sy in sectionYears) {
        final p   = sy.split('_');
        final sec = p[0];
        final yr  = int.parse(p[1]);

        // Find the preferred day for this section from any subject's preference
        // (all subjects in a section share the same preference for NPTEL day)
        final secSubjects = subjects.where(
            (s) => s.section == sec && s.year == yr).toList();

        // Try each subject until we find one with a valid preference day
        int? foundDay;
        String foundPref = '';
        for (final s in secSubjects) {
          final d = s.preferredNptelDay;
          if (d != null) {
            foundDay  = d;
            foundPref = s.preference.trim();
            break;
          }
        }
        final prefDay = foundDay ?? 6; // fallback: Saturday
        if (foundDay == null) _satFallbackSections.add('$sec Yr$yr');

        // Update progress label to show which day was picked
        if (mounted) setState(() {
          _progressLbl = 'Sec $sec Yr$yr: NPTEL → '
              '${foundPref.isNotEmpty ? foundPref : "Saturday (default)"}';
        });

        for (final e in [
          SpecialSlot(id:'${sy}_np5', section:sec, year:yr,
              dayOfWeek:prefDay, periodNumber:5, label:'NPTEL/Mentoring'),
          SpecialSlot(id:'${sy}_np6', section:sec, year:yr,
              dayOfWeek:prefDay, periodNumber:6, label:'Sports'),
          SpecialSlot(id:'${sy}_np7', section:sec, year:yr,
              dayOfWeek:prefDay, periodNumber:7, label:'Sports'),
        ]) { await _db.insertSpecialSlot(e); }
      }
      final specials = await _db.getAllSpecialSlots();

      // ── Detect sections sharing the same NPTEL day ─────────────────────
      final _dayToSecs = <int, List<String>>{};
      for (final sy in sectionYears) {
        final sp = sy.split('_');
        final secSubs = subjects.where(
            (sub) => sub.section == sp[0] && sub.year == int.parse(sp[1]));
        final d = secSubs.map((s) => s.preferredNptelDay)
            .firstWhere((x) => x != null, orElse: () => 6) ?? 6;
        _dayToSecs.putIfAbsent(d, () => []).add('${sp[0]} Yr${sp[1]}');
      }
      final _sharedDayWarns = <String>[];
      const _dayNames = ['','Mon','Tue','Wed','Thu','Fri','Sat'];
      _dayToSecs.forEach((d, secs) {
        if (secs.length > 1) {
          _sharedDayWarns.add(
            '${_dayNames[d]}: ${secs.join(", ")} share NPTEL day — '
            'P5–P7 blocked for all on ${_dayNames[d]}');
        }
      });

      // ── Section count info ──────────────────────────────────────────────
      final sectionCount = sectionYears.length;
      setState(() {
        _progressTotal = sectionCount;
        _progressLbl = 'Scheduling $sectionCount sections ($modeLabel)…';
      });

      // ── Run generator in background isolate (non-blocking UI) ──────────
      final result = await TimetableGenerator.generateAsync(
        subjects:     subjects,
        specialSlots: specials,
        onProgress:   (p) {
          if (!mounted) return;
          setState(() {
            _progress     = p.pct;
            _progressDone = p.done;
            _progressTotal= p.total;
            _progressLbl  = p.total == 0
                ? 'Scheduling…'
                : 'Section ${p.done}/${p.total}: ${p.current}';
          });
        },
      );

      if (!result.success) {
        await _loadStats();
        if (!mounted) return;
        setState(() {
          _gen = false; _progress = 0.0;
          _msg = 'Generation failed. See warnings below.'; _ok = false;
          _warn = result.conflicts;
        });
        return;
      }

      await _db.insertManyTimetableEntries(result.entries);
      SupabaseService().pushAll(); // sync timetable to cloud
      await _loadStats();
      if (!mounted) return;
      final satWarn = _satFallbackSections.isNotEmpty
          ? ' | ⚠ No preference set for: ${_satFallbackSections.join(", ")} — defaulted to Saturday'
          : '';
      setState(() {
        _gen = false; _progress = 1.0;
        _msg = '✓ Generated ${result.entries.length} slots for '
               '$sectionCount sections ($modeLabel)$satWarn';
        _ok = true; _warn = [];
      });

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gen = false; _progress = 0.0;
        _msg = 'Error: $e'; _ok = false;
      });
    }
  }

  // ── Delete timetable only (keep faculty/students/subjects) ─────────────────
  Future<void> _clearTimetable() async {
    if (_genMode == 'year') {
      await _db.clearTimetableByYear(_genYear);
    } else {
      await _db.clearAllTimetables();
      await _db.clearAllSpecialSlots();
    }
    await _loadStats();
    if (!mounted) return;
    final label = _genMode == 'year' ? 'Year $_genYear timetable' : 'All timetables';
    setState(() { _msg = '$label deleted. Ready to generate again.'; _ok = false; _warn = []; _progress = 0.0; });
  }

  // ── Full reset (wipe everything except admin login) ──────────────────────
  Future<void> _resetAll() async {
    await _db.resetAllData();
    await _loadStats();
    if (!mounted) return;
    setState(() { _msg = 'All data cleared. Import faculty & students to start fresh.'; _ok = false; _warn = []; });
  }

  void _goto(int i) {
    if (_sel == i) return;
    setState(() => _sel = i);
    if (i == 1) _importKey.currentState?.refresh();
    if (i == 2) _loadStats();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final name = auth.faculty?.name ?? 'Admin';

    // Only build the visible tab — avoids IndexedStack layout issues on Android
    final Widget tabContent;
    switch (_sel) {
      case 1:
        tabContent = ImportTab(key: _importKey);
        break;
      case 2:
        tabContent = _GenTab(
            onGen: _generate,
            onClear: _clearTimetable,
            onReset: _resetAll,
            onViewTimetable: () => _goto(3),
            running: _gen,
            msg: _msg, ok: _ok, warn: _warn,
            existingSlots: _ec,
            progress: _progress,
            progressLabel: _progressLbl,
            progressDone: _progressDone,
            progressTotal: _progressTotal,
            genMode: _genMode,
            genYear: _genYear,
            genSection: _genSection,
            availYears: _availYears,
            availSections: _availSections,
            onModeChanged: (m) => setState(() => _genMode = m),
            onYearChanged: (y) async {
              setState(() => _genYear = y);
              final secs = await _db.getSectionsForYear(y);
              if (!mounted) return;
              setState(() {
                _availSections = secs;
                _genSection = secs.isNotEmpty ? secs.first : '';
              });
            },
            onSectionChanged: (s) => setState(() => _genSection = s));
        break;
      case 3:
        tabContent = _TTTab(db: _db, excel: _excel);
        break;
      case 4:
        tabContent = const DataManagementScreen();
        break;
      default:
        tabContent = _HomeTab(
            fc: _fc, sc: _sc, subc: _subc, ec: _ec, onNav: _goto);
    }

    // ── Mobile layout ─────────────────────────────────────────────────────
    if (R.isMobile(context)) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: _MobileTopBar(name: name, onRefresh: _loadStats,
              onLogout: auth.logout)),
        body: tabContent,
        bottomNavigationBar: _AdminBottomNav(sel: _sel, onSelect: _goto),
      );
    }

    // ── Desktop layout ────────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Row(children: [
        _Sidebar(sel: _sel, name: name,
            onSelect: _goto, onLogout: auth.logout),
        Expanded(child: Column(children: [
          _TopBar(name: name, onRefresh: _loadStats),
          Expanded(child: tabContent),
        ])),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MOBILE TOP BAR  (admin)
// ═══════════════════════════════════════════════════════════════════════════════
class _MobileTopBar extends StatelessWidget {
  final String name;
  final VoidCallback onRefresh, onLogout;
  const _MobileTopBar({required this.name, required this.onRefresh, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final first = name.split(' ').first;
    return Container(
      color: AppTheme.sidebar,
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        left: 14, right: 14, bottom: 0),
      child: SizedBox(height: 54, child: Row(children: [
        Container(width: 28, height: 28,
          decoration: BoxDecoration(
            gradient: AppTheme.purpleGradient,
            borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.school_rounded, color: Colors.white, size: 14)),
        const SizedBox(width: 8),
        Column(mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hi, $first! 👋', style: const TextStyle(
            color: AppTheme.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w800)),
          const Text('Admin Dashboard', style: TextStyle(
            color: AppTheme.textSecondary, fontSize: 10)),
        ]),
        const Spacer(),
        GestureDetector(
          onTap: onRefresh,
          child: Container(width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppTheme.cardAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border)),
            child: const Icon(Icons.refresh_rounded,
                color: AppTheme.textSecondary, size: 15))),
        const SizedBox(width: 6),
        Builder(builder: (ctx) {
          final auth = ctx.read<AuthService>();
          final f = auth.faculty;
          if (f == null) return const SizedBox.shrink();
          return ProfileDropdown(
            compact:  true,
            name:     f.name,
            subtitle: f.isAdmin ? 'Administrator' : 'Faculty',
            gradient: AppTheme.purpleGradient,
            details: [
              ('Name',  f.name),
              ('Email', f.email),
              ('Role',  f.isAdmin ? 'Administrator' : 'Faculty'),
            ],
            onChangePassword: () => _showAdminChangePasswordDialog(ctx),
            onLogout: auth.logout,
          );
        }),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: onLogout,
          child: Container(width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.error.withOpacity(0.25))),
            child: const Icon(Icons.logout_rounded,
                color: AppTheme.error, size: 14))),
      ])),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADMIN BOTTOM NAV
// ═══════════════════════════════════════════════════════════════════════════════
class _AdminBottomNav extends StatelessWidget {
  final int sel;
  final void Function(int) onSelect;
  static const _items = [
    (Icons.dashboard_rounded,    'Dashboard'),
    (Icons.upload_file_rounded,  'Import'),
    (Icons.auto_awesome_rounded, 'Generate'),
    (Icons.grid_view_rounded,    'Timetable'),
    (Icons.archive_outlined,     'Archive'),
  ];
  const _AdminBottomNav({required this.sel, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.sidebar,
        border: Border(top: BorderSide(color: AppTheme.border))),
      child: SafeArea(
        top: false,
        child: SizedBox(height: 58,
          child: Row(children: _items.asMap().entries.map((e) {
            final active = sel == e.key;
            return Expanded(child: _AdminBotItem(
              icon: e.value.$1, label: e.value.$2,
              active: active, onTap: () => onSelect(e.key)));
          }).toList()),
        ),
      ),
    );
  }
}

class _AdminBotItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _AdminBotItem({required this.icon, required this.label,
      required this.active, required this.onTap});
  @override State<_AdminBotItem> createState() => _AdminBotItemState();
}

class _AdminBotItemState extends State<_AdminBotItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ac   = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 220));
    _anim = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    if (widget.active) _ac.value = 1.0;
  }

  @override
  void didUpdateWidget(_AdminBotItem old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      widget.active ? _ac.forward() : _ac.reverse();
    }
  }

  @override void dispose() { _ac.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: widget.active
                    ? AppTheme.primary.withOpacity(0.15 * _anim.value + 0.01)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20)),
              child: Icon(widget.icon, size: 20,
                color: widget.active ? AppTheme.primaryLt : AppTheme.textMuted)),
            const SizedBox(height: 2),
            Text(widget.label, style: TextStyle(
              color: widget.active ? AppTheme.primaryLt : AppTheme.textMuted,
              fontSize: 9.5,
              fontWeight: widget.active ? FontWeight.w700 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SIDEBAR — animated nav tiles, hover glow, active indicator
// ═══════════════════════════════════════════════════════════════════════════════
class _Sidebar extends StatelessWidget {
  final int sel;
  final String name;
  final void Function(int) onSelect;
  final VoidCallback onLogout;

  static const _items = [
    (Icons.dashboard_rounded,    'Dashboard'),
    (Icons.upload_file_rounded,  'Import Data'),
    (Icons.auto_awesome_rounded, 'Generate'),
    (Icons.grid_view_rounded,    'Timetable'),
    (Icons.archive_outlined,     'Archive'),
  ];

  const _Sidebar({required this.sel, required this.name,
      required this.onSelect, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 214,
      color: AppTheme.sidebar,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Logo ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                gradient: AppTheme.purpleGradient,
                borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.school_rounded,
                  color: Colors.white, size: 15)),
            const SizedBox(width: 10),
            const Text('TimeTable', style: TextStyle(
              color: AppTheme.textPrimary, fontSize: 13.5,
              fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          ])),
        Container(height: 1, color: AppTheme.border),
        const SizedBox(height: 10),

        // ── Section label ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
          child: Text('GENERAL', style: TextStyle(
            color: AppTheme.textMuted, fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 1.4))),

        // ── Nav items ─────────────────────────────────────────────────────
        ..._items.asMap().entries.map((e) => _NavTile(
          icon: e.value.$1, label: e.value.$2,
          active: sel == e.key, onTap: () => onSelect(e.key))),

        const Spacer(),
        Container(height: 1, color: AppTheme.border),
        const SizedBox(height: 6),

        // ── Role indicator ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
          child: Text('ROLE', style: TextStyle(
            color: AppTheme.textMuted, fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 1.4))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
          child: Row(children: [
            Container(width: 6, height: 6,
              decoration: const BoxDecoration(
                color: AppTheme.primary, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            const Text('Administrator', style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11.5, fontWeight: FontWeight.w500)),
          ])),

        // ── Logout ────────────────────────────────────────────────────────
        _NavTile(
          icon: Icons.logout_rounded, label: 'Logout',
          active: false, onTap: onLogout, danger: true),
        const SizedBox(height: 12),
      ]),
    );
  }
}

// Animated sidebar tile — smooth bg + scale on press
class _NavTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool danger;
  const _NavTile({required this.icon, required this.label,
      required this.active, required this.onTap, this.danger = false});
  @override State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double>   _bg;
  bool _hov = false;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _bg = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    if (widget.active) _ac.value = 1.0;
  }

  @override
  void didUpdateWidget(_NavTile old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      widget.active ? _ac.forward() : _ac.reverse();
    }
  }

  @override void dispose() { _ac.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _bg,
          builder: (_, __) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: widget.active
                  ? AppTheme.primary.withOpacity(0.13)
                  : _hov
                      ? AppTheme.primary.withOpacity(0.07)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: widget.active
                    ? AppTheme.primary.withOpacity(0.30 * _bg.value)
                    : Colors.transparent)),
            child: Row(children: [
              // Icon box
              Container(
                width: 27, height: 27,
                decoration: BoxDecoration(
                  color: widget.active
                      ? AppTheme.primary.withOpacity(0.22)
                      : widget.danger
                          ? AppTheme.error.withOpacity(0.11)
                          : _hov
                              ? AppTheme.primary.withOpacity(0.12)
                              : AppTheme.cardAlt,
                  borderRadius: BorderRadius.circular(7)),
                child: Icon(widget.icon, size: 13,
                  color: widget.active
                      ? AppTheme.primaryLt
                      : widget.danger
                          ? AppTheme.error
                          : _hov
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary)),
              const SizedBox(width: 10),
              // Label
              Expanded(child: Text(widget.label,
                style: TextStyle(
                  color: widget.active
                      ? AppTheme.textPrimary
                      : widget.danger
                          ? AppTheme.error
                          : _hov
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                  fontSize: 12.5,
                  fontWeight: widget.active
                      ? FontWeight.w700 : FontWeight.w500))),
              // Active dot
              if (widget.active)
                Container(
                  width: 5, height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLt.withOpacity(_bg.value),
                    shape: BoxShape.circle)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TOP BAR
// ═══════════════════════════════════════════════════════════════════════════════
class _TopBar extends StatelessWidget {
  final String name;
  final VoidCallback onRefresh;
  const _TopBar({required this.name, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final first   = name.split(' ').first;
    final auth    = context.watch<AuthService>();
    final faculty = auth.faculty;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.sidebar,
        border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: Row(children: [
        // Greeting
        Column(mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hi, $first! 👋', style: const TextStyle(
            color: AppTheme.textPrimary, fontSize: 16,
            fontWeight: FontWeight.w800)),
          const Text('Dashboard overview', style: TextStyle(
            color: AppTheme.textSecondary, fontSize: 10.5)),
        ]),
        const Spacer(),
        // Search
        Container(width: 180, height: 30,
          decoration: BoxDecoration(
            color: AppTheme.cardAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border)),
          child: const Row(children: [
            SizedBox(width: 9),
            Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 13),
            SizedBox(width: 6),
            Text('Search...', style: TextStyle(
              color: AppTheme.textMuted, fontSize: 11.5)),
          ])),
        const SizedBox(width: 8),
        _IBtn(icon: Icons.refresh_rounded, onTap: onRefresh),
        const SizedBox(width: 5),
        _IBtn(icon: Icons.notifications_none_rounded),
        const SizedBox(width: 10),
        // Profile dropdown
        if (faculty != null)
          Builder(builder: (ctx) => ProfileDropdown(
            name:     faculty.name,
            subtitle: faculty.isAdmin
                ? 'Administrator'
                : 'Employee ID: ${faculty.employeeId}',
            gradient: AppTheme.purpleGradient,
            details:  faculty.isAdmin
                ? [
                    ('Name',  faculty.name),
                    ('Email', faculty.email),
                    ('Role',  'Administrator'),
                  ]
                : [
                    ('Name',        faculty.name),
                    ('Employee ID', faculty.employeeId),
                    ('Email',       faculty.email),
                    ('Role',        'Faculty'),
                  ],
            onChangePassword: () => _showAdminChangePasswordDialog(ctx),
            onLogout: auth.logout,
          ))
        else
          Container(width: 30, height: 30,
            decoration: BoxDecoration(
              gradient: AppTheme.purpleGradient,
              borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'A',
              style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w800, fontSize: 12)))),
      ]),
    );
  }
}

class _IBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _IBtn({required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(width: 30, height: 30,
      decoration: BoxDecoration(
        color: AppTheme.cardAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border)),
      child: Icon(icon, color: AppTheme.textSecondary, size: 14)));
}

// ═══════════════════════════════════════════════════════════════════════════════
// HOME TAB  — fits entirely in viewport, no scroll needed
// Uses LayoutBuilder so every section gets its exact proportional slice.
// ALL stat cards are wrapped in SelectionContainer.disabled + IgnorePointer
// so they can never be tapped, dragged or text-selected.
// ═══════════════════════════════════════════════════════════════════════════════
class _HomeTab extends StatefulWidget {
  final int fc, sc, subc, ec;
  final void Function(int) onNav;
  const _HomeTab({required this.fc, required this.sc,
      required this.subc, required this.ec, required this.onNav});
  @override State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  @override
  Widget build(BuildContext context) {
    final isMob = R.isMobile(context);

    // ── Mobile: safe scrollable layout (no Expanded in unbounded contexts) ──
    if (isMob) {
      return ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // Stat row 1
          IntrinsicHeight(child: Row(children: [
            Expanded(child: _StatCard(
              value: '${widget.fc}', label: 'Faculty',
              icon: Icons.people_alt_rounded,
              gradient: AppTheme.purpleGradient, progress: 0.72)),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(
              value: '${widget.sc}', label: 'Students',
              icon: Icons.school_rounded,
              gradient: AppTheme.orangeGradient, progress: 0.85)),
          ])),
          const SizedBox(height: 10),
          // Stat row 2
          IntrinsicHeight(child: Row(children: [
            Expanded(child: _StatCard(
              value: '${widget.subc}', label: 'Subjects',
              icon: Icons.book_rounded,
              gradient: AppTheme.cyanGradient,
              progress: (widget.subc / 40.0).clamp(0.0, 1.0))),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(
              value: '${widget.ec}', label: 'Slots',
              icon: Icons.calendar_month_rounded,
              gradient: AppTheme.greenGradient,
              progress: (widget.ec / 300.0).clamp(0.0, 1.0))),
          ])),
          const SizedBox(height: 14),
          // Quick actions — simple vertical list (no Expanded needed)
          _MobileActionsCard(onNav: widget.onNav),
          const SizedBox(height: 14),
          // Stats panel
          _StatsPanel(subc: widget.subc, ec: widget.ec),
          const SizedBox(height: 14),
          // Calendar
          const SizedBox(height: 240, child: _CalCard()),
          const SizedBox(height: 14),
        ],
      );
    }

    // ── Desktop: two-row layout ──────────────────────────────────────────
    return LayoutBuilder(builder: (ctx, box) {
      final row1H = (box.maxHeight * 0.22).clamp(100.0, 130.0);
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // Row 1 — stat cards
          SizedBox(
            height: row1H,
            child: Row(children: [
              Expanded(child: _StatCard(
                value: '${widget.fc}', label: 'Faculty Members',
                icon: Icons.people_alt_rounded,
                gradient: AppTheme.purpleGradient, progress: 0.72)),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                value: '${widget.sc}', label: 'Students Enrolled',
                icon: Icons.school_rounded,
                gradient: AppTheme.orangeGradient, progress: 0.85)),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                value: '${widget.subc}', label: 'Active Subjects',
                icon: Icons.book_rounded,
                gradient: AppTheme.cyanGradient,
                progress: (widget.subc / 40.0).clamp(0.0, 1.0))),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                value: '${widget.ec}', label: 'Schedule Slots',
                icon: Icons.calendar_month_rounded,
                gradient: AppTheme.greenGradient,
                progress: (widget.ec / 300.0).clamp(0.0, 1.0))),
            ]),
          ),
          const SizedBox(height: 12),
          // Row 2 — actions + stats + calendar
          Expanded(child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 11, child: _ActionsCard(onNav: widget.onNav)),
              const SizedBox(width: 12),
              Expanded(flex: 5, child: Column(children: [
                _StatsPanel(subc: widget.subc, ec: widget.ec),
                const SizedBox(height: 12),
                const Expanded(child: _CalCard()),
              ])),
            ],
          )),
        ]),
      );
    });
  }
}

// ── STAT CARD — completely non-interactive (no select, no tap, no hover) ──────
class _StatCard extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final LinearGradient gradient;
  final double progress;
  const _StatCard({required this.value, required this.label,
      required this.icon, required this.gradient, required this.progress});

  @override
  Widget build(BuildContext context) {
    // IgnorePointer   → mouse/touch events pass through (no hover cursor)
    // SelectionContainer.disabled → text inside cannot be selected
    return IgnorePointer(
      child: SelectionContainer.disabled(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
              color: gradient.colors.first.withOpacity(0.28),
              blurRadius: 14, offset: const Offset(0, 5))]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top row: icon + trend
              Row(children: [
                Container(width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: Colors.white, size: 15)),
                const Spacer(),
                Icon(Icons.trending_up_rounded,
                  color: Colors.white.withOpacity(0.50), size: 14),
              ]),
              const SizedBox(height: 10),
              // Value
              Text(value, style: const TextStyle(
                color: Colors.white, fontSize: 24,
                fontWeight: FontWeight.w800, height: 1.1)),
              const SizedBox(height: 2),
              // Label
              Text(label, style: TextStyle(
                color: Colors.white.withOpacity(0.70), fontSize: 10.5)),
              const SizedBox(height: 8),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress, minHeight: 3,
                  backgroundColor: Colors.white.withOpacity(0.20),
                  valueColor: const AlwaysStoppedAnimation(Colors.white))),
            ],
          ),
        ),
      ),
    );
  }
}

// ── ACTIONS CARD — 2×2 grid of tappable navigation cards ─────────────────────
// ── Mobile Actions Card — vertical list, no Expanded needed ─────────────────
class _MobileActionsCard extends StatelessWidget {
  final void Function(int) onNav;
  const _MobileActionsCard({required this.onNav});

  static const _data = [
    (Icons.upload_file_rounded,  'Import Data',         'Upload faculty & student Excel files',  1),
    (Icons.auto_awesome_rounded, 'Generate Timetable',  'Auto-schedule all sections',             2),
    (Icons.grid_view_rounded,    'View Timetable',      'Browse the generated schedule',          3),
    (Icons.bar_chart_rounded,    'Attendance Reports',  'View section-wise attendance',           0),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Quick Actions', style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ..._data.map((d) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => onNav(d.$4),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.cardAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border)),
                child: Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8)),
                    child: Icon(d.$1,
                      color: AppTheme.primaryLt, size: 15)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d.$2, style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(d.$3, style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 10.5)),
                    ])),
                  const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted, size: 16),
                ]),
              ))),
          ),
        ],
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  final void Function(int) onNav;
  const _ActionsCard({required this.onNav});

  // (icon, title, subtitle, badge, tabIndex, featured)
  static const _data = [
    (Icons.upload_file_rounded,  'Import Data',
     'Upload faculty & student Excel files',  'Step 1', 1, false),
    (Icons.auto_awesome_rounded, 'Generate Timetable',
     'Auto-schedule with conflict detection', 'Step 2', 2, true),
    (Icons.grid_view_rounded,    'View Timetable',
     'Browse & export class schedules',       'View',   3, false),
    (Icons.bar_chart_rounded,    'Attendance',
     'Section-wise attendance analytics',     'Reports',3, false),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          const Text('Quick Actions', style: TextStyle(
            color: AppTheme.textPrimary, fontSize: 13,
            fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20)),
            child: const Text('All tabs', style: TextStyle(
              color: AppTheme.primaryLt,
              fontSize: 10, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 10),
        // 2×2 grid — each row Expanded so they fill remaining height equally
        Expanded(child: Column(children: [
          Expanded(child: Row(children: [
            Expanded(child: _ACard(d: _data[0], onNav: onNav)),
            const SizedBox(width: 9),
            Expanded(child: _ACard(d: _data[1], onNav: onNav)),
          ])),
          const SizedBox(height: 9),
          Expanded(child: Row(children: [
            Expanded(child: _ACard(d: _data[2], onNav: onNav)),
            const SizedBox(width: 9),
            Expanded(child: _ACard(d: _data[3], onNav: onNav)),
          ])),
        ])),
      ]),
    );
  }
}

// Animated action card: hover glow border + press scale
class _ACard extends StatefulWidget {
  final (IconData, String, String, String, int, bool) d;
  final void Function(int) onNav;
  const _ACard({required this.d, required this.onNav});
  @override State<_ACard> createState() => _ACardState();
}

class _ACardState extends State<_ACard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double>   _sc;
  bool _hov = false;

  static const _grads = [
    null, // placeholder
  ];

  LinearGradient _gradFor(int idx) => [
    AppTheme.purpleGradient, AppTheme.orangeGradient,
    AppTheme.cyanGradient,   AppTheme.greenGradient,
  ][idx.clamp(0, 3)];

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _sc = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
  }
  @override void dispose() { _ac.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final (icon, title, sub, badge, navIdx, featured) = widget.d;
    // Map navIdx to gradient index: 1→0, 2→1, 3→2 or 3
    final gradIdx = navIdx == 1 ? 0 : navIdx == 2 ? 1 : 2;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTapDown:   (_) => _ac.forward(),
        onTapUp:     (_) { _ac.reverse(); widget.onNav(navIdx); },
        onTapCancel: ()  => _ac.reverse(),
        child: ScaleTransition(
          scale: _sc,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              // featured card gets gradient bg, others get plain dark bg
              gradient: featured ? AppTheme.purpleGradient : null,
              color: featured ? null
                  : _hov ? AppTheme.cardAlt : AppTheme.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: featured
                    ? Colors.transparent
                    : _hov
                        ? AppTheme.primary.withOpacity(0.40)
                        : AppTheme.border),
              boxShadow: _hov && !featured
                  ? [BoxShadow(
                      color: AppTheme.primary.withOpacity(0.14),
                      blurRadius: 10, offset: const Offset(0, 3))]
                  : featured
                      ? [BoxShadow(
                          color: AppTheme.primary.withOpacity(0.30),
                          blurRadius: 14, offset: const Offset(0, 4))]
                      : null),
            // SelectionContainer.disabled prevents any text drag-selection
            child: SelectionContainer.disabled(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    // Badge pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: featured
                            ? Colors.white.withOpacity(0.20)
                            : AppTheme.primary.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(20)),
                      child: Text(badge, style: TextStyle(
                        color: featured
                            ? Colors.white : AppTheme.primaryLt,
                        fontSize: 8, fontWeight: FontWeight.w700))),
                    const Spacer(),
                    // Icon box
                    Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        gradient: featured ? null : _gradFor(gradIdx),
                        color: featured
                            ? Colors.white.withOpacity(0.22) : null,
                        borderRadius: BorderRadius.circular(7)),
                      child: Icon(icon, color: Colors.white, size: 13)),
                  ]),
                  const SizedBox(height: 8),
                  Text(title,
                    style: TextStyle(
                      color: featured
                          ? Colors.white : AppTheme.textPrimary,
                      fontSize: 11.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Expanded(child: Text(sub,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: featured
                          ? Colors.white.withOpacity(0.62)
                          : AppTheme.textSecondary,
                      fontSize: 10, height: 1.4))),
                  // "Open →" link
                  Row(children: [
                    Text('Open', style: TextStyle(
                      color: featured ? Colors.white : AppTheme.primaryLt,
                      fontSize: 10, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 3),
                    Icon(Icons.arrow_forward_rounded,
                      color: featured ? Colors.white : AppTheme.primaryLt,
                      size: 10),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── STATS PANEL ───────────────────────────────────────────────────────────────
class _StatsPanel extends StatelessWidget {
  final int subc, ec;
  const _StatsPanel({required this.subc, required this.ec});

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Text('Schedule Stats', style: TextStyle(
              color: AppTheme.textPrimary, fontSize: 11.5,
              fontWeight: FontWeight.w700)),
            Spacer(),
            Icon(Icons.more_horiz_rounded,
              color: AppTheme.textMuted, size: 15),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _dot(AppTheme.purpleGradient),
            const SizedBox(width: 6),
            _dot(AppTheme.orangeGradient),
            const SizedBox(width: 6),
            _dot(AppTheme.cyanGradient),
            const SizedBox(width: 6),
            _dot(AppTheme.greenGradient),
          ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            _mini('Subjects', '$subc',  AppTheme.primaryLt),
            _mini('Days',     '6',      AppTheme.secondary),
            _mini('Periods',  '7',      AppTheme.cyan),
            _mini('Slots',    '$ec',    AppTheme.emerald),
          ]),
        ]),
      ),
    );
  }

  static Widget _dot(LinearGradient g) => Container(
    width: 16, height: 16,
    decoration: BoxDecoration(gradient: g, shape: BoxShape.circle));

  static Widget _mini(String l, String v, Color c) =>
    Column(children: [
      Text(v, style: TextStyle(color: c, fontSize: 13,
          fontWeight: FontWeight.w800)),
      Text(l, style: const TextStyle(
          color: AppTheme.textMuted, fontSize: 9)),
    ]);
}

// ── CALENDAR CARD ─────────────────────────────────────────────────────────────
class _CalCard extends StatelessWidget {
  const _CalCard();

  static const _days  = ['S','M','T','W','T','F','S'];
  static const _months= ['Jan','Feb','Mar','Apr','May','Jun',
                          'Jul','Aug','Sep','Oct','Nov','Dec'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final fd  = DateTime(now.year, now.month, 1);
    final off = fd.weekday % 7;
    final dim = DateUtils.getDaysInMonth(now.year, now.month);

    return SelectionContainer.disabled(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Header
          Row(children: [
            Text('${_months[now.month-1]} ${now.year}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textPrimary, fontSize: 11.5,
                fontWeight: FontWeight.w700)),
            const Spacer(),
            _cBtn(Icons.chevron_left_rounded),
            const SizedBox(width: 3),
            _cBtn(Icons.chevron_right_rounded),
          ]),
          const SizedBox(height: 8),
          // Day-of-week headers
          Row(children: _days.map((d) => Expanded(child: Center(
            child: Text(d, style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 9, fontWeight: FontWeight.w700))))).toList()),
          const SizedBox(height: 4),
          // Calendar grid — 5 weeks × 24px rows
          ...List.generate(5, (w) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: List.generate(7, (d) {
                final n = w * 7 + d - off + 1;
                final ok = n >= 1 && n <= dim;
                final today = ok && n == now.day;
                return Expanded(child: Center(
                  child: !ok
                    ? const SizedBox(width: 20, height: 20)
                    : Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          color: today
                              ? AppTheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(5)),
                        child: Center(child: Text('$n',
                          style: TextStyle(
                            color: today
                                ? Colors.white
                                : AppTheme.textSecondary,
                            fontSize: 9.5,
                            fontWeight: today
                                ? FontWeight.w800 : FontWeight.w400))))));
              })))),
        ]),
      ),
    );
  }

  static Widget _cBtn(IconData i) => Container(
    width: 20, height: 20,
    decoration: BoxDecoration(
      color: AppTheme.cardAlt,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: AppTheme.border)),
    child: Icon(i, size: 12, color: AppTheme.textSecondary));
}

// ═══════════════════════════════════════════════════════════════════════════════
// GENERATE TAB
// ═══════════════════════════════════════════════════════════════════════════════
class _GenTab extends StatelessWidget {
  final VoidCallback  onGen;
  final VoidCallback  onClear;
  final VoidCallback  onReset;
  final VoidCallback? onViewTimetable;
  final bool          running;
  final String        msg;
  final bool          ok;
  final List<String>  warn;
  final int           existingSlots;
  final double        progress;
  final String        progressLabel;
  final int           progressDone;
  final int           progressTotal;
  final String        genMode;
  final int           genYear;
  final String        genSection;
  final List<int>     availYears;
  final List<String>  availSections;
  final void Function(String)          onModeChanged;
  final void Function(int)             onYearChanged;
  final void Function(String)          onSectionChanged;

  const _GenTab({
    required this.onGen,
    required this.onClear,
    required this.onReset,
    this.onViewTimetable,
    required this.running,
    required this.msg,
    required this.ok,
    required this.warn,
    required this.existingSlots,
    required this.progress,
    required this.progressLabel,
    required this.progressDone,
    required this.progressTotal,
    required this.genMode,
    required this.genYear,
    required this.genSection,
    required this.availYears,
    required this.availSections,
    required this.onModeChanged,
    required this.onYearChanged,
    required this.onSectionChanged,
  });

  static Future<bool> _confirm(BuildContext ctx, String title, String body) async {
    final r = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border)),
        title: Text(title, style: const TextStyle(
          color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(body, style: const TextStyle(
          color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel',
              style: TextStyle(color: AppTheme.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirm',
              style: TextStyle(color: AppTheme.rose, fontWeight: FontWeight.w700))),
        ]));
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isMob = R.isMobile(context);
    final hasTimetable = existingSlots > 0;
    final isYearMode   = genMode == 'year' || genMode == 'section';
    final yearsForPicker = availYears.isEmpty ? [1,2,3,4] : availYears;

    // ── Mode selector ───────────────────────────────────────────────────────
    Widget modeSelector = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 30, height: 30,
            decoration: BoxDecoration(
              gradient: AppTheme.purpleGradient,
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.tune_rounded, color: Colors.white, size: 14)),
          const SizedBox(width: 9),
          const Text('Generation Mode', style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
        const SizedBox(height: 12),

        // Mode toggle: All | Year-wise | Section
        Row(children: [
          Expanded(child: _ModeBtn(
            label: 'All',
            subtitle: 'All years at once',
            icon: Icons.grid_view_rounded,
            selected: genMode == 'all',
            onTap: running ? null : () => onModeChanged('all'),
          )),
          const SizedBox(width: 6),
          Expanded(child: _ModeBtn(
            label: 'Year',
            subtitle: 'One year at a time',
            icon: Icons.school_rounded,
            selected: genMode == 'year',
            onTap: running ? null : () => onModeChanged('year'),
          )),
          const SizedBox(width: 6),
          Expanded(child: _ModeBtn(
            label: 'Section',
            subtitle: 'One section only',
            icon: Icons.class_rounded,
            selected: genMode == 'section',
            onTap: running ? null : () => onModeChanged('section'),
          )),
        ]),

        // Year + Section pickers (year/section mode)
        if (genMode == 'year' || genMode == 'section') ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.cardAlt,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppTheme.primary.withOpacity(0.3))),
            child: Row(children: [
              const Icon(Icons.calendar_today_rounded,
                color: AppTheme.primaryLt, size: 14),
              const SizedBox(width: 10),
              const Text('Select Year:', style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 12)),
              const Spacer(),
              DropdownButtonHideUnderline(child: DropdownButton<int>(
                value: yearsForPicker.contains(genYear) ? genYear : yearsForPicker.first,
                dropdownColor: AppTheme.card,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700, fontSize: 13),
                items: yearsForPicker.map((y) => DropdownMenuItem(
                  value: y,
                  child: Text('Year $y'),
                )).toList(),
                onChanged: running ? null : (v) { if (v != null) onYearChanged(v); },
              )),
            ])),

          // Section picker — only in section mode
          if (genMode == 'section') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.cardAlt,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppTheme.primary.withOpacity(0.3))),
              child: Row(children: [
                const Icon(Icons.class_rounded,
                  color: AppTheme.primaryLt, size: 14),
                const SizedBox(width: 10),
                const Text('Select Section:', style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
                const Spacer(),
                DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: availSections.contains(genSection)
                      ? genSection : null,
                  hint: const Text('—',
                      style: TextStyle(color: AppTheme.textMuted)),
                  dropdownColor: AppTheme.card,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700, fontSize: 13),
                  items: availSections.map((s) => DropdownMenuItem(
                    value: s,
                    child: Text('Section $s'))).toList(),
                  onChanged: running
                      ? null
                      : (v) { if (v != null) onSectionChanged(v); },
                )),
              ])),
          ],

          // Cross-year + preference notes
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.emerald.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.emerald.withOpacity(0.22))),
            child: Row(children: [
              const Icon(Icons.verified_rounded,
                color: AppTheme.emerald, size: 13),
              const SizedBox(width: 8),
              const Expanded(child: Text(
                'Faculty conflicts checked across all years. '
                'A faculty teaching Year 1 and Year 3 will never be double-booked.',
                style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 10.5, height: 1.4))),
            ])),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.amber.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.amber.withOpacity(0.22))),
            child: Row(children: [
              const Icon(Icons.calendar_today_rounded,
                color: AppTheme.amber, size: 13),
              const SizedBox(width: 8),
              const Expanded(child: Text(
                'NPTEL/Sports day (P5–P7) is read from the Preference column in your '
                'Excel file. Each section can have a different day.',
                style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 10.5, height: 1.4))),
            ])),
        ],

        // All-mode summary
        if (!isYearMode && availYears.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.primary.withOpacity(0.22))),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                color: AppTheme.primaryLt, size: 13),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Generating ${availYears.length} year(s): '
                'Year ${availYears.join(", Year ")}. '
                'All sections scheduled simultaneously with global conflict checking.',
                style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 10.5, height: 1.4))),
            ])),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.amber.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.amber.withOpacity(0.22))),
            child: const Row(children: [
              Icon(Icons.calendar_today_rounded, color: AppTheme.amber, size: 13),
              SizedBox(width: 8),
              Expanded(child: Text(
                "Each section's NPTEL/Sports day (P5–P7) is set by the Preference "
                "column in your Excel. Different sections can choose different days.",
                style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 10.5, height: 1.4))),
            ])),
        ],
      ]));

    // ── Constraints card ────────────────────────────────────────────────────
    final constraints = [
      'No faculty double-booking (global, cross-year)',
      'No section slot conflicts',
      'Max 2 periods / subject / day',
      'No consecutive same subject',
      'Lab = 3 consecutive periods (P2–P4 or P5–P7)',
      'Only one lab session per section per day',
      'Split batch B1+B2 always different subjects',
      'Mon–Sat  •  7 periods / day',
      'P5–P7 reserved on section\'s preferred NPTEL day',
      'Runs in background — UI stays responsive',
    ];

    Widget controlsCard = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 30, height: 30,
            decoration: BoxDecoration(
              gradient: AppTheme.cyanGradient,
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.checklist_rounded, color: Colors.white, size: 14)),
          const SizedBox(width: 9),
          const Text('Constraints', style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: constraints.map(_chip).toList()),
        const SizedBox(height: 12),

        // Generate / locked button
        running
          ? _buildProgressWidget()
          : hasTimetable
            ? _buildLockedBtn(isYearMode, genYear)
            : _GBtn(
                label: isYearMode
                    ? 'Generate Timetable — Year $genYear'
                    : 'Generate All Timetables',
                icon: Icons.auto_awesome_rounded,
                onTap: onGen),

        const SizedBox(height: 8),

        // Delete + Reset row
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: hasTimetable ? () async {
              final label = isYearMode
                  ? 'Year $genYear timetable ($existingSlots slots)'
                  : 'all timetable slots ($existingSlots slots)';
              final confirmed = await _confirm(context,
                'Delete Timetable',
                'Delete $label?\n\n'
                'Faculty, student, and subject data will NOT be deleted.\n'
                'You can generate a new timetable immediately after.');
              if (confirmed) onClear();
            } : null,
            child: _actionBtn(
              label: isYearMode ? 'Delete Yr $genYear' : 'Delete Timetable',
              icon: Icons.delete_outline_rounded,
              color: AppTheme.rose,
              enabled: hasTimetable))),
          const SizedBox(width: 8),
          Expanded(child: GestureDetector(
            onTap: () async {
              final confirmed = await _confirm(context,
                'Reset All Data',
                'Permanently delete:\n'
                '• All timetable slots\n'
                '• All subjects\n'
                '• All students\n'
                '• All faculty (except Admin)\n'
                '• All attendance records\n\n'
                'Admin login is preserved.\nThis cannot be undone.');
              if (confirmed) onReset();
            },
            child: _actionBtn(
              label: 'Reset All',
              icon: Icons.warning_amber_rounded,
              color: AppTheme.error,
              enabled: true))),
        ]),
      ]));

    // ── Status card ─────────────────────────────────────────────────────────
    Widget statusCard = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 30, height: 30,
            decoration: BoxDecoration(
              gradient: AppTheme.orangeGradient,
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.info_outline_rounded,
              color: Colors.white, size: 14)),
          const SizedBox(width: 9),
          const Text('Status', style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 13)),
          const Spacer(),
          if (hasTimetable)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.emerald.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.emerald.withOpacity(0.3))),
              child: Text('$existingSlots slots',
                style: const TextStyle(
                  color: AppTheme.emerald,
                  fontSize: 10, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 12),

        if (msg.isEmpty && !running)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.08),
                    shape: BoxShape.circle),
                  child: const Icon(Icons.auto_awesome_rounded,
                    color: AppTheme.primaryLt, size: 22)),
                const SizedBox(height: 10),
                Text(
                  hasTimetable ? 'Timetable ready' : 'Ready to generate',
                  style: const TextStyle(color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 3),
                Text(
                  hasTimetable
                    ? '$existingSlots slots generated'
                    : 'Select mode and press Generate',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11.5)),
              ])))

        else if (running)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(progressLabel,
              style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 11.5)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressTotal == 0 ? null : progress,
                minHeight: 8,
                backgroundColor: AppTheme.cardAlt,
                valueColor: AlwaysStoppedAnimation(AppTheme.primary))),
            const SizedBox(height: 6),
            if (progressTotal > 0)
              Text('$progressDone / $progressTotal sections',
                style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 10.5)),
          ])

        else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ok
                  ? AppTheme.success.withOpacity(0.08)
                  : AppTheme.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: ok
                    ? AppTheme.success.withOpacity(0.28)
                    : AppTheme.error.withOpacity(0.28))),
            child: Row(children: [
              Icon(ok
                  ? Icons.check_circle_outline_rounded
                  : Icons.error_outline_rounded,
                color: ok ? AppTheme.success : AppTheme.error, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(msg, style: TextStyle(
                color: ok ? AppTheme.success : AppTheme.error,
                fontWeight: FontWeight.w600, fontSize: 12.5))),
            ])),

          if (warn.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('CONFLICTS  (${warn.length})', style: TextStyle(
              color: AppTheme.textMuted, fontSize: 8.5,
              fontWeight: FontWeight.w700, letterSpacing: 1.3)),
            const SizedBox(height: 7),
            ...warn.take(15).map((c) => Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.06),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppTheme.warning.withOpacity(0.20))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.warning_amber_rounded,
                      color: AppTheme.warning, size: 11)),
                  const SizedBox(width: 7),
                  Expanded(child: Text(c, style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 10.5))),
                ]))),
          ],

          if (ok && hasTimetable && onViewTimetable != null) ...[
            const SizedBox(height: 12),
            _GBtn(
              label: 'View Timetable',
              icon: Icons.calendar_view_week_rounded,
              onTap: onViewTimetable!),
          ],
        ],
      ]));

    // ── Layout ──────────────────────────────────────────────────────────────
    // Mobile: scrollable column
    // Desktop: Row with left panel (300px) + scrollable right panel.
    // Wrap in SizedBox.expand so the Row gets bounded height from its parent.
    return Padding(
      padding: const EdgeInsets.all(16),
      child: isMob
        ? SingleChildScrollView(child: Column(children: [
            const Text('Generate Timetable', style: TextStyle(
              color: AppTheme.textPrimary, fontSize: 15,
              fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            modeSelector,
            const SizedBox(height: 12),
            controlsCard,
            const SizedBox(height: 12),
            statusCard,
            const SizedBox(height: 14),
          ]))
        : SizedBox.expand(child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left panel — mode + controls
              SizedBox(width: 300, child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Generate Timetable', style: TextStyle(
                      color: AppTheme.textPrimary, fontSize: 15,
                      fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    modeSelector,
                    const SizedBox(height: 12),
                    controlsCard,
                  ]))),
              const SizedBox(width: 14),
              // Right panel — status / results
              Expanded(child: SingleChildScrollView(child: statusCard)),
            ])),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _buildProgressWidget() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppTheme.primary.withOpacity(0.08),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: AppTheme.primary.withOpacity(0.25))),
    child: Row(children: [
      const SizedBox(width: 18, height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2.5, color: AppTheme.primaryLt)),
      const SizedBox(width: 12),
      const Expanded(child: Text('Generating…',
        style: TextStyle(color: AppTheme.primaryLt,
          fontWeight: FontWeight.w600, fontSize: 12.5))),
    ]));

  Widget _buildLockedBtn(bool isYearMode, int genYear) => Tooltip(
    message: isYearMode
        ? 'Delete Year $genYear timetable first'
        : 'Delete existing timetable first',
    child: Container(
      height: 42, alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.cardAlt,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppTheme.border)),
      child: const Row(mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded, color: AppTheme.textMuted, size: 14),
          SizedBox(width: 8),
          Text('Delete timetable to regenerate',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ])));

  static Widget _chip(String t) => Container(
    margin: const EdgeInsets.only(bottom: 5),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: AppTheme.cardAlt,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: AppTheme.border)),
    child: Row(children: [
      Container(width: 5, height: 5,
        decoration: const BoxDecoration(
          color: AppTheme.primaryLt, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Expanded(child: Text(t, style: const TextStyle(
        color: AppTheme.textSecondary, fontSize: 10.5))),
    ]));

  static Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required bool enabled,
  }) => Container(
    height: 38,
    decoration: BoxDecoration(
      color: enabled ? color.withOpacity(0.10) : AppTheme.cardAlt,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(
        color: enabled ? color.withOpacity(0.35) : AppTheme.border)),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: enabled ? color : AppTheme.textMuted, size: 13),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(
        color: enabled ? color : AppTheme.textMuted,
        fontSize: 11, fontWeight: FontWeight.w600)),
    ]));
}

// ── Mode button widget ────────────────────────────────────────────────────────
class _ModeBtn extends StatelessWidget {
  final String label, subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  const _ModeBtn({required this.label, required this.subtitle,
    required this.icon, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected
            ? AppTheme.primary.withOpacity(0.13)
            : AppTheme.cardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? AppTheme.primary : AppTheme.border,
          width: selected ? 1.5 : 1.0)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon,
            color: selected ? AppTheme.primaryLt : AppTheme.textSecondary,
            size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            color: selected ? AppTheme.primaryLt : AppTheme.textPrimary,
            fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(
          color: AppTheme.textMuted, fontSize: 9.5)),
      ])),
  );
}


// ═══════════════════════════════════════════════════════════════════════════════
// TIMETABLE TAB
// ═══════════════════════════════════════════════════════════════════════════════
class _TTTab extends StatefulWidget {
  final DatabaseService db;
  final ExcelService    excel;
  const _TTTab({required this.db, required this.excel});
  @override State<_TTTab> createState() => _TTTabState();
}

class _TTTabState extends State<_TTTab> {
  // Dropdown driven purely by imported subjects — no free-text entry
  List<Map<String, dynamic>> _sectionYearPairs = [];
  String? _selSection;
  int?    _selYear;
  List<TimetableEntry> _entries  = [];
  Map<String, String>  _subNames = {}, _facNames = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSectionPairs();
  }

  Future<void> _loadSectionPairs() async {
    final pairs = await widget.db.getSectionYearPairs();
    if (!mounted) return;
    setState(() {
      _sectionYearPairs = pairs;
      if (pairs.isNotEmpty) {
        _selSection = pairs.first['section'] as String;
        _selYear    = pairs.first['year']    as int;
      }
    });
  }

  Future<void> _load() async {
    final sec = _selSection;
    final yr  = _selYear;
    if (sec == null || yr == null) return;
    setState(() => _loading = true);
    final entries  = await widget.db.getTimetableBySection(sec, yr);
    final subjects = await widget.db.getSubjectsBySection(sec, yr);
    final faculty  = await widget.db.getAllFaculty();
    final allSubs  = subjects.isEmpty ? await widget.db.getAllSubjects() : subjects;
    setState(() {
      _entries  = entries;
      _subNames = {for (final s in allSubs) s.id: s.name};
      _facNames = {for (final f in faculty)  f.id: f.name};
      _loading  = false;
    });
  }

  Future<void> _export() async {
    final path = await widget.excel.exportTimetable(
      entries: _entries, subjectNames: _subNames, facultyNames: _facNames,
      section: _selSection ?? '', year: _selYear ?? 1);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(path != null
          ? '✅ Exported: $path' : '❌ Export failed')));
  }

  Future<void> _deleteSection() async {
    final sec = _selSection ?? '';
    final yr  = _selYear   ?? 1;
    if (sec.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.amber.withOpacity(0.35))),
        title: const Text('Delete Section Timetable?',
          style: TextStyle(color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 15)),
        content: Text(
          'This will delete all ${_entries.length} entries for Section $sec Year $yr.\n\nFaculty, subjects and students are not affected.',
          style: const TextStyle(
            color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
              style: TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.amber,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8))),
            child: const Text('Delete',
              style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Delete only this section+year's entries
    await widget.db.clearTimetable(sec, yr);
    setState(() => _entries = []);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('✅ Section timetable deleted. You can re-generate now.')));
  }

  @override
  Widget build(BuildContext context) {
    final isMob = R.isMobile(context);

    // ── Filter bar ────────────────────────────────────────────────────────
    Widget filterBar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppTheme.border)),
      child: isMob
        // Mobile: two rows
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 24, height: 24,
                decoration: BoxDecoration(
                  gradient: AppTheme.purpleGradient,
                  borderRadius: BorderRadius.circular(6)),
                child: const Icon(Icons.grid_view_rounded,
                    color: Colors.white, size: 12)),
              const SizedBox(width: 8),
              const Text('Timetable Viewer', style: TextStyle(
                color: AppTheme.textPrimary, fontSize: 12.5,
                fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppTheme.cardAlt,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: AppTheme.border)),
                child: DropdownButtonHideUnderline(
                  child: _sectionYearPairs.isEmpty
                    ? const Center(child: Text('Import data first',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11)))
                    : DropdownButton<String>(
                        value: (_selSection != null && _selYear != null &&
                            _sectionYearPairs.any((p) =>
                              p['section'] == _selSection && p['year'] == _selYear))
                            ? '${_selSection}_$_selYear' : null,
                        hint: const Text('Select Section',
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                        dropdownColor: AppTheme.card,
                        isExpanded: true,
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 12),
                        items: _sectionYearPairs.map((p) {
                          final s = p['section'] as String;
                          final y = p['year']    as int;
                          return DropdownMenuItem<String>(
                            value: '${s}_$y',
                            child: Text('Section $s — Year $y'));
                        }).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          final parts = v.split('_');
                          setState(() {
                            _selSection = parts[0];
                            _selYear    = int.tryParse(parts[1]) ?? 1;
                            _entries    = [];
                          });
                        })))),
              const SizedBox(width: 7),
              _GBtn(label: 'Load', icon: Icons.search_rounded,
                  onTap: _selSection != null ? _load : null, compact: true),
              const SizedBox(width: 6),
              Container(width: 36, height: 36,
                decoration: BoxDecoration(
                  color: _entries.isNotEmpty ? AppTheme.cardAlt : AppTheme.card,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: AppTheme.border)),
                child: IconButton(
                  icon: Icon(Icons.download_rounded,
                    color: _entries.isNotEmpty
                        ? AppTheme.primaryLt : AppTheme.textMuted,
                    size: 14),
                  onPressed: _entries.isNotEmpty ? _export : null,
                  padding: EdgeInsets.zero)),
              const SizedBox(width: 5),
              Container(width: 36, height: 36,
                decoration: BoxDecoration(
                  color: _entries.isNotEmpty
                      ? AppTheme.amber.withOpacity(0.08) : AppTheme.card,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: _entries.isNotEmpty
                        ? AppTheme.amber.withOpacity(0.35) : AppTheme.border)),
                child: IconButton(
                  icon: Icon(Icons.delete_sweep_rounded,
                    color: _entries.isNotEmpty
                        ? AppTheme.amber : AppTheme.textMuted,
                    size: 14),
                  tooltip: 'Delete timetable',
                  onPressed: _entries.isNotEmpty ? _deleteSection : null,
                  padding: EdgeInsets.zero)),
            ]),
          ])
        // Desktop: single row
        : Row(children: [
            Container(width: 26, height: 26,
              decoration: BoxDecoration(
                gradient: AppTheme.purpleGradient,
                borderRadius: BorderRadius.circular(7)),
              child: const Icon(Icons.grid_view_rounded,
                  color: Colors.white, size: 12)),
            const SizedBox(width: 9),
            const Text('Timetable Viewer', style: TextStyle(
              color: AppTheme.textPrimary, fontSize: 12.5,
              fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              height: 32,
              constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppTheme.cardAlt,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppTheme.border)),
              child: DropdownButtonHideUnderline(
                child: _sectionYearPairs.isEmpty
                  ? const Center(child: Text('Import data first',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11)))
                  : DropdownButton<String>(
                      value: (_selSection != null && _selYear != null &&
                          _sectionYearPairs.any((p) =>
                            p['section'] == _selSection && p['year'] == _selYear))
                          ? '${_selSection}_$_selYear' : null,
                      hint: const Text('Select Section — Year',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                      dropdownColor: AppTheme.card,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 12),
                      items: _sectionYearPairs.map((p) {
                        final s = p['section'] as String;
                        final y = p['year']    as int;
                        return DropdownMenuItem<String>(
                          value: '${s}_$y',
                          child: Text('Section $s — Year $y'));
                      }).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        final parts = v.split('_');
                        setState(() {
                          _selSection = parts[0];
                          _selYear    = int.tryParse(parts[1]) ?? 1;
                          _entries    = [];
                        });
                      }))),
            const SizedBox(width: 7),
            _GBtn(label: 'Load', icon: Icons.search_rounded,
                onTap: _selSection != null ? _load : null, compact: true),
            const SizedBox(width: 6),
            Container(width: 32, height: 32,
              decoration: BoxDecoration(
                color: _entries.isNotEmpty
                    ? AppTheme.cardAlt : AppTheme.card,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppTheme.border)),
              child: IconButton(
                icon: Icon(Icons.download_rounded,
                  color: _entries.isNotEmpty
                      ? AppTheme.primaryLt : AppTheme.textMuted,
                  size: 13),
                onPressed: _entries.isNotEmpty ? _export : null,
                padding: EdgeInsets.zero)),
            const SizedBox(width: 5),
            Container(width: 32, height: 32,
              decoration: BoxDecoration(
                color: _entries.isNotEmpty
                    ? AppTheme.amber.withOpacity(0.08) : AppTheme.card,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: _entries.isNotEmpty
                      ? AppTheme.amber.withOpacity(0.35) : AppTheme.border)),
              child: IconButton(
                icon: Icon(Icons.delete_sweep_rounded,
                  color: _entries.isNotEmpty
                      ? AppTheme.amber : AppTheme.textMuted,
                  size: 13),
                tooltip: 'Delete this section timetable',
                onPressed: _entries.isNotEmpty ? _deleteSection : null,
                padding: EdgeInsets.zero)),
          ]));

    // ── Grid area ─────────────────────────────────────────────────────────
    Widget gridArea = Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border)),
      child: _loading
        ? const Center(child: CircularProgressIndicator(
            color: AppTheme.primaryLt))
        : _entries.isEmpty
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 48, height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.08),
                  shape: BoxShape.circle),
                child: const Icon(Icons.grid_view_rounded,
                  color: AppTheme.primaryLt, size: 22)),
              const SizedBox(height: 10),
              const Text('Enter a section and tap Search',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
            ]))
          : TimetableGridWidget(
              entries: _entries,
              subjectNames: _subNames,
              facultyNames: _facNames));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        filterBar,
        const SizedBox(height: 9),
        Expanded(child: gridArea),
      ]));
  }
}

void _showAdminChangePasswordDialog(BuildContext context) {
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
        title: const Text('Change Admin Password',
          style: TextStyle(color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800, fontSize: 16)),
        content: SizedBox(width: 340, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AdminPwdField(ctrl: currCtrl, label: 'Current Password',
              obscure: obscureCurr,
              onToggle: () => setS(() => obscureCurr = !obscureCurr)),
            const SizedBox(height: 12),
            _AdminPwdField(ctrl: newCtrl, label: 'New Password',
              obscure: obscureNew,
              onToggle: () => setS(() => obscureNew = !obscureNew),
              hint: 'Min 6 chars, include a number or symbol'),
            const SizedBox(height: 12),
            _AdminPwdField(ctrl: confCtrl, label: 'Confirm New Password',
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
                  content: const Text('Admin password changed!',
                    style: TextStyle(color: Colors.white)),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))));
              }
            },
            child: const Text('Change')),
        ])));
}

class _AdminPwdField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  final String? hint;
  const _AdminPwdField({
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

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED GRADIENT BUTTON  (press-scale animation)
// ═══════════════════════════════════════════════════════════════════════════════
class _GBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool compact;
  const _GBtn({required this.label, required this.icon,
      this.onTap, this.compact = false});
  @override State<_GBtn> createState() => _GBtnState();
}

class _GBtnState extends State<_GBtn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double>   _sc;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 90));
    _sc = Tween<double>(begin: 1.0, end: 0.95)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
  }
  @override void dispose() { _ac.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown:   widget.onTap != null ? (_) => _ac.forward() : null,
    onTapUp:     widget.onTap != null ? (_) { _ac.reverse(); widget.onTap!(); } : null,
    onTapCancel: widget.onTap != null ? () => _ac.reverse() : null,
    child: ScaleTransition(
      scale: _sc,
      child: Container(
        height: widget.compact ? 32 : 42,
        padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 12 : 18),
        decoration: BoxDecoration(
          gradient: AppTheme.purpleGradient,
          borderRadius: BorderRadius.circular(widget.compact ? 7 : 10),
          boxShadow: [AppTheme.glowPurple]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(widget.icon, color: Colors.white,
              size: widget.compact ? 12 : 14),
          SizedBox(width: widget.compact ? 5 : 7),
          Text(widget.label, style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.w700,
            fontSize: widget.compact ? 11.5 : 13)),
        ]))));
}
