import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class SidebarItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const SidebarItem({required this.icon, required this.label, this.onTap});
}

class AppSidebar extends StatelessWidget {
  final String userName;
  final String userRole;
  final int selectedIndex;
  final List<SidebarItem> items;
  final VoidCallback onLogout;

  const AppSidebar({
    super.key, required this.userName, required this.userRole,
    required this.selectedIndex, required this.items, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: AppTheme.sidebar,
        border: Border(right: BorderSide(color: AppTheme.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Logo
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                gradient: AppTheme.purpleGradient,
                borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.school_rounded, color: Colors.white, size: 16)),
            const SizedBox(width: 10),
            const Text('TimeTable', style: TextStyle(
              color: AppTheme.textPrimary, fontSize: 14,
              fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          ]),
        ),
        Divider(height: 1, color: AppTheme.border),
        const SizedBox(height: 14),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('GENERAL', style: TextStyle(
            color: AppTheme.textMuted, fontSize: 9.5,
            fontWeight: FontWeight.w700, letterSpacing: 1.2))),

        ...items.asMap().entries.map((e) => _AnimSideItem(
          item: e.value, selected: selectedIndex == e.key)),

        const Spacer(),
        Divider(height: 1, color: AppTheme.border),
        const SizedBox(height: 8),
        _AnimSideItem(
          item: SidebarItem(
            icon: Icons.logout_rounded, label: 'Logout', onTap: onLogout),
          selected: false, danger: true),
        const SizedBox(height: 12),
      ]),
    );
  }
}

class _AnimSideItem extends StatefulWidget {
  final SidebarItem item;
  final bool selected;
  final bool danger;
  const _AnimSideItem({required this.item, required this.selected, this.danger = false});
  @override State<_AnimSideItem> createState() => _AnimSideItemState();
}

class _AnimSideItemState extends State<_AnimSideItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  bool _hov = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 180));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    if (widget.selected) _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(_AnimSideItem old) {
    super.didUpdateWidget(old);
    if (widget.selected != old.selected) {
      widget.selected ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final col = widget.danger ? AppTheme.error
      : widget.selected ? AppTheme.textPrimary : AppTheme.textSecondary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.item.onTap,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: widget.selected
                ? AppTheme.primary.withOpacity(0.13)
                : _hov ? AppTheme.primary.withOpacity(0.06) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.selected
                  ? AppTheme.primary.withOpacity(0.25)
                  : Colors.transparent)),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: widget.selected
                    ? AppTheme.primary.withOpacity(0.22)
                    : widget.danger
                      ? AppTheme.error.withOpacity(0.10)
                      : AppTheme.cardAlt,
                  borderRadius: BorderRadius.circular(8)),
                child: Icon(widget.item.icon, size: 14,
                  color: widget.selected ? AppTheme.primaryLt
                    : widget.danger ? AppTheme.error
                    : _hov ? AppTheme.textPrimary : AppTheme.textSecondary)),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.item.label, style: TextStyle(
                color: _hov && !widget.selected ? AppTheme.textPrimary : col,
                fontSize: 12.5,
                fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500))),
              if (widget.selected)
                Container(width: 5, height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLt, shape: BoxShape.circle)),
            ]),
          ),
        ),
      ),
    );
  }
}
