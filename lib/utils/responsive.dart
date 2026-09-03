import 'package:flutter/material.dart';

/// Breakpoints — single source of truth for the whole app.
///
///  Desktop  ≥ 720 px  →  full sidebar
///  Mobile   < 720 px  →  bottom nav bar, no sidebar
class R {
  static bool isDesktop(BuildContext ctx) =>
      MediaQuery.sizeOf(ctx).width >= 720;
  static bool isMobile(BuildContext ctx) =>
      MediaQuery.sizeOf(ctx).width < 720;
}
