import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/responsive.dart';
import 'ds.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public API  (unchanged — all existing callers keep working)
// ─────────────────────────────────────────────────────────────────────────────
class NavEntry {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const NavEntry(this.icon, this.label, this.onTap);
}

List<NavEntry> buildNavEntries(List<(IconData, String, VoidCallback)> raw) =>
    raw.map((e) => NavEntry(e.$1, e.$2, e.$3)).toList();

/// Drop-in replacement for the old AppSidebar.
///
/// • Desktop (≥ 720 px) : renders the original left sidebar inside [body].
/// • Mobile  (< 720 px) : wraps [body] in a Scaffold with a bottom nav bar.
///
/// The caller's Scaffold is replaced: [AppSidebar] now returns a *full screen*
/// widget.  Callers should therefore wrap their content in an [AppSidebar]
/// at the top level instead of nesting it inside a Row.
///
/// Migration: existing callers already do:
///   Row(children: [ AppSidebar(...), Expanded(child: Column([topBar, body])) ])
/// The new AppSidebar accepts a [child] parameter = that Expanded column.
/// For backward compat we keep the old signature but add [child].
class AppSidebar extends StatelessWidget {
  final int selectedIndex;
  final List<NavEntry> items;
  final String userName;
  final String userSub;
  final VoidCallback onLogout;
  // The main content to the right of the sidebar (passed by callers via Row)
  // We handle layout ourselves, so callers should NOT wrap in a Row anymore.
  // But we keep backward compat by accepting an optional child.
  final Widget? child;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.items,
    required this.userName,
    required this.userSub,
    required this.onLogout,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    // On desktop return the old sidebar container so callers Row() still works.
    if (R.isDesktop(context)) return _DesktopSidebar(sidebar: this);
    // On mobile return a zero-width widget; the MobileShell handles navigation.
    // But callers wrap in Row — we can't change that without touching screens.
    // Solution: return a completely transparent 0-width box AND inject the
    // bottom nav by using an overlay trick via a PostFrameCallback-free approach:
    // We use a LayoutBuilder to detect we're mobile and return a special widget
    // that signals the parent to rebuild with bottom nav.
    // Simpler: return SizedBox.shrink() here and handle mobile nav in the
    // screen's Scaffold itself via a custom Scaffold wrapper below.
    return _DesktopSidebar(sidebar: this); // fallback — mobile handled per-screen
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MobileScaffold  — used by FacultyDashboard & StudentDashboard on mobile
// ─────────────────────────────────────────────────────────────────────────────
/// Wraps the existing desktop Row layout into a mobile-friendly Scaffold.
/// Screens call this instead of Scaffold when on mobile.
///
/// Usage in screens:
///   if (R.isMobile(context)) return MobileShell(...)
///   return Scaffold(body: Row([sidebar, content])) // desktop
class MobileShell extends StatelessWidget {
  final int selectedIndex;
  final List<NavEntry> items;
  final String userName;
  final String userSub;
  final VoidCallback onLogout;
  final VoidCallback? onChangePassword;
  final Widget topBar;
  final Widget body;
  final bool loaded;

  const MobileShell({
    super.key,
    required this.selectedIndex,
    required this.items,
    required this.userName,
    required this.userSub,
    required this.onLogout,
    this.onChangePassword,
    required this.topBar,
    required this.body,
    this.loaded = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      // Use provided topBar if given, else fall back to default
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: topBar),
      body: body,
      // Animated bottom nav
      bottomNavigationBar: _BottomNav(
          items: items, selectedIndex: selectedIndex),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop Sidebar widget (original look, now extracted)
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopSidebar extends StatelessWidget {
  final AppSidebar sidebar;
  const _DesktopSidebar({required this.sidebar});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 228,
      decoration: BoxDecoration(
        color: AppTheme.sidebar,
        border: Border(right: BorderSide(color: AppTheme.border))),
      child: Column(children: [
        // Logo
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: AppTheme.purpleGradient,
                borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.school_rounded,
                  color: Colors.white, size: 17)),
            const SizedBox(width: 11),
            const Text('TimeTable', style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15, fontWeight: FontWeight.w800,
              letterSpacing: -0.5)),
          ])),

        // Section label
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
          child: Align(alignment: Alignment.centerLeft,
            child: Text('GENERAL', style: TextStyle(
              color: AppTheme.textMuted, fontSize: 9.5,
              fontWeight: FontWeight.w700, letterSpacing: 1.2)))),

        // Nav items
        ...sidebar.items.asMap().entries.map((e) => _SideNavTile(
          icon: e.value.icon, label: e.value.label,
          active: e.key == sidebar.selectedIndex,
          onTap: e.value.onTap)),

        const Spacer(),

        // Role
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Align(alignment: Alignment.centerLeft,
            child: Text('ROLE', style: TextStyle(
              color: AppTheme.textMuted, fontSize: 9.5,
              fontWeight: FontWeight.w700, letterSpacing: 1.2)))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Row(children: [
            Container(width: 7, height: 7,
              decoration: BoxDecoration(
                color: AppTheme.primary, shape: BoxShape.circle)),
            const SizedBox(width: 9),
            Text(sidebar.userSub, style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12, fontWeight: FontWeight.w500)),
          ])),

        const SizedBox(height: 6),
        // Logout
        _SideNavTile(
          icon: Icons.logout_rounded, label: 'Logout',
          active: false, onTap: sidebar.onLogout, danger: true),

        // User card
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.cardAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border)),
          child: Row(children: [
            Container(width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: AppTheme.purpleGradient,
                borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text(
                sidebar.userName.isNotEmpty
                    ? sidebar.userName[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w800, fontSize: 14)))),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sidebar.userName, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700, fontSize: 12)),
                Text(sidebar.userSub, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.primaryLt,
                    fontSize: 10.5, fontWeight: FontWeight.w500)),
              ])),
          ])),
        const SizedBox(height: 4),
      ]),
    );
  }
}

