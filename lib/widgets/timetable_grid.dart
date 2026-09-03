import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  TIMETABLE GRID — sticky headers, true 2-axis pan
//
//  Layout:
//   ┌──────────┬──────── horizontally scrollable ────────────────────┐
//   │  corner  │  P1 │ brk │ P2 │ brk │ P3 │ P4 │ brk │ P5 │ P6 │ P7 │  ← frozen top
//   ├──────────┼────────────────────────────────────────────────────────┤
//   │  MON     │  cells …                                               │  ↑
//   │  TUE     │  cells …                                               │  vertically
//   │  …       │  cells …                                               │  scrollable
//   │  SAT     │  cells …                                               │  ↓
//   └──────────┴────────────────────────────────────────────────────────┘
//    ↑ frozen left
//
//  Two linked ScrollControllers keep header and body in sync horizontally.
// ══════════════════════════════════════════════════════════════════════════════

class TimetableGridWidget extends StatefulWidget {
  final List<TimetableEntry> entries;
  final Map<String, String>  subjectNames;
  final Map<String, String>  facultyNames;
  final int?  selectedDay;
  final bool  showFaculty;

  const TimetableGridWidget({
    super.key,
    required this.entries,
    required this.subjectNames,
    required this.facultyNames,
    this.selectedDay,
    this.showFaculty = true,
  });

  @override
  State<TimetableGridWidget> createState() => _TimetableGridWidgetState();
}

class _TimetableGridWidgetState extends State<TimetableGridWidget> {
  final _hHeader = ScrollController(); // header row horizontal
  final _hBody   = ScrollController(); // body cells horizontal  (linked to _hHeader)
  final _vBody   = ScrollController(); // body+day-col vertical

  // Keep H scroll in sync: header ↔ body
  bool _syncing = false;
  void _onHeaderScroll() {
    if (_syncing) return;
    _syncing = true;
    _hBody.jumpTo(_hHeader.offset);
    _syncing = false;
  }
  void _onBodyScroll() {
    if (_syncing) return;
    _syncing = true;
    _hHeader.jumpTo(_hBody.offset);
    _syncing = false;
  }

  @override
  void initState() {
    super.initState();
    // Link header and body horizontal scroll
    _hHeader.addListener(_onHeaderScroll);
    _hBody.addListener(_onBodyScroll);
  }

  @override
  void dispose() {
    _hHeader.removeListener(_onHeaderScroll);
    _hBody.removeListener(_onBodyScroll);
    _hHeader.dispose();
    _hBody.dispose();
    _vBody.dispose();
    super.dispose();
  }

  // ── Dimensions ─────────────────────────────────────────────────────────────
  static const double _dayColW    = 46.0;
  static const double _periodColW = 108.0;
  static const double _breakColW  = 20.0;
  static const double _headH      = 50.0;
  static const double _rowH       = 88.0;

  static Color _accent(bool isLab, bool isSpecial) {
    if (isSpecial) return AppTheme.specialColor;
    if (isLab)     return AppTheme.labColor;
    return AppTheme.theoryColor;
  }

  @override
  Widget build(BuildContext context) {
    final days  = widget.selectedDay != null
        ? [widget.selectedDay!]
        : [1, 2, 3, 4, 5, 6];
    final slots = TimeSlot.periods;

    // Total scrollable width of period columns
    final double scrollW = slots.fold(0.0, (sum, s) =>
        sum + (s.isBreak ? _breakColW : _periodColW));

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Column(children: [
        // ── SCROLL HINT (shown on mobile when content wider than screen) ────
        LayoutBuilder(builder: (ctx, box) {
          final canScroll = scrollW + _dayColW > box.maxWidth;
          if (!canScroll) return const SizedBox.shrink();
          return Container(
            color: AppTheme.cardAlt,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.chevron_left_rounded,
                color: AppTheme.textMuted, size: 14),
              const SizedBox(width: 4),
              const Text('Swipe to see all periods',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                color: AppTheme.textMuted, size: 14),
            ]),
          );
        }),
        // ── FROZEN HEADER ROW ───────────────────────────────────────────────
        SizedBox(
          height: _headH,
          child: Row(children: [
            // Corner cell (frozen)
            _cornerCell(),
            // Period headers (horizontally scrollable)
            Expanded(child: SingleChildScrollView(
              controller: _hHeader,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: _HeaderRow(
                slots:      slots,
                periodColW: _periodColW,
                breakColW:  _breakColW,
                headH:      _headH,
              ),
            )),
          ]),
        ),

