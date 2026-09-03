#!/bin/bash
echo "Setting up web dependencies for TimetableOS..."
flutter pub get && \
dart run sqflite_common_ffi_web:setup && \
echo "Done! Run: flutter run -d chrome"
