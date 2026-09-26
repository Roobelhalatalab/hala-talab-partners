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
