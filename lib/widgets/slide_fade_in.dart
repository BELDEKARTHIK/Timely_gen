// FIXED — passthrough, no SlideTransition
import 'package:flutter/material.dart';
class SlideFadeIn extends StatelessWidget {
  final Widget child;
  final int index;
  const SlideFadeIn({super.key, required this.child, this.index = 0});
  @override Widget build(BuildContext context) => child;
}
