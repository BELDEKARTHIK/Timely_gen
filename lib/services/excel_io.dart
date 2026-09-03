// IO (Android/iOS/Windows/macOS/Linux) Excel file operations
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

bool isAndroidPlatform() => Platform.isAndroid;

// Desktop: pick file via path
Future<List<int>?> pickFileBytes() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return null;
  final path = result.files.single.path;
  if (path == null) return null;
  return await File(path).readAsBytes();
}

// Save XLSX bytes to a file and return the path
Future<String?> saveXlsxBytes(String filename, List<int> bytes) async {
  try {
    String savePath;
    if (Platform.isAndroid) {
      try {
        final dir = Directory('/storage/emulated/0/Download');
        if (await dir.exists()) {
          savePath = '${dir.path}/$filename';
        } else {
          final d = await getApplicationDocumentsDirectory();
          savePath = '${d.path}/$filename';
        }
      } catch (_) {
        final d = await getApplicationDocumentsDirectory();
        savePath = '${d.path}/$filename';
      }
    } else {
      final d = await getApplicationDocumentsDirectory();
      savePath = '${d.path}/$filename';
    }
    await File(savePath).writeAsBytes(bytes);
    return savePath;
  } catch (e) {
    return null;
  }
}
