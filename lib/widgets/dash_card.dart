import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

// ── Stat Card — gradient card matching reference screenshot ─────────────────
class StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final LinearGradient gradient;
  final Widget? extra;

  const StatCard({
    super.key,
    required this.value, required this.label,
    required this.icon, required this.gradient, this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withOpacity(0.30),
            blurRadius: 20, offset: const Offset(0, 8))
        ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: Colors.white, size: 19)),
            const Spacer(),
            Icon(Icons.more_horiz_rounded,
              color: Colors.white.withOpacity(0.5), size: 18),
          ]),
          const SizedBox(height: 14),
          Text(value, style: const TextStyle(
            color: Colors.white, fontSize: 34,
            fontWeight: FontWeight.w800, height: 1)),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(
            color: Colors.white.withOpacity(0.75),
            fontSize: 12.5, fontWeight: FontWeight.w500)),
          if (extra != null) ...[const SizedBox(height: 14), extra!],
        ],
      ),
    );
  }
}

// ── Section Header ───────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeader({super.key, required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(title, style: const TextStyle(
        color: AppTheme.textPrimary, fontSize: 15,
        fontWeight: FontWeight.w700)),
      const Spacer(),
      if (action != null)
        GestureDetector(
          onTap: onAction,
          child: Text(action!, style: const TextStyle(
            color: AppTheme.primaryLt, fontSize: 12, fontWeight: FontWeight.w600))),
    ]);
  }
}

// ── Info Card ────────────────────────────────────────────────────────────────
class InfoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const InfoCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border)),
      child: child,
    );
  }
}
