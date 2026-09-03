// FIXED — plain Material, no Matrix4/AnimatedContainer
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
class HoverGlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const HoverGlassCard({super.key, required this.child, this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: AppTheme.surfaceEl,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(16)),
        child: child)));
}
