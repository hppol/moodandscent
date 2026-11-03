import 'dart:typed_data';
import 'dart:io';

Future<void> saveImageToDevice(Uint8List bytes, String fileName) async {
  try {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null) {
      final downloadsDir = Directory('$userProfile\\Downloads');
      if (await downloadsDir.exists()) {
        final file = File('${downloadsDir.path}\\$fileName');
        await file.writeAsBytes(bytes);
      }
    }
  } catch (_) {}
}

