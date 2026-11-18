import 'package:image_picker/image_picker.dart';
export 'package:image_picker/image_picker.dart' show XFile;

abstract class ScanPhotoSource {
  Future<List<XFile>> pick({required bool camera, required int limit});
}

class DeviceScanPhotos implements ScanPhotoSource {
  final _picker = ImagePicker();
  @override
  Future<List<XFile>> pick({required bool camera, required int limit}) async {
    if (camera) {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 96,
        requestFullMetadata: false,
      );
      return photo == null ? [] : [photo];
    }
    return _picker.pickMultiImage(
      limit: limit,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 96,
      requestFullMetadata: false,
    );
  }
}
