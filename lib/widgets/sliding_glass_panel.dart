// FIXED — instant width swap, no AnimatedContainer
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
class SlidingGlassPanel extends StatefulWidget {
  final Widget child;
  const SlidingGlassPanel({super.key, required this.child});
  @override State<SlidingGlassPanel> createState() => _SlidingGlassPanelState();
}
class _SlidingGlassPanelState extends State<SlidingGlassPanel> {
  bool _expanded = true;
  @override
  Widget build(BuildContext context) => Container(
    width: _expanded ? 280 : 52,
    color: AppTheme.sidebar,
    child: Column(children: [
      Align(alignment: Alignment.centerRight,
        child: IconButton(
          icon: Icon(_expanded ? Icons.chevron_left : Icons.chevron_right,
              color: AppTheme.textSecondary),
          onPressed: () => setState(() => _expanded = !_expanded))),
      if (_expanded) Expanded(child: widget.child),
    ]));
}