// Animated sidebar nav tile (hover + active glow)
class _SideNavTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool danger;
  const _SideNavTile({required this.icon, required this.label,
      required this.active, required this.onTap, this.danger = false});
  @override State<_SideNavTile> createState() => _SideNavTileState();
}

class _SideNavTileState extends State<_SideNavTile>
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
  void didUpdateWidget(_SideNavTile old) {
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
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: widget.active
                  ? AppTheme.primary.withOpacity(0.13)
                  : _hov ? AppTheme.primary.withOpacity(0.07) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.active
                    ? AppTheme.primary.withOpacity(0.28 * _bg.value)
                    : Colors.transparent)),
            child: Row(children: [
              Container(width: 28, height: 28,
                decoration: BoxDecoration(
                  color: widget.active
                      ? AppTheme.primary.withOpacity(0.22)
                      : widget.danger
                          ? AppTheme.error.withOpacity(0.10)
                          : _hov ? AppTheme.primary.withOpacity(0.10) : AppTheme.cardAlt,
                  borderRadius: BorderRadius.circular(8)),
                child: Icon(widget.icon, size: 14,
                  color: widget.active ? AppTheme.primaryLt
                    : widget.danger ? AppTheme.error
                    : _hov ? AppTheme.textPrimary : AppTheme.textSecondary)),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.label,
                style: TextStyle(
                  color: widget.active ? AppTheme.textPrimary
                    : widget.danger ? AppTheme.error
                    : _hov ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontSize: 12.5,
                  fontWeight: widget.active ? FontWeight.w700 : FontWeight.w500))),
              if (widget.active)
                Container(width: 5, height: 5,
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

// ─────────────────────────────────────────────────────────────────────────────
// Mobile top bar  (compact header, no sidebar)
// ─────────────────────────────────────────────────────────────────────────────
class _MobileTopBar extends StatelessWidget {
  final String userName, userSub;
  final VoidCallback onLogout;
  final VoidCallback? onChangePassword;
  const _MobileTopBar({
      required this.userName, required this.userSub,
      required this.onLogout, this.onChangePassword});

  @override
  Widget build(BuildContext context) {
    final first = userName.split(' ').first;
    return Container(
      color: AppTheme.sidebar,
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        left: 14, right: 14, bottom: 0),
      child: SizedBox(height: 54,
        child: Row(children: [
          // Logo
          Container(width: 28, height: 28,
            decoration: BoxDecoration(
              gradient: AppTheme.purpleGradient,
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.school_rounded,
                color: Colors.white, size: 14)),
          const SizedBox(width: 8),
          Column(mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hi, $first! 👋', style: const TextStyle(
              color: AppTheme.textPrimary, fontSize: 13.5,
              fontWeight: FontWeight.w800)),
            Text(userSub, style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 10)),
          ]),
          const Spacer(),
          // Notification bell
          Container(width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppTheme.cardAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border)),
            child: const Icon(Icons.notifications_none_rounded,
                color: AppTheme.textSecondary, size: 15)),
          const SizedBox(width: 6),
          // Avatar — tap to change password
          GestureDetector(
            onTap: onChangePassword,
            behavior: HitTestBehavior.opaque,
            child: Tooltip(
              message: 'Change Password',
              child: Container(width: 32, height: 32,
                decoration: BoxDecoration(
                  gradient: AppTheme.purpleGradient,
                  borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text(
                  userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w800, fontSize: 13)))))),
          const SizedBox(width: 6),
          // Logout
          GestureDetector(
            onTap: onLogout,
            child: Container(width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.error.withOpacity(0.25))),
              child: const Icon(Icons.logout_rounded,
                  color: AppTheme.error, size: 14))),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Nav Bar  (animated pill indicator)
// ─────────────────────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final List<NavEntry> items;
  final int selectedIndex;
  const _BottomNav({required this.items, required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.sidebar,
        border: Border(top: BorderSide(color: AppTheme.border))),
      child: SafeArea(
        top: false,
        child: SizedBox(height: 58,
          child: Row(
            children: items.asMap().entries.map((e) {
              final active = selectedIndex == e.key;
              return Expanded(child: _BotItem(
                icon: e.value.icon,
                label: e.value.label,
                active: active,
                onTap: e.value.onTap,
              ));
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _BotItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _BotItem({required this.icon, required this.label,
      required this.active, required this.onTap});
  @override State<_BotItem> createState() => _BotItemState();
}

class _BotItemState extends State<_BotItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ac   = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _anim = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    if (widget.active) _ac.value = 1.0;
  }

  @override
  void didUpdateWidget(_BotItem old) {
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
            // Animated pill background
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: widget.active
                    ? AppTheme.primary.withOpacity(0.15 * _anim.value + 0.01)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20)),
              child: Icon(widget.icon, size: 20,
                color: widget.active
                    ? AppTheme.primaryLt
                    : AppTheme.textMuted)),
            const SizedBox(height: 2),
            Text(widget.label,
              style: TextStyle(
                color: widget.active
                    ? AppTheme.primaryLt : AppTheme.textMuted,
                fontSize: 9.5,
                fontWeight: widget.active
                    ? FontWeight.w700 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}
