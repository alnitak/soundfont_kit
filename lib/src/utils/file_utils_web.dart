import 'dart:typed_data';

Future<Uint8List> readFileBytes(String path, int? offset, int? length) async {
  throw UnsupportedError('File I/O is not supported on web platform. Use fromBytes, fromAsset, or fromUrl.');
}

Future<bool> checkFileExists(String path) async {
  return false;
}
