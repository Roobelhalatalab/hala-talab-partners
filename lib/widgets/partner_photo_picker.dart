import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Opens the native Photos library on iPhone/iPad, while keeping the existing
/// file chooser on Android and desktop. Documents continue to use FilePicker.
Future<PlatformFile?> pickPartnerPhoto() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    final photo = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (photo == null) return null;
    final bytes = await photo.readAsBytes();
    return PlatformFile(name: photo.name, size: bytes.length, bytes: bytes);
  }
  final selection = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    withData: true,
    allowMultiple: false,
  );
  if (selection == null || selection.files.isEmpty) return null;
  return selection.files.single;
}
