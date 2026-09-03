import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

// IO-only imports — not compiled on web
// Platform file helpers
import 'excel_io.dart'
    if (dart.library.html) 'excel_web.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  XlsxFile  — result of parsing an xlsx, returned to the UI
// ─────────────────────────────────────────────────────────────────────────────
class XlsxFile {
  final String path;
  final Map<String, List<List<String>>> _data;

  XlsxFile(this.path, this._data)
      : sheetNames = _data.keys.toList();

  final List<String> sheetNames;
  List<List<String>> rows(String sheetName) => _data[sheetName] ?? [];
}

typedef ExcelFile = XlsxFile;

// ─────────────────────────────────────────────────────────────────────────────
//  ExcelService
// ─────────────────────────────────────────────────────────────────────────────
class ExcelService {
  final _uuid = const Uuid();
  final _ch   = const MethodChannel('com.college.timetable_app/file');

  // ── Pick & load Excel ──────────────────────────────────────────────────────
  Future<XlsxFile?> pickAndLoadExcel() async {
    if (kIsWeb) {
      return _pickAndLoadWeb();
    } else if (isAndroidPlatform()) {
      return _pickAndLoadAndroid();
    } else {
      return _pickAndLoadDesktop();
    }
  }

  // Web path — file_picker returns bytes directly
  Future<XlsxFile?> _pickAndLoadWeb() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final bytes = result.files.single.bytes;
    if (bytes == null) return null;
    return _parseXlsxBytes(bytes, 'uploaded.xlsx');
  }

  // Android path — Kotlin MethodChannel
  Future<XlsxFile?> _pickAndLoadAndroid() async {
    final raw = await _ch.invokeMethod<dynamic>('pickExcelFile');
    if (raw == null) return null;
    return _parseJsonResponse(raw as String);
  }

  // Desktop path — file_picker returns bytes, then parse
  Future<XlsxFile?> _pickAndLoadDesktop() async {
    final bytes = await pickFileBytes();
    if (bytes == null) return null;
    return _parseXlsxBytes(bytes, 'imported.xlsx');
  }

  // Parse JSON string returned by Kotlin
  XlsxFile _parseJsonResponse(String jsonStr) {
    final Map<String, dynamic> json =
        jsonDecode(jsonStr) as Map<String, dynamic>;
    final sheetsJson = json['sheets'] as List<dynamic>;
    if (sheetsJson.isEmpty) throw Exception('No sheets found in file.');
    final data = <String, List<List<String>>>{};
    for (final s in sheetsJson) {
      final sheetMap = s as Map<String, dynamic>;
      final name     = sheetMap['name'] as String;
      final rowsRaw  = sheetMap['rows'] as List<dynamic>;
      data[name]     = rowsRaw.map((r) {
        final row = r as List<dynamic>;
        return row.map((c) => (c ?? '').toString()).toList();
      }).toList();
    }
    return XlsxFile('imported', data);
  }

  // Pure Dart xlsx parser (ZIP + XML)
  XlsxFile _parseXlsxBytes(List<int> bytes, String path) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files   = <String, String>{};
    for (final f in archive) {
      if (!f.isFile) continue;
      try {
        files[f.name] = utf8.decode(f.content as List<int>, allowMalformed: true);
      } catch (_) {}
    }

    final sharedStrings = _parseSharedStrings(files['xl/sharedStrings.xml'] ?? '');
    final sheetNames    = _parseSheetNames(files['xl/workbook.xml'] ?? '');
    final sheetPaths    = _parseSheetPaths(files['xl/_rels/workbook.xml.rels'] ?? '');

    final data = <String, List<List<String>>>{};
    for (int i = 0; i < sheetNames.length; i++) {
      final name = sheetNames[i];
      final path_ = sheetPaths.length > i ? sheetPaths[i] : 'xl/worksheets/sheet${i+1}.xml';
      final xml  = files[path_] ?? files['xl/worksheets/sheet${i+1}.xml'] ?? '';
      if (xml.isNotEmpty) data[name] = _parseSheet(xml, sharedStrings);
    }

    if (data.isEmpty) {
      // fallback: just parse sheet1
      final xml = files['xl/worksheets/sheet1.xml'] ?? '';
      if (xml.isNotEmpty) data['Sheet1'] = _parseSheet(xml, sharedStrings);
    }

    return XlsxFile(path, data);
  }

  List<String> _parseSharedStrings(String xml) {
    final result = <String>[];
    if (xml.isEmpty) return result;
    final siRe = RegExp(r'<si>(.*?)</si>', dotAll: true);
    final tRe  = RegExp(r'<t[^>]*>([^<]*)</t>');
    for (final si in siRe.allMatches(xml)) {
      final buf = StringBuffer();
      for (final t in tRe.allMatches(si.group(1) ?? '')) {
        buf.write(_unescape(t.group(1) ?? ''));
      }
      result.add(buf.toString());
    }
    return result;
  }

  List<String> _parseSheetNames(String xml) {
    if (xml.isEmpty) return [];
    return RegExp(r'<sheet\s[^>]*name="([^"]*)"')
        .allMatches(xml)
        .map((m) => m.group(1) ?? 'Sheet')
        .toList();
  }

  List<String> _parseSheetPaths(String xml) {
    if (xml.isEmpty) return [];
    final paths = <String>[];
    for (final m in RegExp(r'<Relationship[^>]*Target="([^"]*)"[^>]*Id="rId(\d+)"',
            dotAll: true)
        .allMatches(xml)) {
      var t = m.group(1) ?? '';
      if (!t.startsWith('xl/')) t = 'xl/$t';
      paths.add(t);
    }
    return paths;
  }

  List<List<String>> _parseSheet(String xml, List<String> ss) {
    final rows = <List<String>>[];
    final rowRe  = RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true);
    final cellRe = RegExp(r'<c\b([^>]*)>(.*?)</c>', dotAll: true);
    final vRe    = RegExp(r'<v>([^<]*)</v>');
    final tRe    = RegExp(r'<t>([^<]*)</t>');

    for (final rowMatch in rowRe.allMatches(xml)) {
      final cells = <String>[];
      int lastCol = -1;
      for (final cellMatch in cellRe.allMatches(rowMatch.group(1) ?? '')) {
        final attrs = cellMatch.group(1) ?? '';
        final body  = cellMatch.group(2) ?? '';
        final rAttr = RegExp(r'\br="([A-Z]+)(\d+)"').firstMatch(attrs);
        final tAttr = RegExp(r'\bt="([^"]*)"').firstMatch(attrs);
        final colIdx = rAttr != null ? _colIdx(rAttr.group(1)!) : lastCol + 1;
        while (cells.length < colIdx) cells.add('');
        final typ = tAttr?.group(1) ?? '';
        String val = '';
        if (typ == 's') {
          final vi = int.tryParse(vRe.firstMatch(body)?.group(1) ?? '') ?? -1;
          val = (vi >= 0 && vi < ss.length) ? ss[vi] : '';
        } else if (typ == 'inlineStr') {
          val = _unescape(tRe.firstMatch(body)?.group(1) ?? '');
        } else {
          val = _unescape(vRe.firstMatch(body)?.group(1) ?? '');
        }
        cells.add(val);
        lastCol = colIdx;
      }
      if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
    }
    return rows;
  }

  int _colIdx(String letters) {
    int col = 0;
    for (final ch in letters.codeUnits) col = col * 26 + (ch - 65 + 1);
    return col - 1;
  }

  String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  // ── Parse faculty sheet ────────────────────────────────────────────────────
  List<FacultyImportRow> parseFacultySheet(XlsxFile file, String sheetName) {
    final allRows = file.rows(sheetName);
    if (allRows.length < 2) return [];

    final headers = _headers(allRows[0]);

    final result = <FacultyImportRow>[];
    for (int r = 1; r < allRows.length; r++) {
      final row  = allRows[r];
      String c(String h) => _cell(row, headers, h);
      final name = c('Faculty Name');
      if (name.isEmpty) continue;
      final rawEmpId = c('Employee ID').trim();
      final empId = rawEmpId.isNotEmpty
          ? rawEmpId.toUpperCase()
          : name.toUpperCase().replaceAll(' ', '_').replaceAll('.', '');
      result.add(FacultyImportRow(
        employeeId:            empId,
        facultyName:           name,
        subject:               c('Subject'),
        section:               c('Section'),
        year:                  _parseYear(c('Year')),
        type:                  c('Type').isEmpty ? 'Theory' : c('Type'),
        periodsPerWeek:        int.tryParse(c('Periods Per Week')) ?? 4,
        isIncharge:            c('Is Incharge').toLowerCase() == 'yes',
        batch:                 int.tryParse(c('Batch')) ?? 0,
        email:                 c('Email'),
        preference:            c('Preference'),
        labDividedIntoBatches: c('Lab Divided Into 2 Batches').toLowerCase() == 'yes',
      ));
    }
    return result;
  }

  ParsedFacultyData convertFacultyRows(List<FacultyImportRow> rows) {
    final facultyMap = <String, Faculty>{};
    final subjects   = <Subject>[];

    for (final row in rows) {
      if (row.facultyName.isEmpty) continue;
      facultyMap.putIfAbsent(row.employeeId, () {
        return Faculty(
          id:           row.employeeId,
          employeeId:   row.employeeId,
          name:         row.facultyName,
          email:        row.email.isNotEmpty
              ? row.email
              : '${row.employeeId.toLowerCase()}@college.edu',
          passwordHash: row.employeeId,
        );
      });

      final faculty = facultyMap[row.employeeId]!;
      final subjectId =
          '${row.employeeId}_${_code(row.subject)}_${row.section}_${row.year}_${row.batch}';
      subjects.add(Subject(
        id:                   subjectId,
        name:                 row.subject,
        code:                 _code(row.subject),
        section:              row.section,
        year:                 row.year,
        facultyId:            faculty.id,
        type:                 row.type,
        periodsPerWeek:       row.periodsPerWeek,
        isIncharge:           row.isIncharge,
        batch:                row.batch,
        labDividedIntoBatches: row.labDividedIntoBatches,
        preference:           row.preference,
      ));
    }
    return ParsedFacultyData(
      faculty:  facultyMap.values.toList(),
      subjects: subjects,
    );
  }

  // ── Parse student sheet ────────────────────────────────────────────────────
  List<Student> parseStudentSheet(XlsxFile file, String sheetName) {
    final allRows = file.rows(sheetName);
    if (allRows.length < 2) return [];

    final headers = _headers(allRows[0]);
    final result  = <Student>[];

    for (int r = 1; r < allRows.length; r++) {
      final row  = allRows[r];
      String c(String h) => _cell(row, headers, h);
      final roll = c('Roll Number').trim().toUpperCase();
      if (roll.isEmpty) continue;
      result.add(Student(
        id:         _uuid.v4(),
        rollNumber: roll,
        name:       c('Student Name').trim(),
        section:    c('Section').trim().toUpperCase(),
        year:       _parseYear(c('Year')),
        batch:      int.tryParse(c('Batch').trim()) ?? 1,
      ));
    }
    return result;
  }

  // ── Export timetable ───────────────────────────────────────────────────────
  Future<String?> exportTimetable({
    required List<TimetableEntry> entries,
    required Map<String, String>  subjectNames,
    required Map<String, String>  facultyNames,
    required String section, required int year,
  }) async {
    final days   = ['', 'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
    final header = ['Day','Period','Subject','Faculty','Type','Batch'];
    final rows   = [header];
    for (final e in entries..sort((a, b) {
      final d = a.dayOfWeek.compareTo(b.dayOfWeek);
      return d != 0 ? d : a.periodNumber.compareTo(b.periodNumber);
    })) {
      rows.add([
        days[e.dayOfWeek],
        'P${e.periodNumber}',
        e.specialLabel ?? subjectNames[e.subjectId] ?? '',
        facultyNames[e.facultyId] ?? '',
        e.isLab ? 'Lab' : (e.specialLabel != null ? 'Special' : 'Theory'),
        e.batch == 0 ? 'All' : 'B${e.batch}',
      ]);
    }
    return _saveXlsx('timetable_${section}_yr$year.xlsx',
        'Timetable_${section}_Y$year', rows);
  }

  // ── Export attendance ──────────────────────────────────────────────────────
  Future<String?> exportAttendance({
    required List<Student>          students,
    required List<AttendanceRecord> records,
    required Map<String, String>    subjectNames,
    required String                 section,
  }) async {
    final header = ['Roll Number', 'Student Name',
        ...subjectNames.values, 'Overall %'];
    final rows = [header];
    for (final s in students) {
      final r = records.where((r) => r.studentId == s.id).toList();
      final subPcts = subjectNames.keys.map((subId) {
        final sr = r.where((rec) => rec.subjectId == subId).toList();
        if (sr.isEmpty) return '-';
        final p = sr.where((rec) => rec.isPresent).length / sr.length * 100;
        return '${p.toStringAsFixed(0)}%';
      }).toList();
      final overall = r.isEmpty ? '0%'
          : '${(r.where((rec) => rec.isPresent).length / r.length * 100).toStringAsFixed(0)}%';
      rows.add([s.rollNumber, s.name, ...subPcts, overall]);
    }
    return _saveXlsx('attendance_$section.xlsx', 'Attendance_$section', rows);
  }

  // ── Download faculty template ──────────────────────────────────────────────
  Future<String?> downloadFacultyTemplate() async {
    final rows = [
      ['Employee ID', 'Faculty Name', 'Subject', 'Section', 'Year', 'Type',
       'Periods Per Week', 'Is Incharge', 'Batch', 'Email',
       'Preference', 'Lab Divided Into 2 Batches'],
      // ── Year 1, Section A ──────────────────────────────────────────────
      ['TCH001', 'Dr. A Kumar',    'Data Structures',     'A', '1', 'Theory', '4', 'Yes', '0', 'akumar@college.edu',    'Monday',    'No'],
      ['TCH002', 'Mrs. K Ashwini', 'Programming in C',    'A', '1', 'Theory', '4', 'No',  '0', 'kashwini@college.edu',  'Monday',    'No'],
      ['TCH003', 'Dr. P Shanthi',  'C Programming Lab',   'A', '1', 'Lab',    '3', 'No',  '1', 'pshanthi@college.edu',  'Monday',    'Yes'],
      ['TCH003', 'Dr. P Shanthi',  'C Programming Lab',   'A', '1', 'Lab',    '3', 'No',  '2', 'pshanthi@college.edu',  'Monday',    'Yes'],
      ['TCH004', 'Mr. B Naveen',   'Engineering Maths',   'A', '1', 'Theory', '4', 'No',  '0', 'bnaveen@college.edu',   'Monday',    'No'],
      // ── Year 1, Section B ──────────────────────────────────────────────
      ['TCH005', 'Ms. D Shravani', 'Engineering Physics', 'B', '1', 'Theory', '4', 'Yes', '0', 'dshravani@college.edu', 'Wednesday', 'No'],
      ['TCH006', 'Dr. R Prasad',   'Programming in C',    'B', '1', 'Theory', '4', 'No',  '0', 'rprasad@college.edu',   'Wednesday', 'No'],
      ['TCH007', 'Mrs. S Lakshmi', 'C Programming Lab',   'B', '1', 'Lab',    '3', 'No',  '0', 'slakshmi@college.edu',  'Wednesday', 'No'],
      ['TCH008', 'Mr. T Ravi',     'Engineering Maths',   'B', '1', 'Theory', '4', 'No',  '0', 'travi@college.edu',     'Wednesday', 'No'],
      // ── Year 2, Section A ──────────────────────────────────────────────
      ['TCH009', 'Dr. M Srinivas', 'OOP',                 'A', '2', 'Theory', '4', 'Yes', '0', 'msrinivas@college.edu', 'Tuesday',   'No'],
      ['TCH010', 'Mrs. N Padma',   'DBMS',                'A', '2', 'Theory', '4', 'No',  '0', 'npadma@college.edu',    'Tuesday',   'No'],
      ['TCH011', 'Dr. K Reddy',    'DBMS Lab',            'A', '2', 'Lab',    '3', 'No',  '1', 'kreddy@college.edu',    'Tuesday',   'Yes'],
      ['TCH011', 'Dr. K Reddy',    'DBMS Lab',            'A', '2', 'Lab',    '3', 'No',  '2', 'kreddy@college.edu',    'Tuesday',   'Yes'],
      ['TCH012', 'Mr. V Rao',      'Computer Networks',   'A', '2', 'Theory', '4', 'No',  '0', 'vrao@college.edu',      'Tuesday',   'No'],
      // ── Year 2, Section B ──────────────────────────────────────────────
      ['TCH014', 'Dr. H Mohan',    'OOP',                 'B', '2', 'Theory', '4', 'Yes', '0', 'hmohan@college.edu',    'Thursday',  'No'],
      ['TCH015', 'Mrs. J Kavitha', 'DBMS',                'B', '2', 'Theory', '4', 'No',  '0', 'jkavitha@college.edu',  'Thursday',  'No'],
      ['TCH016', 'Mr. F Kumar',    'DBMS Lab',            'B', '2', 'Lab',    '3', 'No',  '0', 'fkumar@college.edu',    'Thursday',  'No'],
      ['TCH017', 'Dr. G Shankar',  'Computer Networks',   'B', '2', 'Theory', '4', 'No',  '0', 'gshankar@college.edu',  'Thursday',  'No'],
      // ── Year 3, Section A ──────────────────────────────────────────────
      ['TCH018', 'Ms. C Bhavani',  'Artificial Intelligence', 'A', '3', 'Theory', '4', 'Yes', '0', 'cbhavani@college.edu', 'Wednesday', 'No'],
      ['TCH019', 'Dr. E Naidu',    'Machine Learning',    'A', '3', 'Theory', '4', 'No',  '0', 'enaidu@college.edu',    'Wednesday', 'No'],
      ['TCH020', 'Mr. A Raju',     'ML Lab',              'A', '3', 'Lab',    '3', 'No',  '1', 'araju@college.edu',     'Wednesday', 'Yes'],
      ['TCH020', 'Mr. A Raju',     'ML Lab',              'A', '3', 'Lab',    '3', 'No',  '2', 'araju@college.edu',     'Wednesday', 'Yes'],
      ['TCH021', 'Mrs. B Sunitha', 'R Programming',       'A', '3', 'Theory', '4', 'No',  '0', 'bsunitha@college.edu',  'Wednesday', 'No'],
      // ── Year 3, Section B ──────────────────────────────────────────────
      ['TCH023', 'Ms. Q Rani',     'Artificial Intelligence', 'B', '3', 'Theory', '4', 'Yes', '0', 'qrani@college.edu',    'Friday',    'No'],
      ['TCH024', 'Dr. O Babu',     'Machine Learning',    'B', '3', 'Theory', '4', 'No',  '0', 'obabu@college.edu',     'Friday',    'No'],
      ['TCH025', 'Mr. N Murthy',   'ML Lab',              'B', '3', 'Lab',    '3', 'No',  '1', 'nmurthy@college.edu',   'Friday',    'Yes'],
      ['TCH025', 'Mr. N Murthy',   'ML Lab',              'B', '3', 'Lab',    '3', 'No',  '2', 'nmurthy@college.edu',   'Friday',    'Yes'],
      ['TCH026', 'Mrs. I Rekha',   'R Programming',       'B', '3', 'Theory', '4', 'No',  '0', 'irekha@college.edu',    'Friday',    'No'],
      // ── Year 4, Section A ──────────────────────────────────────────────
      ['TCH027', 'Dr. S Patel',    'Cloud Computing',     'A', '4', 'Theory', '4', 'Yes', '0', 'spatel@college.edu',    'Monday',    'No'],
      ['TCH028', 'Mr. U Sharma',   'Deep Learning',       'A', '4', 'Theory', '4', 'No',  '0', 'usharma@college.edu',   'Monday',    'No'],
      ['TCH029', 'Mrs. W Nair',    'Big Data Lab',        'A', '4', 'Lab',    '3', 'No',  '1', 'wnair@college.edu',     'Monday',    'Yes'],
      ['TCH029', 'Mrs. W Nair',    'Big Data Lab',        'A', '4', 'Lab',    '3', 'No',  '2', 'wnair@college.edu',     'Monday',    'Yes'],
      ['TCH030', 'Dr. X Iyer',     'Software Engineering','A', '4', 'Theory', '4', 'No',  '0', 'xiyer@college.edu',     'Monday',    'No'],
      // ── Year 4, Section B ──────────────────────────────────────────────
      ['TCH031', 'Ms. Y Verma',    'Cloud Computing',     'B', '4', 'Theory', '4', 'Yes', '0', 'yverma@college.edu',    'Thursday',  'No'],
      ['TCH032', 'Dr. Z Pillai',   'Deep Learning',       'B', '4', 'Theory', '4', 'No',  '0', 'zpillai@college.edu',   'Thursday',  'No'],
      ['TCH033', 'Mr. AA Singh',   'Big Data Lab',        'B', '4', 'Lab',    '3', 'No',  '0', 'aasingh@college.edu',   'Thursday',  'No'],
      ['TCH034', 'Mrs. BB Gupta',  'Software Engineering','B', '4', 'Theory', '4', 'No',  '0', 'bbgupta@college.edu',   'Thursday',  'No'],
    ];
    return _saveXlsx('faculty_template.xlsx', 'Faculty', rows);
  }
  Future<String?> downloadStudentTemplate() async {
    final rows = [
      ['Roll Number', 'Student Name', 'Section', 'Year', 'Batch'],
      // Year 1, Section A
      ['23CS001', 'Aditya Sharma',      'A', '1', '1'],
      ['23CS002', 'Bhavana Reddy',      'A', '1', '2'],
      ['23CS003', 'Chetan Kumar',       'A', '1', '1'],
      ['23CS004', 'Divya Lakshmi',      'A', '1', '2'],
      ['23CS005', 'Eswar Naidu',        'A', '1', '1'],
      // Year 1, Section B
      ['23CS006', 'Farida Begum',       'B', '1', '1'],
      ['23CS007', 'Ganesh Rao',         'B', '1', '2'],
      ['23CS008', 'Haritha Singh',      'B', '1', '1'],
      ['23CS009', 'Irfan Khan',         'B', '1', '2'],
      ['23CS010', 'Jyothi Prasad',      'B', '1', '1'],
      // Year 2, Section A
      ['22CS001', 'Karthik Reddy',      'A', '2', '1'],
      ['22CS002', 'Lavanya Devi',        'A', '2', '2'],
      ['22CS003', 'Mahesh Babu',        'A', '2', '1'],
      ['22CS004', 'Nithya Sree',        'A', '2', '2'],
      ['22CS005', 'Om Prakash',         'A', '2', '1'],
      // Year 2, Section B
      ['22CS006', 'Pranav Kumar',       'B', '2', '1'],
      ['22CS007', 'Qadeer Ahmed',       'B', '2', '2'],
      ['22CS008', 'Ramya Krishna',      'B', '2', '1'],
      ['22CS009', 'Suresh Goud',        'B', '2', '2'],
      ['22CS010', 'Tejaswi Raju',       'B', '2', '1'],
      // Year 3, Section A
      ['21CS001', 'Uma Shankar',        'A', '3', '1'],
      ['21CS002', 'Venkateswara Rao',   'A', '3', '2'],
      ['21CS003', 'Wasim Akram',        'A', '3', '1'],
      ['21CS004', 'Xena Patel',         'A', '3', '2'],
      ['21CS005', 'Yogesh Verma',       'A', '3', '1'],
      // Year 3, Section B
      ['21CS006', 'Zara Begum',         'B', '3', '1'],
      ['21CS007', 'Arjun Nair',         'B', '3', '2'],
      ['21CS008', 'Bhanu Priya',        'B', '3', '1'],
      ['21CS009', 'Chandra Mohan',      'B', '3', '2'],
      ['21CS010', 'Deepak Pillai',      'B', '3', '1'],
      // Year 4, Section A
      ['20CS001', 'Ekanth Sai',         'A', '4', '1'],
      ['20CS002', 'Fatima Zahra',       'A', '4', '2'],
      ['20CS003', 'Gopal Krishna',      'A', '4', '1'],
      ['20CS004', 'Hema Malini',        'A', '4', '2'],
      ['20CS005', 'Imran Ali',          'A', '4', '1'],
      // Year 4, Section B
      ['20CS006', 'Janaki Ram',         'B', '4', '1'],
      ['20CS007', 'Kavitha Nair',       'B', '4', '2'],
      ['20CS008', 'Lokesh Kumar',       'B', '4', '1'],
      ['20CS009', 'Madhavi Latha',      'B', '4', '2'],
      ['20CS010', 'Nagesh Babu',        'B', '4', '1'],
    ];
    return _saveXlsx('student_template.xlsx', 'Students', rows);
  }
  Future<String?> _saveXlsx(
      String filename, String sheetName, List<List<dynamic>> rows) async {
    final bytes = _buildXlsx(sheetName, rows);
    return saveXlsxBytes(filename, bytes);
  }

  // ── Public wrappers for archive screen ───────────────────────────────────
  /// Build XLSX bytes from headers + rows.
  Uint8List buildXlsx({
    required String sheetName,
    required List<dynamic> headers,
    required List<List<dynamic>> rows,
  }) {
    final allRows = [headers, ...rows];
    return Uint8List.fromList(_buildXlsx(sheetName, allRows));
  }

  /// Build and save an XLSX file to disk / trigger browser download.
  /// Returns the saved path (native) or null (web triggers download).
  Future<String?> saveXlsxFile(
      String filename, Uint8List bytes) async {
    return _saveXlsxBytes(filename, bytes.toList());
  }

  /// Internal bridge to the platform saveXlsxBytes function.
  Future<String?> _saveXlsxBytes(String filename, List<int> bytes) =>
      saveXlsxBytes(filename, bytes);

  // ── Build minimal valid XLSX bytes ────────────────────────────────────────
  List<int> _buildXlsx(String sheetName, List<List<dynamic>> rows) {
    // Shared strings
    final strings = <String>[];
    final strIdx  = <String, int>{};

    String strRef(dynamic val) {
      final s = val?.toString() ?? '';
      if (!strIdx.containsKey(s)) {
        strIdx[s] = strings.length;
        strings.add(s);
      }
      return strIdx[s].toString();
    }

    // Build sheet XML
    final sb = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetData>');

    for (int r = 0; r < rows.length; r++) {
      sb.write('<row r="${r + 1}">');
      final row = rows[r];
      for (int c = 0; c < row.length; c++) {
        final col  = _xlCol(c);
        final cell = '$col${r + 1}';
        final val  = row[c];
        if (val is num) {
          sb.write('<c r="$cell"><v>$val</v></c>');
        } else {
          final idx = strRef(val);
          sb.write('<c r="$cell" t="s"><v>$idx</v></c>');
        }
      }
      sb.write('</row>');
    }
    sb.write('</sheetData></worksheet>');

    final sheetXml   = sb.toString();
    final ssXml      = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
        ' count="${strings.length}" uniqueCount="${strings.length}">'
        '${strings.map((s) => '<si><t>${_escape(s)}</t></si>').join()}</sst>';
    final wbXml      = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
        ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="$sheetName" sheetId="1" r:id="rId1"/></sheets></workbook>';
    final wbRels     = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>'
        '</Relationships>';
    final pkgRels    = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>';
    const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
        '</Types>';

    final archive = Archive();
    void add(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    add('[Content_Types].xml',         contentTypes);
    add('_rels/.rels',                 pkgRels);
    add('xl/workbook.xml',             wbXml);
    add('xl/_rels/workbook.xml.rels',  wbRels);
    add('xl/worksheets/sheet1.xml',    sheetXml);
    add('xl/sharedStrings.xml',        ssXml);

    return ZipEncoder().encode(archive)!;
  }

  String _xlCol(int col) {
    var s = '';
    col++;
    while (col > 0) {
      col--;
      s = String.fromCharCode(65 + col % 26) + s;
      col ~/= 26;
    }
    return s;
  }

  String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// Parses year values from Excel cells robustly.
  /// Handles: "1", "2", "3", "4", "1st", "2nd", "3rd", "4th",
  ///          "1st year", "2nd year", "I", "II", "III", "IV",
  ///          "Year 1", "Year 2", "First Year", etc.
  int _parseYear(String raw) {
    final s = raw.trim().toLowerCase()
        .replaceAll('year', '').replaceAll('yr', '')
        .replaceAll('st', '').replaceAll('nd', '')
        .replaceAll('rd', '').replaceAll('th', '')
        .trim();

    // Direct digit
    final n = int.tryParse(s);
    if (n != null && n >= 1 && n <= 4) return n;

    // Roman numerals
    if (s == 'i' || s == 'first'  || s == '1') return 1;
    if (s == 'ii' || s == 'second' || s == '2') return 2;
    if (s == 'iii'|| s == 'third'  || s == '3') return 3;
    if (s == 'iv' || s == 'fourth' || s == '4') return 4;

    // Contains digit somewhere
    final match = RegExp(r'[1-4]').firstMatch(raw);
    if (match != null) return int.parse(match.group(0)!);

    return 1; // default
  }

  Map<String, int> _headers(List<String> row) {
    final h = <String, int>{};
    for (int i = 0; i < row.length; i++) {
      final key = row[i].trim();
      if (key.isNotEmpty) {
        h[key] = i;                        // exact
        h[key.toLowerCase()] = i;         // lowercase
        h[key.toUpperCase()] = i;         // uppercase
        h[key.replaceAll(' ', '')] = i;   // no-space variant
      }
    }
    return h;
  }

  String _cell(List<String> row, Map<String, int> headers, String col) {
    // Try exact, then lowercase, then no-space, then uppercase
    int? idx = headers[col]
        ?? headers[col.toLowerCase()]
        ?? headers[col.replaceAll(' ', '')]
        ?? headers[col.toUpperCase()];
    if (idx == null || idx >= row.length) return '';
    return row[idx].trim();
  }

  String _code(String name) =>
      name.trim().split(' ').map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
}

// ─────────────────────────────────────────────────────────────────────────────
//  DTOs
// ─────────────────────────────────────────────────────────────────────────────
class FacultyImportRow {
  final String employeeId;
  final String facultyName, subject, section, type, email, preference;
  final int    year, periodsPerWeek, batch;
  final bool   isIncharge, labDividedIntoBatches;
  FacultyImportRow({
    required this.employeeId,
    required this.facultyName, required this.subject,    required this.section,
    required this.year,        required this.type,       required this.periodsPerWeek,
    required this.isIncharge,  required this.batch,      required this.email,
    required this.preference,  required this.labDividedIntoBatches,
  });
}

class ParsedFacultyData {
  final List<Faculty> faculty;
  final List<Subject> subjects;
  ParsedFacultyData({required this.faculty, required this.subjects});
}
