import 'modulator_info.dart';
import 'sample_info.dart';
import 'soundfont_format.dart';

/// Represents a region or zone within an instrument or preset.
class Zone {
  final int keyRangeMin;
  final int keyRangeMax;
  final int velRangeMin;
  final int velRangeMax;
  final int? rootKey;
  final int? pitchCorrection;
  final double? attenuation;
  final double? pan;
  final int? sampleID;
  final SampleInfo? sampleRef;
  final int? instrumentID;
  final LoopMode? loopMode;
  final int? loopStart;
  final int? loopEnd;

  // Volume Envelope (EG2)
  final double? volEnvAttack;
  final double? volEnvHold;
  final double? volEnvDecay;
  final double? volEnvSustain;
  final double? volEnvRelease;

  // Modulation Envelope (EG1)
  final double? modEnvAttack;
  final double? modEnvHold;
  final double? modEnvDecay;
  final double? modEnvSustain;
  final double? modEnvRelease;

  // Filter
  final double? initialFilterCutoff;
  final double? initialFilterQ;

  /// Raw generator IDs mapped to values (for SF2/SF3)
  final Map<int, int> generators;

  /// Raw SF2 modulators
  final List<ModulatorInfo> modulators;

  /// Raw SFZ opcodes (for SFZ format)
  final Map<String, String> opcodes;

  const Zone({
    this.keyRangeMin = 0,
    this.keyRangeMax = 127,
    this.velRangeMin = 0,
    this.velRangeMax = 127,
    this.rootKey,
    this.pitchCorrection,
    this.attenuation,
    this.pan,
    this.sampleID,
    this.sampleRef,
    this.instrumentID,
    this.loopMode,
    this.loopStart,
    this.loopEnd,
    this.volEnvAttack,
    this.volEnvHold,
    this.volEnvDecay,
    this.volEnvSustain,
    this.volEnvRelease,
    this.modEnvAttack,
    this.modEnvHold,
    this.modEnvDecay,
    this.modEnvSustain,
    this.modEnvRelease,
    this.initialFilterCutoff,
    this.initialFilterQ,
    this.generators = const {},
    this.modulators = const [],
    this.opcodes = const {},
  });

  /// Check if a given MIDI key and velocity falls within this zone's ranges
  bool matches(int key, int velocity) {
    return key >= keyRangeMin &&
        key <= keyRangeMax &&
        velocity >= velRangeMin &&
        velocity <= velRangeMax;
  }

  @override
  String toString() {
    return 'Zone(keyRange: $keyRangeMin..$keyRangeMax, velRange: $velRangeMin..$velRangeMax, '
        'sampleID: $sampleID, instrumentID: $instrumentID, rootKey: $rootKey)';
  }
}
