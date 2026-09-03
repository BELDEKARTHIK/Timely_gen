@echo off
echo Setting up web dependencies for TimetableOS...
echo.

REM Get packages
call flutter pub get
if errorlevel 1 goto :error

REM Copy sqflite web worker files into web/ folder
REM This is REQUIRED for the web build to work
call dart run sqflite_common_ffi_web:setup
if errorlevel 1 goto :error

echo.
echo Web setup complete! Files copied to web/ folder:
echo   - web/sqflite_sw.js
echo   - web/sqlite3.wasm
echo.
echo Now run: flutter run -d chrome
goto :end

:error
echo Setup failed. Make sure Flutter is installed and in your PATH.
:end
