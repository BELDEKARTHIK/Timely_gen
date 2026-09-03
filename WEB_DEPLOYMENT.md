# TimetableOS — Web Deployment Guide

## ⚠️ IMPORTANT: How to Build & Serve Correctly

### Step 1 — Build
```bash
cd D:\Projects\timetable_app
flutter clean
flutter pub get
flutter build web --release --base-href /
```

### Step 2 — Serve (choose one method)

#### Option A: Flutter's built-in server (EASIEST — just for testing)
```bash
flutter run -d chrome
```
This is the RECOMMENDED way to test locally. Flutter handles all paths correctly.

#### Option B: Python local server (serve from build/web root)
```bash
# Navigate INTO the build/web folder first
cd build\web
python -m http.server 8000
```
Then open: **http://localhost:8000**  (NOT /build/web/)

#### Option C: Netlify (free hosting, drag & drop)
1. Build with: `flutter build web --release --base-href /`
2. Drag the entire `build\web\` folder to https://app.netlify.com
3. Done — get instant URL

#### Option D: Firebase Hosting
```bash
npm install -g firebase-tools
firebase login
firebase init hosting
# Public directory: build/web
# Single-page app: YES
# Overwrite index.html: NO
flutter build web --release --base-href /
firebase deploy
```

---

## Common Blank Page Causes & Fixes

| Cause | Fix |
|---|---|
| Serving from wrong path | Navigate to `localhost:8000` not `localhost:8000/build/web/` |
| Wrong base href | Always build with `--base-href /` |
| Browser cache | Hard refresh: Ctrl+Shift+R |
| CORS error | Use `flutter run -d chrome` for local testing |
| Missing sqlite3.wasm | Run `flutter pub get` then rebuild |

---

## Files in build/web/ after successful build
- `index.html` — entry point
- `main.dart.js` or `flutter.js` — compiled Dart code
- `sqlite3.wasm` — SQLite WebAssembly (auto-copied by sqflite_common_ffi_web)
- `assets/` — app assets
- `icons/` — app icons

If `sqlite3.wasm` is MISSING from build/web/, the app will show a blank page.
Run `flutter pub get` and rebuild to fix.
