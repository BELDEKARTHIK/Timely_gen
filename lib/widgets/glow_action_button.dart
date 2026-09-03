// FIXED — static button, no AnimationController
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
class GlowActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  const GlowActionButton({super.key, required this.label,
    required this.onTap, this.icon});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity, height: 52,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: AppTheme.purpleGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
            color: AppTheme.purple.withOpacity(0.35),
            blurRadius: 16, offset: const Offset(0, 6))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8)],
          Text(label, style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        ]))));
}