        // ── BODY (frozen day labels + scrollable cells) ──────────────────────
        // ONE vertical ScrollView wraps both day labels and cells.
        // Explicit height avoids IntrinsicHeight (web-safe).
        Expanded(child: SingleChildScrollView(
          controller: _vBody,
          scrollDirection: Axis.vertical,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            height: _rowH * days.length,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Frozen day-label column (fixed width)
                SizedBox(
                  width: _dayColW,
                  child: Column(children: days.map((d) => _DayLabel(
                    day: d, rowH: _rowH, colW: _dayColW)).toList())),

                // Horizontally scrollable cell area
                Expanded(child: SingleChildScrollView(
                  controller: _hBody,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(
                    width: scrollW,
                    child: Column(
                      children: days.map((day) => SizedBox(
                        height: _rowH,
                        child: _CellRow(
                          day:          day,
                          slots:        slots,
                          entries:      widget.entries,
                          subjectNames: widget.subjectNames,
                          facultyNames: widget.facultyNames,
                          showFaculty:  widget.showFaculty,
                          periodColW:   _periodColW,
                          breakColW:    _breakColW,
                          rowH:         _rowH,
                          accentFn:     _accent,
                        ),
                      )).toList(),
                    ),
                  ),
                )),
              ],
            ),
          ),
        )),
      ]),
    );
  }

  Widget _cornerCell() => Container(
    width: _dayColW,
    height: _headH,
    color: AppTheme.bgDark,
    child: const Center(
      child: Icon(Icons.calendar_today_rounded,
        color: AppTheme.textMuted, size: 13)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  HEADER ROW (period labels)
// ══════════════════════════════════════════════════════════════════════════════
class _HeaderRow extends StatelessWidget {
  final List<PeriodSlot> slots;
  final double periodColW, breakColW, headH;
  const _HeaderRow({
    required this.slots, required this.periodColW,
    required this.breakColW, required this.headH,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: headH,
      color: AppTheme.bgDark,
      child: Row(children: slots.map((slot) {
        if (slot.isBreak) {
          return Container(
            width: breakColW,
            height: headH,
            color: AppTheme.bgDark,
            child: Center(child: RotatedBox(
              quarterTurns: 1,
              child: Text(
                slot.label.contains('Lunch') ? 'L' : 'B',
                style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 7,
                  fontWeight: FontWeight.w700)),
            )));
        }
        return Container(
          width: periodColW,
          height: headH,
          decoration: BoxDecoration(
            color: AppTheme.bgDark,
            border: Border(
              left:   BorderSide(color: AppTheme.border),
              bottom: BorderSide(color: AppTheme.border),
            )),
          child: Column(mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:  AppTheme.primary.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.28))),
                child: Text('P${slot.number}',
                  style: const TextStyle(
                    color: AppTheme.primaryLt,
                    fontWeight: FontWeight.w800, fontSize: 10))),
              const SizedBox(height: 3),
              Text(slot.startTime,
                style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 8)),
            ]),
        );
      }).toList()),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DAY LABEL (frozen left column)
// ══════════════════════════════════════════════════════════════════════════════
class _DayLabel extends StatelessWidget {
  final int day;
  final double rowH, colW;
  const _DayLabel({required this.day, required this.rowH, required this.colW});

  static const _short = ['','MON','TUE','WED','THU','FRI','SAT'];
  static const _full  = ['','Mon','Tue','Wed','Thu','Fri','Sat'];

