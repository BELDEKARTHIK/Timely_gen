// ── Platform-aware database initialisation ────────────────────────────────────
// Web    : sqflite_common_ffi_web (IndexedDB-backed)
// Windows/Linux : sqflite_common_ffi (native FFI)
// Android/iOS/macOS : sqflite (default — no init needed)

import 'package:flutter/foundation.dart' show kIsWeb;

// Conditional imports — only the matching file is compiled for each target
import 'db_init_stub.dart'
    if (dart.library.html) 'db_init_web.dart'
    if (dart.library.io)   'db_init_io.dart';

class DbInit {
  static Future<void> init() => initDatabase();
}
