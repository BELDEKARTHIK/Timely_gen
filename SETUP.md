# TimetableOS — First-Time Setup

## For Web (REQUIRED — run once)

The web build needs two files (`sqflite_sw.js` + `sqlite3.wasm`) copied into the `web/` folder.
Run this command once after cloning or extracting the project:

```bash
flutter pub get
dart run sqflite_common_ffi_web:setup
```

Then start the app:
```bash
flutter run -d chrome
```

**Windows users:** Double-click `setup_web.bat` — it does everything automatically.

---

## For Android/iOS (no extra setup needed)
```bash
flutter pub get
flutter run              # connects to your device/emulator
```

## For Windows Desktop
```bash
flutter pub get
flutter run -d windows
```

---

## What the web setup command does
It copies these two files from the Flutter pub cache into your `web/` folder:
- `web/sqflite_sw.js` — SQLite SharedWorker JavaScript
- `web/sqlite3.wasm` — SQLite compiled to WebAssembly

These files are required by `sqflite_common_ffi_web` to store data in the browser.
You only need to run this command **once**. The files are stable and don't change
unless you upgrade the `sqflite_common_ffi_web` package version.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Web database setup required" on startup | Run `dart run sqflite_common_ffi_web:setup` |
| Login spinner never stops | Run the setup command above, then restart |
| Blank white page | Run `flutter clean && flutter pub get` |
| Build fails | Run `flutter clean` first |
