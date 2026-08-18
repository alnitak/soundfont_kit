import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../utils/file_utils.dart' if (dart.library.html) '../utils/file_utils_web.dart';

/// Abstract data source for SoundFont files.
abstract class SoundFontSource {
  const SoundFontSource();

  /// Base directory or context path for resolving relative sample paths.
  String? get basePath => null;

  /// Fetches byte buffer of the main file or a byte slice.
  Future<Uint8List> getBytes([int? offset, int? length]);

  /// Returns a stream of byte chunks for a given offset and length.
  Stream<Uint8List> getByteStream([
    int? offset,
    int? length,
    int chunkSize = 16384,
  ]) async* {
    final totalBytes = await getBytes(offset, length);
    for (int i = 0; i < totalBytes.length; i += chunkSize) {
      final end = (i + chunkSize < totalBytes.length)
          ? i + chunkSize
          : totalBytes.length;
      yield Uint8List.sublistView(totalBytes, i, end);
    }
  }

  /// Returns a stream of byte chunks for a subfile.
  Stream<Uint8List> getSubFileByteStream(
    String relativePath, {
    int chunkSize = 16384,
  }) async* {
    final totalBytes = await getSubFileBytes(relativePath);
    for (int i = 0; i < totalBytes.length; i += chunkSize) {
      final end = (i + chunkSize < totalBytes.length)
          ? i + chunkSize
          : totalBytes.length;
      yield Uint8List.sublistView(totalBytes, i, end);
    }
  }

  /// Reads a text representation of the file (or subfile).
  Future<String> readAsString([String? relativePath]) async {
    final bytes = relativePath != null
        ? await getSubFileBytes(relativePath)
        : await getBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Fetches sub-file bytes (e.g. for SFZ sample files or ZIP archives).
  Future<Uint8List> getSubFileBytes(String relativePath);

  /// Checks if a relative sub-file exists.
  Future<bool> hasSubFile(String relativePath);

  /// Factory constructor for memory buffers.
  factory SoundFontSource.fromBytes(Uint8List bytes, {String? basePath}) =
      MemorySource;

  /// Factory constructor for file paths on disk.
  factory SoundFontSource.fromFile(String filePath) = FileSource;

  /// Factory constructor for Flutter asset keys.
  factory SoundFontSource.fromAsset(String assetPath) = AssetSource;

  /// Factory constructor for remote HTTP URLs.
  factory SoundFontSource.fromUrl(String url) = UrlSource;

  /// Factory constructor for Zip archives.
  factory SoundFontSource.fromZipArchive(Archive archive, {String? basePath}) =
      ZipSource;
}

/// In-memory byte buffer source.
class MemorySource extends SoundFontSource {
  final Uint8List _bytes;
  @override
  final String? basePath;

  MemorySource(Uint8List bytes, {this.basePath}) : _bytes = bytes;

  @override
  Future<Uint8List> getBytes([int? offset, int? length]) async {
    if (offset == null && length == null) return _bytes;
    final start = offset ?? 0;
    final end = length != null ? start + length : _bytes.length;
    return _bytes.sublist(start, end.clamp(0, _bytes.length));
  }

  @override
  Future<Uint8List> getSubFileBytes(String relativePath) {
    throw UnsupportedError(
        'MemorySource does not support relative sub-file loading without a Zip archive');
  }

  @override
  Future<bool> hasSubFile(String relativePath) async => false;
}

/// Disk file path source.
class FileSource extends SoundFontSource {
  final String filePath;

  FileSource(this.filePath);

  @override
  String get basePath => p.dirname(filePath);

  @override
  Future<Uint8List> getBytes([int? offset, int? length]) async {
    return readFileBytes(filePath, offset, length);
  }

  @override
  Future<Uint8List> getSubFileBytes(String relativePath) async {
    final fullPath = p.normalize(p.join(basePath, relativePath));
    return readFileBytes(fullPath, null, null);
  }

  @override
  Future<bool> hasSubFile(String relativePath) async {
    final fullPath = p.normalize(p.join(basePath, relativePath));
    return checkFileExists(fullPath);
  }
}

/// Flutter Asset source.
class AssetSource extends SoundFontSource {
  final String assetPath;

  AssetSource(this.assetPath);

  @override
  String get basePath => p.dirname(assetPath);

  @override
  Future<Uint8List> getBytes([int? offset, int? length]) async {
    final byteData = await rootBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
    if (offset == null && length == null) return bytes;
    final start = offset ?? 0;
    final end = length != null ? start + length : bytes.length;
    return bytes.sublist(start, end.clamp(0, bytes.length));
  }

