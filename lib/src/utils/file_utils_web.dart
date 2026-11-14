import 'dart:typed_data';

/// Web stub for reading file bytes from [path]; throws an [UnsupportedError] on web.
Future<Uint8List> readFileBytes(String path, int? offset, int? length) async {
  throw UnsupportedError(
    'File I/O is not supported on web platform. Use fromBytes, fromAsset, or fromUrl.',
  );
}

/// Web stub for checking whether a file exists at [path]; always returns `false` on web.
Future<bool> checkFileExists(String path) async {
  return false;
}

/// Web stub for synchronously reading file bytes from [path]; throws an [UnsupportedError] on web.
Uint8List readFileSync(String path) {
  throw UnsupportedError(
    'File I/O is not supported on web platform. Use fromBytes, fromAsset, or fromUrl.',
  );
}
