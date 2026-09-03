// Design System shared components
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

// ── Stat Card (like the purple/amber cards in reference) ──────────────────
class DsStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final List<Color> gradColors;
  final Widget? bottom;

  const DsStatCard({super.key,
    required this.label, required this.value,
    required this.icon, required this.gradColors, this.bottom});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradColors,
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: gradColors.last.withOpacity(0.3),
          blurRadius: 20, offset: const Offset(0, 8))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: Colors.white.withOpacity(0.9), size: 20),
            const Spacer(),
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                shape: BoxShape.circle)),
          ]),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(
              color: Colors.white, fontSize: 32,
              fontWeight: FontWeight.w800, height: 1)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(
              color: Colors.white.withOpacity(0.75), fontSize: 13)),
          if (bottom != null) ...[const SizedBox(height: 12), bottom!],
        ],
      ),
    );
  }
}

// ── Surface Card ──────────────────────────────────────────────────────────
class DsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool elevated;

  const DsCard({super.key, required this.child,
    this.padding, this.radius = 16, this.elevated = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: elevated ? AppTheme.surfaceEl : AppTheme.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppTheme.border)),
    child: child,
  );
}

// ── Pill badge ────────────────────────────────────────────────────────────
class DsPill extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;

  const DsPill(this.text, {super.key,
    this.color = AppTheme.purple, this.filled = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: filled ? color : color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.35))),
    child: Text(text, style: TextStyle(
        color: filled ? Colors.white : color,
        fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

// ── Section header ────────────────────────────────────────────────────────
class DsSectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const DsSectionHeader(this.title, {super.key, this.action});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
    child: Row(children: [
      Text(title, style: const TextStyle(
          color: AppTheme.textPrimary, fontSize: 16,
          fontWeight: FontWeight.w800)),
      const Spacer(),
      if (action != null) action!,
    ]),
  );
}

// ── Primary button ────────────────────────────────────────────────────────
class DsButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool secondary;
  final bool small;

  const DsButton({super.key, required this.label, required this.onTap,
    this.icon, this.secondary = false, this.small = false});

  @override
  Widget build(BuildContext context) {
    final h = small ? 36.0 : 46.0;
    final px = small ? 14.0 : 20.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: h,
        padding: EdgeInsets.symmetric(horizontal: px),
        decoration: BoxDecoration(
          gradient: secondary ? null : AppTheme.purpleGradient,
          color: secondary ? AppTheme.surfaceEl : null,
          borderRadius: BorderRadius.circular(12),
          border: secondary ? Border.all(color: AppTheme.border) : null,
          boxShadow: secondary ? null : [BoxShadow(
            color: AppTheme.purple.withOpacity(0.3),
            blurRadius: 12, offset: const Offset(0, 4))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: small ? 14 : 16),
            SizedBox(width: small ? 5 : 7)],
          Text(label, style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700,
              fontSize: small ? 12 : 13)),
        ]),
      ),
    );
  }
}

// ── Sidebar nav item ──────────────────────────────────────────────────────
class DsNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const DsNavItem({super.key, required this.icon, required this.label,
    required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: active ? AppTheme.purpleGradient : null,
          color: active ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active ? [BoxShadow(
            color: AppTheme.purple.withOpacity(0.3),
            blurRadius: 12, offset: const Offset(0, 4))] : null),
        child: Row(children: [
          Icon(icon, color: active ? Colors.white : AppTheme.textSecondary,
              size: 18),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(
              color: active ? Colors.white : AppTheme.textSecondary,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13)),
        ]),
      ),
    );
  }
}

// ── Loading spinner ───────────────────────────────────────────────────────
class DsLoader extends StatelessWidget {
  const DsLoader({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(
        color: AppTheme.purple, strokeWidth: 2));
}
