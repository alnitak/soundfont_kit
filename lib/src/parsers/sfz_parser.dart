import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../models/instrument.dart';
import '../models/preset.dart';
import '../models/sample_info.dart';
import '../models/soundfont_format.dart';
import '../models/zone.dart';
import '../sources/soundfont_source.dart';

/// Result container for parsed SFZ instrument definition files.
class SfzData {
  /// Name of the SFZ instrument bank.
  final String name;

  /// Optional comment or serialized `<control>` header metadata.
  final String? comment;

  /// Synthesized presets wrapping the parsed SFZ instrument.
  final List<Preset> presets;

  /// Parsed instruments containing the SFZ `<region>` zones.
  final List<Instrument> instruments;

  /// Sample descriptors referenced by the SFZ `<region>` opcodes.
  final List<SampleInfo> samples;

  /// Active [SoundFontSource] used to load external sample audio files.
  final SoundFontSource activeSource;

  /// Creates an [SfzData] container with parsed SFZ presets, instruments, and samples.
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
  /// The input [SoundFontSource] providing the `.sfz` text or `.zip` archive.
  final SoundFontSource source;

  /// Creates an [SfzParser] reading from [source].
  SfzParser(this.source);

  /// Parses the SFZ definition from [source] and returns the resulting [SfzData].
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
        fullSamplePath = p
            .normalize(p.join(defaultPath, fullSamplePath))
            .replaceAll('\\', '/');
      }

      final ext = p.extension(fullSamplePath).toLowerCase();
      SampleCompression comp = SampleCompression.wav;
      if (ext == '.flac') {
        comp = SampleCompression.flac;
      } else if (ext == '.ogg') {
        comp = SampleCompression.ogg;
      }

      final parsedKey = _parseNote(merged['key']);
      final rootKey = _parseNote(merged['pitch_keycenter']) ?? parsedKey ?? 60;
      final loKey = _parseNote(merged['lokey']) ?? parsedKey ?? 0;
      final hiKey = _parseNote(merged['hikey']) ?? parsedKey ?? 127;

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

      double? delay = double.tryParse(merged['ampeg_delay'] ?? '');
      double? attack = double.tryParse(merged['ampeg_attack'] ?? '');
      double? hold = double.tryParse(merged['ampeg_hold'] ?? '');
      double? decay = double.tryParse(merged['ampeg_decay'] ?? '');
      double? sustain = double.tryParse(merged['ampeg_sustain'] ?? '');
      double? release = double.tryParse(merged['ampeg_release'] ?? '');
      int? tune = int.tryParse(merged['tune'] ?? '');
      final int transpose = int.tryParse(merged['transpose'] ?? '') ?? 0;
      if (transpose != 0) {
        tune = (tune ?? 0) + transpose * 100;
      }

      double? pan;
      final panRaw = double.tryParse(merged['pan'] ?? '');
      if (panRaw != null) {
        pan = (panRaw / 100.0).clamp(-1.0, 1.0);
      }

      double? attenuation;
      final volDb = double.tryParse(merged['volume'] ?? '');
      if (volDb != null && volDb < 0) {
        attenuation = -volDb;
      }

      final double? cutoff = double.tryParse(merged['cutoff'] ?? '');
      final double? resonance = double.tryParse(merged['resonance'] ?? '');
      final int? group = int.tryParse(merged['group'] ?? '');
      final int? offBy = int.tryParse(merged['off_by'] ?? '');

      final double? modEnvDelay = double.tryParse(
        merged['fileg_delay'] ?? merged['pitcheg_delay'] ?? '',
      );
      final double? modEnvAttack = double.tryParse(
        merged['fileg_attack'] ?? merged['pitcheg_attack'] ?? '',
      );
      final double? modEnvHold = double.tryParse(
        merged['fileg_hold'] ?? merged['pitcheg_hold'] ?? '',
      );
      final double? modEnvDecay = double.tryParse(
        merged['fileg_decay'] ?? merged['pitcheg_decay'] ?? '',
      );
      final double? modEnvSustainPct = double.tryParse(
        merged['fileg_sustain'] ?? merged['pitcheg_sustain'] ?? '',
      );
      final double? modEnvSustain = modEnvSustainPct != null
          ? (modEnvSustainPct / 100.0).clamp(0.0, 1.0)
          : null;
      final double? modEnvRelease = double.tryParse(
        merged['fileg_release'] ?? merged['pitcheg_release'] ?? '',
      );
      final int? modEnvToFilterFc =
          double.tryParse(merged['fileg_depth'] ?? '')?.round();
      final int? modEnvToPitch =
          double.tryParse(merged['pitcheg_depth'] ?? '')?.round();

      final double? vibLfoDelay = double.tryParse(
        merged['pitchlfo_delay'] ?? '',
      );
      final double? vibLfoFreq = double.tryParse(merged['pitchlfo_freq'] ?? '');
      final int? vibLfoToPitch =
          double.tryParse(merged['pitchlfo_depth'] ?? '')?.round();

      final double? reverbPct = double.tryParse(merged['effect1'] ?? '');
      final double? chorusPct = double.tryParse(merged['effect2'] ?? '');

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
        attenuation: attenuation,
        pan: pan,
        sampleID: sampleInfo.id,
        sampleRef: sampleInfo,
        loopMode: loopMode,
        loopStart: loopStart,
        loopEnd: loopEnd,
        volEnvDelay: delay,
        volEnvAttack: attack,
        volEnvHold: hold,
        volEnvDecay: decay,
        volEnvSustain: sustain,
        volEnvRelease: release,
        modEnvDelay: modEnvDelay,
        modEnvAttack: modEnvAttack,
        modEnvHold: modEnvHold,
        modEnvDecay: modEnvDecay,
        modEnvSustain: modEnvSustain,
        modEnvRelease: modEnvRelease,
        modEnvToPitch: modEnvToPitch,
        modEnvToFilterFc: modEnvToFilterFc,
        initialFilterCutoff: cutoff,
        initialFilterQ: resonance,
        vibLfoDelay: vibLfoDelay,
        vibLfoFreq: vibLfoFreq,
        vibLfoToPitch: vibLfoToPitch,
        exclusiveClass: group,
        offByGroup: offBy ?? group,
        reverbSend: reverbPct != null
            ? (reverbPct / 100.0).clamp(0.0, 1.0)
            : null,
        chorusSend: chorusPct != null
            ? (chorusPct / 100.0).clamp(0.0, 1.0)
            : null,
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

    final instrument = Instrument(id: 0, name: name, zones: zones);

    final presetZone = Zone(
      keyRangeMin: 0,
      keyRangeMax: 127,
      velRangeMin: 0,
      velRangeMax: 127,
      instrumentID: 0,
    );

    final preset = Preset(bank: 0, program: 0, name: name, zones: [presetZone]);

    return SfzData(
      name: name,
      comment: controlOpcodes.toString(),
      presets: [preset],
      instruments: [instrument],
      samples: samples,
      activeSource: currentSource,
    );
  }

  /// Parses a note value from SFZ opcode, which can be an integer (e.g. "60")
  /// or note name (e.g. "C4", "F#6", "Eb5", "Db3").
  static int? _parseNote(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final clean = value.trim().toLowerCase();
    final intVal = int.tryParse(clean);
    if (intVal != null) return intVal;

    final match = RegExp(r'^([a-g])([#b]?)(-?\d+)$').firstMatch(clean);
    if (match == null) return null;

    final noteLetter = match.group(1)!;
    final accidental = match.group(2)!;
    final octave = int.tryParse(match.group(3)!) ?? 4;

    int noteInOctave = switch (noteLetter) {
      'c' => 0,
      'd' => 2,
      'e' => 4,
      'f' => 5,
      'g' => 7,
      'a' => 9,
      'b' => 11,
      _ => 0,
    };

    if (accidental == '#' || accidental == '+') {
      noteInOctave += 1;
    } else if (accidental == 'b' || accidental == '-') {
      noteInOctave -= 1;
    }

    final midiNote = (octave + 1) * 12 + noteInOctave;
    return midiNote.clamp(0, 127);
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
