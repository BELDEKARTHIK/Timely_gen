// Web Excel file operations — uses package:web (Dart 3 compatible)
// Falls back to dart:html if package:web is unavailable
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:typed_data';
// ignore: deprecated_member_use
import 'dart:html' as html;

bool isAndroidPlatform() => false;

Future<List<int>?> pickFileBytes() async => null;

/// Web: trigger browser download of Excel file
Future<String?> saveXlsxBytes(String filename, List<int> bytes) async {
  try {
    final data = Uint8List.fromList(bytes);
    final blob = html.Blob(
      [data],
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    final url  = html.Url.createObjectUrlFromBlob(blob);
    // ignore: unsafe_html
    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..setAttribute('download', filename)
      ..style.display = 'none';
    html.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
    Future.delayed(const Duration(seconds: 2), () {
      html.Url.revokeObjectUrl(url);
    });
    return filename;
  } catch (e) {
    return null;
  }
}