  @override
  Future<Uint8List> getSubFileBytes(String relativePath) async {
    final fullPath = p.normalize(p.join(basePath, relativePath));
    final byteData = await rootBundle.load(fullPath);
    return byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
  }

  @override
  Future<bool> hasSubFile(String relativePath) async {
    try {
      final fullPath = p.normalize(p.join(basePath, relativePath));
      await rootBundle.load(fullPath);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Remote HTTP URL source.
class UrlSource extends SoundFontSource {
  final String url;
  Uint8List? _cachedBytes;

  UrlSource(this.url);

  @override
  String get basePath => url.contains('/') ? url.substring(0, url.lastIndexOf('/')) : url;

  @override
  Future<Uint8List> getBytes([int? offset, int? length]) async {
    _cachedBytes ??= (await http.get(Uri.parse(url))).bodyBytes;
    final bytes = _cachedBytes!;
    if (offset == null && length == null) return bytes;
    final start = offset ?? 0;
    final end = length != null ? start + length : bytes.length;
    return bytes.sublist(start, end.clamp(0, bytes.length));
  }

  @override
  Future<Uint8List> getSubFileBytes(String relativePath) async {
    final subUrl = '$basePath/$relativePath';
    final res = await http.get(Uri.parse(subUrl));
    if (res.statusCode != 200) {
      throw Exception('Failed to load remote subfile $subUrl: ${res.statusCode}');
    }
    return res.bodyBytes;
  }

  @override
  Future<bool> hasSubFile(String relativePath) async {
    try {
      final subUrl = '$basePath/$relativePath';
      final res = await http.head(Uri.parse(subUrl));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

/// Zip Archive source (e.g., zipped SFZ + audio files).
class ZipSource extends SoundFontSource {
  final Archive archive;
  @override
  final String? basePath;
  final Map<String, ArchiveFile> _fileMap = {};

  ZipSource(this.archive, {this.basePath}) {
    for (final file in archive) {
      if (file.isFile) {
        // Store normalized paths (handling backslashes & case insensitivity)
        final normPath = p.normalize(file.name).replaceAll('\\', '/');
        _fileMap[normPath.toLowerCase()] = file;
      }
    }
  }

  Uint8List? _mainFileBytes;

  @override
  Future<Uint8List> getBytes([int? offset, int? length]) async {
    if (_mainFileBytes == null) {
      // Find the main .sfz, .sf3, or .sf2 file in archive
      ArchiveFile? sfFile;
      for (final file in archive) {
        final ext = p.extension(file.name).toLowerCase();
        if (ext == '.sfz' || ext == '.sf3' || ext == '.sf2') {
          sfFile = file;
          break;
        }
      }
      if (sfFile == null) {
        throw Exception('No .sfz, .sf2, or .sf3 file found in ZIP archive');
      }
      final content = sfFile.content as List<int>;
      _mainFileBytes = Uint8List.fromList(content);
    }

    final bytes = _mainFileBytes!;
    if (offset == null && length == null) return bytes;
    final start = offset ?? 0;
    final end = length != null ? start + length : bytes.length;
    return bytes.sublist(start, end.clamp(0, bytes.length));
  }

  @override
  Future<Uint8List> getSubFileBytes(String relativePath) async {
    final target = p.normalize(relativePath).replaceAll('\\', '/').toLowerCase();
    
    // Try exact match or relative match
    var entry = _fileMap[target];
    if (entry == null && basePath != null && basePath!.isNotEmpty) {
      final combined = p.normalize(p.join(basePath!, relativePath)).replaceAll('\\', '/').toLowerCase();
      entry = _fileMap[combined];
    }
    if (entry == null) {
      // Try searching by filename suffix
      for (final key in _fileMap.keys) {
        if (key.endsWith(target)) {
          entry = _fileMap[key];
          break;
        }
      }
    }

    if (entry == null) {
      throw Exception('Subfile "$relativePath" not found in ZIP archive.');
    }

    final content = entry.content as List<int>;
    return Uint8List.fromList(content);
  }

  @override
  Future<bool> hasSubFile(String relativePath) async {
    final target = p.normalize(relativePath).replaceAll('\\', '/').toLowerCase();
    if (_fileMap.containsKey(target)) return true;
    for (final key in _fileMap.keys) {
      if (key.endsWith(target)) return true;
    }
    return false;
  }
}
