// ══════════════════════════════════════════════════════════════════════════════
//  ProfileDropdown — tappable avatar that shows an overlay panel with
//  user details + Change Password + Logout actions.
//
//  Works on web (desktop) and Android/iOS (mobile) without any platform checks.
//  Uses OverlayEntry so it floats above all content and doesn't affect layout.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class ProfileDropdown extends StatefulWidget {
  /// Display name (used for avatar letter + title)
  final String name;

  /// Subtitle line shown under the name (e.g. "Employee ID: TCH001")
  final String subtitle;

  /// Extra detail rows: [(label, value), ...]
  final List<(String, String)> details;

  /// Avatar gradient — use AppTheme.purpleGradient or AppTheme.orangeGradient
  final LinearGradient gradient;

  /// Called when "Change Password" is tapped
  final VoidCallback onChangePassword;

  /// Called when "Logout" is tapped
  final VoidCallback onLogout;

  /// If true, only the avatar circle is shown (no name text) — for tight spaces
  final bool compact;

  const ProfileDropdown({
    super.key,
    required this.name,
    required this.subtitle,
    required this.details,
    required this.gradient,
    required this.onChangePassword,
    required this.onLogout,
    this.compact = false,
  });

  @override
  State<ProfileDropdown> createState() => _ProfileDropdownState();
}

class _ProfileDropdownState extends State<ProfileDropdown>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlay;
  late AnimationController _ac;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _scaleAnim = CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic);
    _fadeAnim  = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _removeOverlay();
    _ac.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_overlay != null) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos    = box.localToGlobal(Offset.zero);
    final size   = box.size;
    final screen = MediaQuery.sizeOf(_key.currentContext!);

    // Panel width — 280 on desktop, full width on tiny screens
    const panelW = 280.0;
    // Position right-aligned with avatar, but clamp to screen
    double left = pos.dx + size.width - panelW;
    if (left < 8) left = 8;
    if (left + panelW > screen.width - 8) left = screen.width - panelW - 8;

    _overlay = OverlayEntry(builder: (ctx) => _DropPanel(
      left:             left,
      top:              pos.dy + size.height + 6,
      panelW:           panelW,
      name:             widget.name,
      subtitle:         widget.subtitle,
      details:          widget.details,
      gradient:         widget.gradient,
      scaleAnim:        _scaleAnim,
      fadeAnim:         _fadeAnim,
      onChangePassword: () {
        _close();
        widget.onChangePassword();
      },
      onLogout: () {
        _close();
        widget.onLogout();
      },
      onDismiss: _close,
    ));

    Overlay.of(_key.currentContext!).insert(_overlay!);
    _ac.forward(from: 0);
  }

  void _close() async {
    await _ac.reverse();
    _removeOverlay();
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.name.isNotEmpty
        ? widget.name[0].toUpperCase() : '?';
    return GestureDetector(
      key:      _key,
      onTap:    _toggle,
      behavior: HitTestBehavior.opaque,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(initial,
            style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w800, fontSize: 14)))),
        if (!widget.compact) ...[
          const SizedBox(width: 6),
          Text(widget.name.split(' ').first,
            style: const TextStyle(color: AppTheme.textPrimary,
              fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded,
            color: AppTheme.textMuted, size: 16),
        ],
      ]),
    );
  }
}

// ── The floating panel ────────────────────────────────────────────────────────
class _DropPanel extends StatelessWidget {
  final double left, top, panelW;
  final String name, subtitle;
  final List<(String, String)> details;
  final LinearGradient gradient;
  final Animation<double> scaleAnim, fadeAnim;
  final VoidCallback onChangePassword, onLogout, onDismiss;

  const _DropPanel({
    required this.left, required this.top, required this.panelW,
    required this.name, required this.subtitle, required this.details,
    required this.gradient,
    required this.scaleAnim, required this.fadeAnim,
    required this.onChangePassword, required this.onLogout,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Dismiss backdrop
      Positioned.fill(child: GestureDetector(
        onTap: onDismiss,
        behavior: HitTestBehavior.opaque,
        child: const ColoredBox(color: Colors.transparent))),

      // Panel
      Positioned(
        left: left, top: top, width: panelW,
        child: FadeTransition(
          opacity: fadeAnim,
          child: ScaleTransition(
            scale: scaleAnim,
            alignment: Alignment.topRight,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 20, offset: const Offset(0, 8))]),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: gradient.scale(0.6),
                        borderRadius: const BorderRadius.only(
                          topLeft:  Radius.circular(13),
                          topRight: Radius.circular(13))),
                      child: Row(children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            gradient: gradient,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.25),
                              width: 2)),
                          child: Center(child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w900, fontSize: 18)))),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800, fontSize: 14),
                              overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(subtitle,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 11),
                              overflow: TextOverflow.ellipsis),
                          ])),
                      ])),

                    // Detail rows
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: details.map((d) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            SizedBox(width: 90,
                              child: Text(d.$1,
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600))),
                            Expanded(child: Text(d.$2,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 11.5),
                              overflow: TextOverflow.ellipsis)),
                          ]))).toList())),

                    const Divider(color: AppTheme.border, height: 1),

                    // Actions
                    _Action(
                      icon:  Icons.lock_outline_rounded,
                      label: 'Change Password',
                      color: AppTheme.primary,
                      onTap: onChangePassword),
                    const Divider(color: AppTheme.border, height: 1, indent: 16),
                    _Action(
                      icon:  Icons.logout_rounded,
                      label: 'Logout',
                      color: AppTheme.error,
                      onTap: onLogout),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Action({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(
            color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ])),
    );
  }
}
