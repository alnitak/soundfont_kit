import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../models/instrument.dart';
import '../models/preset.dart';
import '../models/sample_info.dart';
import '../models/soundfont_format.dart';
import '../models/zone.dart';
import '../sources/soundfont_source.dart';

/// Result container for parsed SFZ files.
class SfzData {
  final String name;
  final String? comment;
  final List<Preset> presets;
  final List<Instrument> instruments;
  final List<SampleInfo> samples;
  final SoundFontSource activeSource;

  SfzData({
    required this.name,
    this.comment,
    required this.presets,
    required this.instruments,
    required this.samples,
    required this.activeSource,
  });
}

/// Parser for SFZ text-based instrument definitions and zipped SFZ packages.
class SfzParser {
  final SoundFontSource source;

  SfzParser(this.source);

  Future<SfzData> parse() async {
    SoundFontSource currentSource = source;
    final initialBytes = await source.getBytes();

    // Check for ZIP magic header 'PK\x03\x04'
    if (initialBytes.length > 4 &&
        initialBytes[0] == 0x50 &&
        initialBytes[1] == 0x4B &&
        initialBytes[2] == 0x03 &&
        initialBytes[3] == 0x04) {
      final archive = ZipDecoder().decodeBytes(initialBytes);
      currentSource = ZipSource(archive, basePath: source.basePath);
    }

    final sfzText = await currentSource.readAsString();

    final globalOpcodes = <String, String>{};
    final masterOpcodes = <String, String>{};
    final groupOpcodes = <String, String>{};
    final controlOpcodes = <String, String>{};

    String defaultPath = '';
    String? sfzName;

    final samples = <SampleInfo>[];
    final zones = <Zone>[];

    // Preprocess text: remove comments
    final cleanText = _stripComments(sfzText);
    final tokens = _tokenizeSfz(cleanText);

    String currentHeader = '';
    Map<String, String> currentRegionOpcodes = {};

    void flushRegion() {
      if (currentRegionOpcodes.isEmpty) return;

      final merged = <String, String>{
        ...globalOpcodes,
        ...masterOpcodes,
        ...groupOpcodes,
        ...currentRegionOpcodes,
      };

      final sampleVal = merged['sample'];
      if (sampleVal == null || sampleVal.isEmpty) {
        currentRegionOpcodes.clear();
        return;
      }

      String fullSamplePath = sampleVal.replaceAll('\\', '/');
      if (defaultPath.isNotEmpty && !fullSamplePath.startsWith(defaultPath)) {
        fullSamplePath = p.normalize(p.join(defaultPath, fullSamplePath)).replaceAll('\\', '/');
      }

      final ext = p.extension(fullSamplePath).toLowerCase();
      SampleCompression comp = SampleCompression.wav;
      if (ext == '.flac') {
        comp = SampleCompression.flac;
      } else if (ext == '.ogg') {
        comp = SampleCompression.ogg;
      }

      int rootKey = int.tryParse(merged['pitch_keycenter'] ?? '') ??
          int.tryParse(merged['key'] ?? '') ?? 60;
      int loKey = int.tryParse(merged['lokey'] ?? '') ??
          int.tryParse(merged['key'] ?? '') ?? 0;
      int hiKey = int.tryParse(merged['hikey'] ?? '') ??
          int.tryParse(merged['key'] ?? '') ?? 127;

      int loVel = int.tryParse(merged['lovel'] ?? '') ?? 0;
      int hiVel = int.tryParse(merged['hivel'] ?? '') ?? 127;

      int loopStart = int.tryParse(merged['loop_start'] ?? '') ?? 0;
      int loopEnd = int.tryParse(merged['loop_end'] ?? '') ?? 0;

      LoopMode? loopMode;
      final loopVal = merged['loop_mode'];
      if (loopVal != null) {
        if (loopVal.contains('continuous')) {
          loopMode = LoopMode.continuous;
        } else if (loopVal.contains('sustain')) {
          loopMode = LoopMode.sustain;
        } else if (loopVal.contains('no_loop')) {
          loopMode = LoopMode.none;
        }
      }

      double? attack = double.tryParse(merged['ampeg_attack'] ?? '');
      double? decay = double.tryParse(merged['ampeg_decay'] ?? '');
      double? sustain = double.tryParse(merged['ampeg_sustain'] ?? '');
      double? release = double.tryParse(merged['ampeg_release'] ?? '');
      int? tune = int.tryParse(merged['tune'] ?? '');

      final sampleInfo = SampleInfo(
        id: samples.length,
        name: p.basenameWithoutExtension(fullSamplePath),
        originalPitch: rootKey,
        pitchCorrection: tune ?? 0,
        loopStart: loopStart,
        loopEnd: loopEnd,
        compression: comp,
        samplePath: fullSamplePath,
      );

      samples.add(sampleInfo);

      final zone = Zone(
        keyRangeMin: loKey,
        keyRangeMax: hiKey,
        velRangeMin: loVel,
        velRangeMax: hiVel,
        rootKey: rootKey,
        pitchCorrection: tune,
        sampleID: sampleInfo.id,
        sampleRef: sampleInfo,
        loopMode: loopMode,
        loopStart: loopStart,
        loopEnd: loopEnd,
        volEnvAttack: attack,
        volEnvDecay: decay,
        volEnvSustain: sustain,
        volEnvRelease: release,
        opcodes: Map.unmodifiable(merged),
      );

      zones.add(zone);
      currentRegionOpcodes.clear();
    }

    for (final token in tokens) {
      if (token.startsWith('<') && token.endsWith('>')) {
        final header = token.substring(1, token.length - 1).toLowerCase();

        if (currentHeader == 'region') {
          flushRegion();
        }

        currentHeader = header;
        if (header == 'global') {
          globalOpcodes.clear();
          masterOpcodes.clear();
          groupOpcodes.clear();
        } else if (header == 'master') {
          masterOpcodes.clear();
          groupOpcodes.clear();
        } else if (header == 'group') {
          groupOpcodes.clear();
        }
      } else if (token.contains('=')) {
        final parts = token.split('=');
        final key = parts[0].trim().toLowerCase();
        final val = parts.sublist(1).join('=').trim().replaceAll('"', '');

        if (key == 'default_path') {
          defaultPath = val.replaceAll('\\', '/');
        }

        if (currentHeader == 'control') {
          controlOpcodes[key] = val;
          if (key == 'default_path') defaultPath = val.replaceAll('\\', '/');
        } else if (currentHeader == 'global') {
          globalOpcodes[key] = val;
        } else if (currentHeader == 'master') {
          masterOpcodes[key] = val;
        } else if (currentHeader == 'group') {
          groupOpcodes[key] = val;
        } else if (currentHeader == 'region') {
          currentRegionOpcodes[key] = val;
        }
      }
    }

    if (currentHeader == 'region') {
      flushRegion();
    }

    final name = sfzName ?? controlOpcodes['default_path'] ?? 'SFZ Instrument';

    final instrument = Instrument(
      id: 0,
      name: name,
      zones: zones,
    );

    final preset = Preset(
      bank: 0,
      program: 0,
      name: name,
      zones: zones,
    );

    return SfzData(
      name: name,
      comment: controlOpcodes.toString(),
      presets: [preset],
      instruments: [instrument],
      samples: samples,
      activeSource: currentSource,
    );
  }

  String _stripComments(String text) {
    // Strip multi-line comments /* ... */
    final noMulti = text.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    // Strip single-line comments // ... or # ... (except #define / #include)
    final lines = noMulti.split('\n');
    final cleanLines = <String>[];

    for (var line in lines) {
      final idx = line.indexOf('//');
      if (idx >= 0) {
        line = line.substring(0, idx);
      }
      cleanLines.add(line);
    }
    return cleanLines.join('\n');
  }

  List<String> _tokenizeSfz(String text) {
    final tokens = <String>[];
    final regex = RegExp(r'<[^>]+>|[\w_]+=(?:"[^"]*"|\S+)');
    final matches = regex.allMatches(text);

    for (final m in matches) {
      tokens.add(m.group(0)!);
    }
    return tokens;
  }
}
