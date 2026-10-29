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

  // Volume Envelope (EG2 - 6-stage DAHDSR)
  final double? volEnvDelay;
  final double? volEnvAttack;
  final double? volEnvHold;
  final double? volEnvDecay;

  /// Sustain attenuation in dB (`0.0` = full peak level, `100.0`+ = silent),
  /// or normalized `0.0..1.0` attenuation ratio if `<= 1.44` from legacy SF2
  /// `gens[37] / 1000.0` (1.0 = 100 dB attenuation).
  final double? volEnvSustain;
  final double? volEnvRelease;

  // Modulation Envelope (EG1 - 6-stage DAHDSR)
  final double? modEnvDelay;
  final double? modEnvAttack;
  final double? modEnvHold;
  final double? modEnvDecay;

  /// Modulation envelope sustain level (`0.0..1.0`, where `1.0` = full sustain).
  final double? modEnvSustain;
  final double? modEnvRelease;
  final int? modEnvToPitch;
  final int? modEnvToFilterFc;

  // Low-Pass Resonant Filter (SF2 Gen 8 & 9 / SFZ cutoff & resonance)
  /// Filter cutoff frequency in Hz (e.g. `20.0..20000.0`).
  final double? initialFilterCutoff;

  /// Filter resonance in dB (`0.0..96.0`, SF2 Gen 9 centibels / 10).
  final double? initialFilterQ;

  // Modulation LFO & Vibrato LFO
  final double? modLfoDelay;
  final double? modLfoFreq;
  final int? modLfoToPitch;
  final int? modLfoToFilterFc;
  final double? modLfoToVolume;
  final double? vibLfoDelay;
  final double? vibLfoFreq;
  final int? vibLfoToPitch;

  // Exclusive Class (Choke Group - SF2 Gen 57 / SFZ group & off_by)
  final int? exclusiveClass;
  final int? offByGroup;

  // Effects Send Levels (0.0 to 1.0)
  final double? reverbSend;
  final double? chorusSend;

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
    this.volEnvDelay,
    this.volEnvAttack,
    this.volEnvHold,
    this.volEnvDecay,
    this.volEnvSustain,
    this.volEnvRelease,
    this.modEnvDelay,
    this.modEnvAttack,
    this.modEnvHold,
    this.modEnvDecay,
    this.modEnvSustain,
    this.modEnvRelease,
    this.modEnvToPitch,
    this.modEnvToFilterFc,
    this.initialFilterCutoff,
    this.initialFilterQ,
    this.modLfoDelay,
    this.modLfoFreq,
    this.modLfoToPitch,
    this.modLfoToFilterFc,
    this.modLfoToVolume,
    this.vibLfoDelay,
    this.vibLfoFreq,
    this.vibLfoToPitch,
    this.exclusiveClass,
    this.offByGroup,
    this.reverbSend,
    this.chorusSend,
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
