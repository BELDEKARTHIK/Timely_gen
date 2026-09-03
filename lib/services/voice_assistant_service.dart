import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import '../services/database_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  VOICE ASSISTANT SERVICE
//
//  Windows / Linux / macOS  →  TEXT-ONLY mode (no mic, no TTS)
//                               Chat panel still works via keyboard input.
//  Android / iOS            →  Full voice via MethodChannel to Android STT/TTS
//                               (no extra Flutter packages — uses Android APIs
//                               directly through a lightweight channel).
//
//  Why no flutter_tts / speech_to_text packages?
//  flutter_tts requires nuget.exe on Windows which is not standard.
//  We avoid that entirely by driving Android STT/TTS through a MethodChannel
//  defined in MainActivity.kt — zero Windows build impact.
// ══════════════════════════════════════════════════════════════════════════════

enum AssistantIntent { read, navigate, action, help, unknown }

class AssistantMessage {
  final String  text;
  final bool    isUser;
  final DateTime time;
  final AssistantIntent? intent;
  AssistantMessage({
    required this.text, required this.isUser,
    required this.time,  this.intent,
  });
}

class NavAction {
  final int?    tabIndex;
  final String? screen;
  const NavAction({this.tabIndex, this.screen});
}

// ── Platform helpers ─────────────────────────────────────────────────────────
bool get _isMobile => Platform.isAndroid || Platform.isIOS;

const _voiceChannel = MethodChannel('com.college.timetable_app/voice');

class VoiceAssistantService extends ChangeNotifier {

  static const _geminiApiKey = 'AIzaSyD_VpKXLXIBxHk1j2ZCYi26_AYlXl4h-Y8';
  static const _geminiUrl    =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-1.5-flash:generateContent';

  final _db = DatabaseService();

  bool   _isListening  = false;
  bool   _isSpeaking   = false;
  bool   _isProcessing = false;
  String _liveText     = '';
  final  List<AssistantMessage> _messages = [];
  NavAction? _pendingNav;

