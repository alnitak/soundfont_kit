import 'dart:async';
import 'dart:typed_data';
import 'package:archive/archive.dart';

import 'models/instrument.dart';
import 'models/preset.dart';
import 'models/sample_info.dart';
import 'models/soundfont_format.dart';
import 'parsers/sf2_parser.dart';
import 'parsers/sf3_parser.dart';
import 'parsers/sfz_parser.dart';
import 'player/player_options.dart';
import 'player/soundfont_player.dart';
import 'sources/soundfont_source.dart';

/// Unified main interface for reading and querying SoundFont files (SF2, SF3, and SFZ).
abstract class SoundFontFile {
  /// The detected or specified format of this SoundFont file.
  SoundFontFormat get format;

  /// The name of the SoundFont bank or instrument.
  String? get name;

  /// Optional description or comment metadata.
  String? get comment;

  /// All presets defined in this SoundFont.
  List<Preset> get presets;

  /// All instruments defined in this SoundFont.
  List<Instrument> get instruments;

  /// All audio sample definitions in this SoundFont.
  List<SampleInfo> get samples;

  /// Look up a preset by bank and program number.
  Preset? findPreset({required int bank, required int program}) {
    for (final p in presets) {
      if (p.bank == bank && p.program == program) return p;
    }
    return null;
  }

  /// Retrieves the raw compressed or uncompressed audio bytes for a specific [SampleInfo].
  Future<Uint8List> getSampleBytes(SampleInfo sample);

  /// Retrieves a stream of audio byte chunks for a specific [SampleInfo].
  Stream<Uint8List> getSampleByteStream(
    SampleInfo sample, {
    int chunkSize = 16384,
  });

  /// Creates a [SoundFontPlayer] instance for audio playback of this SoundFont.
  SoundFontPlayer createPlayer({SoundFontPlayerOptions? options}) {
    final player = SoundFontPlayer(
      soundFont: this,
      options: options ?? const SoundFontPlayerOptions(),
    );
    if (player.options.preloadAllSamples) {
      player.preloadAll();
    }
    return player;
  }

  /// Load a SoundFont from an in-memory byte buffer.
  static Future<SoundFontFile> fromBytes(
    Uint8List bytes, {
    SoundFontFormat? formatHint,
    String? basePath,
  }) async {
    final source = MemorySource(bytes, basePath: basePath);
    return fromSource(source, formatHint: formatHint);
  }

  /// Load a SoundFont from a file on disk.
  static Future<SoundFontFile> fromFile(String filePath) async {
    final source = FileSource(filePath);
    return fromSource(source, pathHint: filePath);
  }

  /// Load a SoundFont from a Flutter asset key.
  static Future<SoundFontFile> fromAsset(String assetPath) async {
    final source = AssetSource(assetPath);
    return fromSource(source, pathHint: assetPath);
  }

  /// Load a SoundFont from a remote HTTP URL.
  static Future<SoundFontFile> fromUrl(String url) async {
    final source = UrlSource(url);
    return fromSource(source, pathHint: url);
  }

  /// Load a SoundFont from any custom [SoundFontSource].
  static Future<SoundFontFile> fromSource(
    SoundFontSource source, {
    SoundFontFormat? formatHint,
    String? pathHint,
  }) async {
    final bytes = await source.getBytes();

    // Check if source is a ZIP archive
    if (bytes.length > 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04 &&
        source is! ZipSource) {
      final archive = ZipDecoder().decodeBytes(bytes);
      final zipSource = SoundFontSource.fromZipArchive(
        archive,
        basePath: source.basePath,
      );
      return fromSource(zipSource, formatHint: formatHint, pathHint: pathHint);
    }

    // Check if source is GZIP compressed (0x1F, 0x8B)
    if (bytes.length > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      final decompressed = Uint8List.fromList(GZipDecoder().decodeBytes(bytes));
      final memSource = MemorySource(decompressed, basePath: source.basePath);
      return fromSource(memSource, formatHint: formatHint, pathHint: pathHint);
    }

    // Check if source is BZIP2 compressed ('BZ')
    if (bytes.length > 2 && bytes[0] == 0x42 && bytes[1] == 0x5A) {
      final decompressed = Uint8List.fromList(
        BZip2Decoder().decodeBytes(bytes),
      );
      final memSource = MemorySource(decompressed, basePath: source.basePath);
      return fromSource(memSource, formatHint: formatHint, pathHint: pathHint);
    }

    // Check if source is TAR archive
    if (bytes.length > 262 &&
        bytes[257] == 0x75 &&
        bytes[258] == 0x73 &&
        bytes[259] == 0x74 &&
        bytes[260] == 0x61 &&
        bytes[261] == 0x72 &&
        source is! ZipSource) {
      final archive = TarDecoder().decodeBytes(bytes);
      final tarSource = SoundFontSource.fromZipArchive(
        archive,
        basePath: source.basePath,
      );
      return fromSource(tarSource, formatHint: formatHint, pathHint: pathHint);
    }

    var format =
        formatHint ?? _detectFormat(bytes, pathHint ?? source.basePath);

    switch (format) {
      case SoundFontFormat.sf2:
        final parser = Sf2Parser(source);
        final sf2Data = await parser.parse();
        // Check if any sample was OGG encoded
        final hasOgg = sf2Data.samples.any(
          (s) => s.compression == SampleCompression.ogg,
        );
        final actualFormat = hasOgg ? SoundFontFormat.sf3 : SoundFontFormat.sf2;
        return _Sf2SoundFontFile(sf2Data, source, actualFormat);

      case SoundFontFormat.sf3:
        final parser = Sf3Parser(source);
        final sf3Data = await parser.parse();
        return _Sf2SoundFontFile(sf3Data, source, SoundFontFormat.sf3);

      case SoundFontFormat.sfz:
        final parser = SfzParser(source);
        final sfzData = await parser.parse();
        return _SfzSoundFontFile(sfzData);
    }
  }