  @override
  Widget build(BuildContext context) {
    final isToday = DateTime.now().weekday == day;
    final isSat   = day == 6;
    return Container(
      width: colW, height: rowH,
      decoration: BoxDecoration(
        color: isToday
            ? AppTheme.primary.withOpacity(0.12)
            : AppTheme.cardAlt,
        border: Border(
          right:  BorderSide(color: AppTheme.border),
          bottom: BorderSide(color: AppTheme.border),
        )),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (isToday)
          Container(
            width: 5, height: 5,
            margin: const EdgeInsets.only(bottom: 3),
            decoration: const BoxDecoration(
              color: AppTheme.primaryLt, shape: BoxShape.circle)),
        Text(_short[day], style: TextStyle(
          color: isToday
              ? AppTheme.primaryLt
              : isSat ? AppTheme.secondary : AppTheme.textSecondary,
          fontWeight: FontWeight.w800, fontSize: 9)),
        const SizedBox(height: 1),
        Text(_full[day], style: const TextStyle(
          color: AppTheme.textMuted, fontSize: 7)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  CELL ROW (one day's worth of period cells)
// ══════════════════════════════════════════════════════════════════════════════
class _CellRow extends StatelessWidget {
  final int day;
  final List<PeriodSlot> slots;
  final List<TimetableEntry> entries;
  final Map<String, String>  subjectNames, facultyNames;
  final bool showFaculty;
  final double periodColW, breakColW, rowH;
  final Color Function(bool, bool) accentFn;

  const _CellRow({
    required this.day,       required this.slots,
    required this.entries,   required this.subjectNames,
    required this.facultyNames, required this.showFaculty,
    required this.periodColW,   required this.breakColW,
    required this.rowH,         required this.accentFn,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = DateTime.now().weekday == day;
    return Container(
      height: rowH,
      color: isToday ? AppTheme.primary.withOpacity(0.03) : AppTheme.card,
      child: Row(children: slots.map((slot) {
        if (slot.isBreak) {
          return Container(
            width: breakColW, height: rowH,
            color: AppTheme.bgDark.withOpacity(0.5),
            child: const Center(child: Icon(
              Icons.remove_rounded, color: AppTheme.textMuted, size: 9)));
        }

        final matches = entries
            .where((e) => e.dayOfWeek == day && e.periodNumber == slot.number)
            .toList();

        return Container(
          width: periodColW, height: rowH,
          decoration: BoxDecoration(
            border: Border(
              left:   BorderSide(color: AppTheme.border),
              bottom: BorderSide(color: AppTheme.border),
            )),
          child: matches.isEmpty
            ? const Center(child: Text('—', style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 14, fontWeight: FontWeight.w200)))
            : _PeriodCell(
                matches:      matches,
                subjectNames: subjectNames,
                facultyNames: facultyNames,
                showFaculty:  showFaculty,
                accentFn:     accentFn,
              ),
        );
      }).toList()),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  PERIOD CELL (handles B1+B2 split)
// ══════════════════════════════════════════════════════════════════════════════
class _PeriodCell extends StatelessWidget {
  final List<TimetableEntry> matches;
  final Map<String, String>  subjectNames, facultyNames;
  final bool showFaculty;
  final Color Function(bool, bool) accentFn;

  const _PeriodCell({
    required this.matches,      required this.subjectNames,
    required this.facultyNames, required this.showFaculty,
    required this.accentFn,
  });

  @override
  Widget build(BuildContext context) {
    final b1    = matches.where((e) => e.batch == 1).toList();
    final b2    = matches.where((e) => e.batch == 2).toList();
    final other = matches.where((e) => e.batch == 0).toList();

    if (b1.isNotEmpty && b2.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(3),
        child: Column(children: [
          Expanded(child: _EntryTile(
            entry: b1.first, subjectNames: subjectNames,
            facultyNames: facultyNames, showFaculty: false,
            accentFn: accentFn, compact: true)),
          const SizedBox(height: 2),
          Expanded(child: _EntryTile(
            entry: b2.first, subjectNames: subjectNames,
            facultyNames: facultyNames, showFaculty: false,
            accentFn: accentFn, compact: true)),
        ]),
      );
    }

    final all = [...other, ...b1, ...b2];
    if (all.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(4),
      child: _EntryTile(
        entry: all.first, subjectNames: subjectNames,
        facultyNames: facultyNames, showFaculty: showFaculty,
        accentFn: accentFn, compact: false),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ENTRY TILE
// ══════════════════════════════════════════════════════════════════════════════
class _EntryTile extends StatelessWidget {
  final TimetableEntry entry;
  final Map<String, String> subjectNames, facultyNames;
  final bool showFaculty, compact;
  final Color Function(bool, bool) accentFn;

  const _EntryTile({
    required this.entry,        required this.subjectNames,
    required this.facultyNames, required this.showFaculty,
    required this.accentFn,     required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final isSpecial = entry.specialLabel != null;
    final isLab     = entry.isLab;
    final accent    = accentFn(isLab, isSpecial);
    final name      = isSpecial
        ? entry.specialLabel!
        : (subjectNames[entry.subjectId] ?? 'Subject');
    final fac       = facultyNames[entry.facultyId] ?? '';
    final typeLabel = isSpecial ? 'SPL' : isLab ? 'LAB' : 'LEC';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6, vertical: compact ? 3 : 4),
      decoration: BoxDecoration(
        color:  accent.withOpacity(0.09),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: accent.withOpacity(0.30))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            _badge(typeLabel, accent),
            if (entry.batch > 0) ...[ const SizedBox(width: 3),
              _badge('B${entry.batch}', AppTheme.secondary)],
          ]),
          SizedBox(height: compact ? 2 : 3),
          Text(name,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent, fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w700, height: 1.2)),
          if (showFaculty && fac.isNotEmpty && !isSpecial && !compact)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                Icon(Icons.person_outline_rounded,
                  size: 8, color: AppTheme.textMuted),
                const SizedBox(width: 2),
                Expanded(child: Text(fac,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 8))),
              ])),
        ],
      ),
    );
  }

  static Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: color.withOpacity(0.18),
      borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: TextStyle(
      color: color, fontSize: 7,
      fontWeight: FontWeight.w800, letterSpacing: 0.3)));
}