  bool get isListening   => _isListening;
  bool get isSpeaking    => _isSpeaking;
  bool get isProcessing  => _isProcessing;
  bool get isReady       => _isMobile;        // STT only on Android
  bool get voiceAvailable=> _isMobile;        // mic button only on Android
  String get liveText    => _liveText;
  List<AssistantMessage> get messages => List.unmodifiable(_messages);
  NavAction? get pendingNav => _pendingNav;
  void clearPendingNav() { _pendingNav = null; }

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (!_isMobile) return; // Windows: nothing to initialise
    // Register result listener from Android STT
    _voiceChannel.setMethodCallHandler(_handleAndroidCallback);
  }

  // Called by Android Kotlin when STT/TTS events fire
  Future<void> _handleAndroidCallback(MethodCall call) async {
    switch (call.method) {
      case 'onPartialResult':
        _liveText = call.arguments as String? ?? '';
        notifyListeners();
        break;
      case 'onFinalResult':
        final text = call.arguments as String? ?? '';
        _isListening = false;
        _liveText    = '';
        notifyListeners();
        if (text.trim().isNotEmpty) _processQuery(text.trim());
        break;
      case 'onSttError':
        _isListening = false;
        _liveText = '';
        final errMsg = call.arguments as String? ?? '';
        // 'no_match' is a soft error (silence/timeout) — just reset quietly
        if (errMsg != 'no_match' && errMsg.isNotEmpty) {
          _addMessage('Mic error: $errMsg', isUser: false);
        }
        notifyListeners();
        break;
      case 'onTtsDone':
        _isSpeaking = false;
        notifyListeners();
        break;
    }
  }

  // ── Start listening ────────────────────────────────────────────────────────
  Future<void> startListening() async {
    if (!_isMobile || _isListening) return;
    _liveText    = '';
    _isListening = true;
    notifyListeners();
    try {
      await _voiceChannel.invokeMethod('startListening');
    } catch (_) {
      _isListening = false;
      notifyListeners();
    }
  }

  Future<void> stopListening() async {
    if (!_isMobile) return;
    try { await _voiceChannel.invokeMethod('stopListening'); } catch (_) {}
    _isListening = false;
    notifyListeners();
  }

  // ── Text input (keyboard — works on ALL platforms) ────────────────────────
  Future<void> sendText(String text) async {
    if (text.trim().isEmpty) return;
    _processQuery(text.trim());
  }

  // ── Core pipeline ─────────────────────────────────────────────────────────
  Future<void> _processQuery(String query) async {
    _addMessage(query, isUser: true);
    _isProcessing = true;
    _liveText     = '';
    notifyListeners();

    try {
      // Navigation intents — no API call needed
      final nav = _handleNavIntent(query);
      if (nav != null) {
        _pendingNav = nav;
        final reply = _navReply(query);
        _addMessage(reply, isUser: false, intent: AssistantIntent.navigate);
        _isProcessing = false;
        notifyListeners();
        await _speak(reply);
        return;
      }

      // DB context + Gemini
      final context = await _buildContext(query);
      final reply   = await _callGemini(query, context);
      _addMessage(reply, isUser: false, intent: _detectIntent(query));
      _isProcessing = false;
      notifyListeners();
      await _speak(reply);

    } catch (e) {
      const err = 'Sorry, I encountered an error. Please try again.';
      _addMessage(err, isUser: false);
      _isProcessing = false;
      notifyListeners();
    }
  }

  // ── Intent detection ──────────────────────────────────────────────────────
  AssistantIntent _detectIntent(String q) {
    final l = q.toLowerCase();
    if (_isNav(l)) return AssistantIntent.navigate;
    if (l.contains('generate') || l.contains('export') ||
        l.contains('mark')     || l.contains('download'))
      return AssistantIntent.action;
    if (l.contains('how') || l.contains('what is') || l.contains('help'))
      return AssistantIntent.help;
    return AssistantIntent.read;
  }

  bool _isNav(String q) =>
    q.contains('go to')    || q.contains('open')      || q.contains('navigate') ||
    q.contains('show me')  || q.contains('take me')   || q.contains('switch to') ||
    q.contains('dashboard')|| q.contains('today tab') || q.contains('timetable tab') ||
    q.contains('import tab')|| q.contains('generate tab') ||
    q.contains('attendance screen') || q.contains('history') || q.contains('overview');

  NavAction? _handleNavIntent(String q) {
    final l = q.toLowerCase();
    if (!_isNav(l)) return null;
    if (l.contains('import'))     return const NavAction(tabIndex: 1, screen: 'import');
    if (l.contains('generat'))    return const NavAction(tabIndex: 2, screen: 'generate');
    if (l.contains('timetable'))  return const NavAction(tabIndex: 3, screen: 'timetable');
    if (l.contains('dashboard'))  return const NavAction(tabIndex: 0, screen: 'dashboard');
    if (l.contains('today'))      return const NavAction(tabIndex: 0, screen: 'today');
    if (l.contains('history'))    return const NavAction(tabIndex: 2, screen: 'history');
    if (l.contains('overview'))   return const NavAction(tabIndex: 0, screen: 'overview');
    if (l.contains('attendance')) return const NavAction(tabIndex: 2, screen: 'attendance');
    return null;
  }

  String _navReply(String q) {
    final l = q.toLowerCase();
    if (l.contains('import'))     return 'Opening Import Data tab.';
    if (l.contains('generat'))    return 'Switching to Generate tab.';
    if (l.contains('timetable'))  return 'Opening Timetable Viewer.';
    if (l.contains('dashboard'))  return 'Going to Dashboard.';
    if (l.contains('today'))      return "Showing today's classes.";
    if (l.contains('history'))    return 'Opening attendance history.';
    if (l.contains('overview'))   return 'Showing overview.';
    if (l.contains('attendance')) return 'Opening Attendance screen.';
    return 'Navigating now.';
  }

  // ── DB context builder ────────────────────────────────────────────────────
  Future<String> _buildContext(String query) async {
    final l = query.toLowerCase();
    final b = StringBuffer();
    try {
      final faculty  = await _db.getAllFaculty();
      final students = await _db.getAllStudents();
      final subjects = await _db.getAllSubjects();
      final entries  = await _db.getAllTimetableEntries();

      b.writeln('=== LIVE DB ===');
      b.writeln('Faculty: ${faculty.length}');
      b.writeln('Students: ${students.length}');
      b.writeln('Subjects: ${subjects.length}');
      b.writeln('Timetable slots: ${entries.length}');

      if (l.contains('faculty') || l.contains('teacher') || l.contains('who teaches')) {
        b.writeln('\nFACULTY:');
        for (final f in faculty.take(20)) b.writeln('- ${f.name} (${f.email})');
        b.writeln('\nSUBJECTS:');
        for (final s in subjects.take(30)) {
          final f = faculty.firstWhere((f) => f.id == s.facultyId,
              orElse: () => Faculty(id:'', name:'Unknown', email:'', passwordHash:''));
          b.writeln('- ${s.name}|${s.section} Yr${s.year}|${f.name}|${s.type}');
        }
      }

      if (l.contains('student') || l.contains('how many') || l.contains('section')) {
        b.writeln('\nSECTIONS:');
        final m = <String, int>{};
        for (final s in students) {
          final k = 'Sec ${s.section} Yr${s.year}';
          m[k] = (m[k] ?? 0) + 1;
        }
        m.forEach((k, v) => b.writeln('- $k: $v students'));
      }

      if (l.contains('timetable') || l.contains('schedule') ||
          l.contains('period')    || l.contains('class') || l.contains('lab')) {
        final dow = DateTime.now().weekday;
        if (dow <= 6) {
          final todayE = entries.where((e) => e.dayOfWeek == dow).toList();
          b.writeln('\nTODAY (${_dn(dow)}): ${todayE.length} entries');
          for (final e in todayE.take(15)) {
            final sn = subjects.firstWhere((s) => s.id == e.subjectId,
                orElse: () => Subject(id:'', name: e.specialLabel ?? '?', code:'',
                  section: e.section, year: e.year, facultyId:'', type:'Theory',
                  periodsPerWeek: 1)).name;
            final fn = faculty.firstWhere((f) => f.id == e.facultyId,
                orElse: () => Faculty(id:'', name:'', email:'', passwordHash:'')).name;
            b.writeln('P${e.periodNumber}|${e.section} Yr${e.year}|$sn'
                '${e.isLab?" [LAB]":""}${e.batch>0?" B${e.batch}":""}${fn.isNotEmpty?"|$fn":""}');
          }
        }
      }

      if (l.contains('attendance') || l.contains('percent') ||
          l.contains('below 75')   || l.contains('shortage')) {
        final recs = <AttendanceRecord>[];
        for (final s in students.take(10)) {
          recs.addAll(await _db.getAttendanceForStudent(s.id));
        }
        if (recs.isNotEmpty) {
          b.writeln('\nATTENDANCE (sample):');
          final ps = <String, Map<String, List<bool>>>{};
          for (final r in recs) {
            ps.putIfAbsent(r.studentId, () => {});
            ps[r.studentId]!.putIfAbsent(r.subjectId, () => []);
            ps[r.studentId]![r.subjectId]!.add(r.isPresent);
          }
          for (final sid in ps.keys.take(5)) {
            final stu = students.firstWhere((s) => s.id == sid,
                orElse: () => Student(id:'', rollNumber:'?', name:'?',
                    section:'', year: 1, batch: 0));
            b.writeln('${stu.name}(${stu.rollNumber}):');
            ps[sid]!.forEach((subId, bools) {
              final sn = subjects.firstWhere((s) => s.id == subId,
                  orElse: () => Subject(id:'', name: subId, code:'', section:'',
                      year: 1, facultyId:'', type:'Theory', periodsPerWeek: 1)).name;
              final pct = bools.isEmpty ? 0.0
                  : bools.where((b) => b).length / bools.length * 100;
              b.writeln('  $sn: ${pct.toStringAsFixed(0)}%'
                  ' (${bools.where((b)=>b).length}/${bools.length})');
            });
          }
        }
      }

      final now = DateTime.now();
      b.writeln('\nTIME: ${now.hour}:${now.minute.toString().padLeft(2,'0')} ${_dn(now.weekday)}');
      b.writeln('SCHEDULE: Mon-Sat P1=9:15 P2=10:10 P3=11:10 P4=12:00 P5=1:30 P6=2:20 P7=3:10');

    } catch (e) { b.writeln('Context error: $e'); }
    return b.toString();
  }

  String _dn(int d) =>
    ['','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][d.clamp(0,7)];

  // ── Gemini ────────────────────────────────────────────────────────────────
  Future<String> _callGemini(String query, String ctx) async {
    final prompt =
        'You are a helpful voice assistant for a college timetable and '
        'attendance management app. The live database context is below. '
        'Answer in 1-3 plain sentences. No markdown, no bullets, no asterisks. '
        'Be direct and concise.\n\n$ctx\n\nQuestion: $query';

    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final res = await http.post(
          Uri.parse('$_geminiUrl?key=$_geminiApiKey'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'contents': [{'parts': [{'text': prompt}]}],
            'generationConfig': {
              'temperature': 0.3,
              'maxOutputTokens': 256,
              'topP': 0.8,
            },
          }),
        ).timeout(const Duration(seconds: 20));

        if (res.statusCode == 200) {
          final j = jsonDecode(res.body);
          final text =
              j['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
          if (text != null && text.trim().isNotEmpty) return text.trim();
          return _localAnswer(query, ctx);
        } else if (res.statusCode == 401 || res.statusCode == 403) {
          return 'API key invalid. Please check your Gemini API key.';
        } else if (res.statusCode == 429) {
          return 'Too many requests. Please wait a moment and try again.';
        } else {
          if (attempt < 2) {
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
          return 'Gemini error (HTTP ${res.statusCode}). '
              'Check internet on device. Using offline answers.';
        }
      } catch (_) {
        if (attempt < 2) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        return _localAnswer(query, ctx);
      }
    }
    return _localAnswer(query, ctx);
  }

  // ── Offline fallback ──────────────────────────────────────────────────────
  String _localAnswer(String query, String ctx) {
    final q = query.toLowerCase();
    final lines = ctx.split('\n');

    int getVal(String prefix) {
      for (final l in lines) {
        if (l.startsWith(prefix)) {
          return int.tryParse(l.split(':').last.trim()) ?? 0;
        }
      }
      return 0;
    }

    final faculty  = getVal('Faculty:');
    final students = getVal('Students:');
    final subjects = getVal('Subjects:');
    final slots    = getVal('Timetable slots:');

    if (q.contains('faculty') || q.contains('teacher'))
      return 'There are $faculty faculty members in the system.';
    if (q.contains('student'))
      return 'There are $students students enrolled.';
    if (q.contains('subject'))
      return 'There are $subjects subjects configured.';
    if (q.contains('slot') || q.contains('timetable') || q.contains('schedule'))
      return 'The timetable has $slots scheduled slots across all sections.';
    if (q.contains('hello') || q.contains('hi'))
      return 'Hello! I am your timetable assistant. '
          'I have data for $faculty faculty and $students students.';
    if (q.contains('today') || q.contains('class'))
      return "There are $slots total timetable slots. "
          "Open the Timetable tab to see today's schedule.";
    if (q.contains('help') || q.contains('what can'))
      return 'Ask me about timetables, attendance, faculty, or students. '
          'I have $faculty faculty and $students students in the system.';

    return 'I have data for $faculty faculty, $students students, '
        'and $subjects subjects. '
        'Enable internet for more detailed AI responses.';
  }


  // ── TTS via MethodChannel ─────────────────────────────────────────────────
  Future<void> _speak(String text) async {
    if (!_isMobile || text.trim().isEmpty) return;
    final clean = text
        .replaceAll('**', '').replaceAll('*', '')
        .replaceAll('#',  '').replaceAll('`', '').trim();
    _isSpeaking = true;
    notifyListeners();
    try {
      await _voiceChannel.invokeMethod('speak', clean);
    } catch (_) {
      _isSpeaking = false;
      notifyListeners();
    }
  }

  Future<void> stopSpeaking() async {
    if (!_isMobile) return;
    try { await _voiceChannel.invokeMethod('stopSpeaking'); } catch (_) {}
    _isSpeaking = false;
    notifyListeners();
  }

  void _addMessage(String text, {required bool isUser, AssistantIntent? intent}) {
    _messages.add(AssistantMessage(
      text: text, isUser: isUser, time: DateTime.now(), intent: intent,
    ));
    notifyListeners();
  }

  void clearHistory() { _messages.clear(); notifyListeners(); }

  @override
  void dispose() {
    stopSpeaking();
    stopListening();
    super.dispose();
  }
}
