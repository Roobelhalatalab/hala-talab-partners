import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart' show PlatformFile;
import 'package:image_picker/image_picker.dart';

/// Picks a store/product/category photo from the device photo library.
///
/// IMPORTANT: photo flows must never use FilePicker. Using ImagePicker here for
/// every platform prevents iOS from falling back to the Files document browser.
/// Document/PDF flows intentionally keep FilePicker in their own screens.
Future<PlatformFile?> pickPartnerPhotoFromGallery() async {
  final XFile? photo = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    requestFullMetadata: false,
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


/// Choose a camera capture or photo-library image without opening a document picker.
/// Both paths return the same PlatformFile so the existing crop and size checks remain.
Future<PlatformFile?> pickPartnerPhotoWithCamera(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.camera_alt_outlined),
          title: const Text('التقاط صورة بالكاميرا'),
          onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('اختيار صورة من الاستوديو'),
          onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (source == null) return null;
  final XFile? photo = await ImagePicker().pickImage(
    source: source,
    requestFullMetadata: false,
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
