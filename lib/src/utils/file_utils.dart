import 'dart:io';
import 'dart:typed_data';

/// Reads all bytes or a byte slice starting at [offset] with [length] from the file at [path].
Future<Uint8List> readFileBytes(String path, int? offset, int? length) async {
  final file = File(path);
  if (!await file.exists()) {
    throw FileSystemException('File not found: $path', path);
  }
  if (offset == null && length == null) {
    return await file.readAsBytes();
  }
  final handle = await file.open(mode: FileMode.read);
  try {
    if (offset != null) {
      await handle.setPosition(offset);
    }
    final len = length ?? (await file.length() - (offset ?? 0));
    return await handle.read(len);
  } finally {
    await handle.close();
  }
}

/// Checks whether a file exists on disk at [path].
Future<bool> checkFileExists(String path) async {
  return File(path).exists();
}

/// Synchronously reads all bytes from the file at [path].
Uint8List readFileSync(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw FileSystemException('File not found: $path', path);
  }
  return file.readAsBytesSync();
}
