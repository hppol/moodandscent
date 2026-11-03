import 'dart:typed_data';
import 'image_saver_stub.dart'
    if (dart.library.html) 'image_saver_web.dart';

Future<void> downloadImage(Uint8List bytes, String fileName) =>
    saveImageToDevice(bytes, fileName);