  static SoundFontFormat _detectFormat(Uint8List bytes, String? pathHint) {
    if (pathHint != null) {
      final lower = pathHint.toLowerCase();
      if (lower.endsWith('.sf3')) return SoundFontFormat.sf3;
      if (lower.endsWith('.sfz')) return SoundFontFormat.sfz;
      if (lower.endsWith('.sf2')) return SoundFontFormat.sf2;
    }

    if (bytes.length >= 12) {
      final header = String.fromCharCodes(bytes.sublist(0, 4));
      final form = String.fromCharCodes(bytes.sublist(8, 12));
      if (header == 'RIFF' && form == 'sfbk') {
        // Check for SF3 markers inside bytes (e.g. 'OggS' or Ogg sample flag bit)
        final isSf3 = _containsSubBytes(bytes, [
          0x4F,
          0x67,
          0x67,
          0x53,
        ]); // OggS
        return isSf3 ? SoundFontFormat.sf3 : SoundFontFormat.sf2;
      }
    }

    // Check for ZIP magic 'PK\x03\x04'
    if (bytes.length > 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04) {
      return SoundFontFormat.sfz;
    }

    // Default fallback to SFZ for text files
    return SoundFontFormat.sfz;
  }

  static bool _containsSubBytes(Uint8List source, List<int> pattern) {
    for (int i = 0; i <= source.length - pattern.length; i++) {
      bool match = true;
      for (int j = 0; j < pattern.length; j++) {
        if (source[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }
}

class _Sf2SoundFontFile extends SoundFontFile {
  final Sf2Data _data;
  final SoundFontSource _source;
  @override
  final SoundFontFormat format;

  _Sf2SoundFontFile(this._data, this._source, this.format);

  @override
  String? get name => _data.name;

  @override
  String? get comment => _data.comment;

  @override
  List<Preset> get presets => _data.presets;

  @override
  List<Instrument> get instruments => _data.instruments;

  @override
  List<SampleInfo> get samples => _data.samples;

  @override
  Future<Uint8List> getSampleBytes(SampleInfo sample) async {
    if (sample.byteLength <= 0) return Uint8List(0);
    return await _source.getBytes(sample.byteOffset, sample.byteLength);
  }

  @override
  Stream<Uint8List> getSampleByteStream(
    SampleInfo sample, {
    int chunkSize = 16384,
  }) {
    if (sample.byteLength <= 0) {
      return Stream.value(Uint8List(0));
    }
    return _source.getByteStream(
      sample.byteOffset,
      sample.byteLength,
      chunkSize,
    );
  }
}

class _SfzSoundFontFile extends SoundFontFile {
  final SfzData _data;

  _SfzSoundFontFile(this._data);

  @override
  SoundFontFormat get format => SoundFontFormat.sfz;

  @override
  String? get name => _data.name;

  @override
  String? get comment => _data.comment;

  @override
  List<Preset> get presets => _data.presets;

  @override
  List<Instrument> get instruments => _data.instruments;

  @override
  List<SampleInfo> get samples => _data.samples;

  @override
  Future<Uint8List> getSampleBytes(SampleInfo sample) async {
    if (sample.samplePath != null && sample.samplePath!.isNotEmpty) {
      return await _data.activeSource.getSubFileBytes(sample.samplePath!);
    }
    return Uint8List(0);
  }

  @override
  Stream<Uint8List> getSampleByteStream(
    SampleInfo sample, {
    int chunkSize = 16384,
  }) {
    if (sample.samplePath != null && sample.samplePath!.isNotEmpty) {
      return _data.activeSource.getSubFileByteStream(
        sample.samplePath!,
        chunkSize: chunkSize,
      );
    }
    return Stream.value(Uint8List(0));
  }
}
