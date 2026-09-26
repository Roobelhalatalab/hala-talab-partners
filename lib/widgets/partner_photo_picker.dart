import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Picks a store/product/category photo from the native photo library on mobile.
///
/// iOS/iPadOS: opens Photos (PHPicker/ImagePicker), never the Files document picker.
/// Android: opens the native gallery/photo picker.
/// Desktop/Web: keeps the existing FilePicker fallback.
///
/// Documents intentionally continue to use FilePicker in their own flow.
Future<PlatformFile?> pickPartnerPhoto() async {
  final isMobilePhotoPlatform = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  if (isMobilePhotoPlatform) {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
      // Large enough for sharp product/store images while avoiding enormous
      // camera originals that waste memory before the crop editor exports PNG.
      maxWidth: 3000,
      maxHeight: 3000,
      imageQuality: 92,
    );
    if (photo == null) return null;

    final bytes = await photo.readAsBytes();
    if (bytes.isEmpty) return null;
    return PlatformFile(
      name: photo.name.isEmpty ? 'partner_photo.jpg' : photo.name,
      size: bytes.length,
      bytes: bytes,
      path: photo.path,
    );
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
