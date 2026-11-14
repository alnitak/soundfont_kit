import 'modulator_info.dart';
import 'sample_info.dart';
import 'soundfont_format.dart';

/// Represents a synthesis region or zone within an `Instrument` or `Preset`.
class Zone {
  /// Lowest MIDI key number (`0..127`) covered by this zone.
  final int keyRangeMin;

  /// Highest MIDI key number (`0..127`) covered by this zone.
  final int keyRangeMax;

  /// Lowest MIDI note-on velocity (`0..127`) covered by this zone.
  final int velRangeMin;

  /// Highest MIDI note-on velocity (`0..127`) covered by this zone.
  final int velRangeMax;

  /// Overriding root MIDI key number (`0..127`, SF2 Gen 58 `overridingRootKey`).
  final int? rootKey;

  /// Combined coarse and fine tuning offset in cents (SF2 Gen 51 `coarseTune` * 100 + Gen 52 `fineTune`).
  final int? pitchCorrection;

  /// Initial volume attenuation in decibels (SF2 Gen 48 `initialAttenuation` in centibels / 10).
  final double? attenuation;

  /// Stereo pan position from `-1.0` (hard left) through `0.0` (center) to `1.0` (hard right).
  final double? pan;

  /// Index of the target [SampleInfo] in the SoundFont's sample list (for instrument zones).
  final int? sampleID;

  /// Direct reference to the resolved [SampleInfo] for this zone, if any.
  final SampleInfo? sampleRef;

  /// Index of the target `Instrument` in the SoundFont's instrument list (for preset zones).
  final int? instrumentID;

  /// Overriding sample loop mode (SF2 Gen 54 `sampleModes`).
  final LoopMode? loopMode;

  /// Overriding loop start position in sample frames.
  final int? loopStart;

  /// Overriding loop end position in sample frames.
  final int? loopEnd;

  // Volume Envelope (EG2 - 6-stage DAHDSR)

  /// Volume envelope delay phase duration in seconds (SF2 Gen 33 `delayVolEnv`).
  final double? volEnvDelay;

  /// Volume envelope attack phase duration in seconds (SF2 Gen 34 `attackVolEnv`).
  final double? volEnvAttack;

  /// Volume envelope hold phase duration in seconds (SF2 Gen 35 `holdVolEnv`).
  final double? volEnvHold;

  /// Volume envelope decay phase duration in seconds (SF2 Gen 36 `decayVolEnv`).
  final double? volEnvDecay;

  /// Sustain attenuation in dB (`0.0` = full peak level, `100.0`+ = silent),
  /// or normalized `0.0..1.0` attenuation ratio if `<= 1.44` from legacy SF2
  /// `gens[37] / 1000.0` (`1.0` = 100 dB attenuation).
  final double? volEnvSustain;

  /// Volume envelope release phase duration in seconds (SF2 Gen 38 `releaseVolEnv`).
  final double? volEnvRelease;

  // Modulation Envelope (EG1 - 6-stage DAHDSR)

  /// Modulation envelope delay phase duration in seconds (SF2 Gen 25 `delayModEnv`).
  final double? modEnvDelay;

  /// Modulation envelope attack phase duration in seconds (SF2 Gen 26 `attackModEnv`).
  final double? modEnvAttack;

  /// Modulation envelope hold phase duration in seconds (SF2 Gen 27 `holdModEnv`).
  final double? modEnvHold;

  /// Modulation envelope decay phase duration in seconds (SF2 Gen 28 `decayModEnv`).
  final double? modEnvDecay;

  /// Modulation envelope sustain level (`0.0..1.0`, where `1.0` = full sustain).
  final double? modEnvSustain;

  /// Modulation envelope release phase duration in seconds (SF2 Gen 30 `releaseModEnv`).
  final double? modEnvRelease;

  /// Pitch modulation depth from the modulation envelope in cents (SF2 Gen 7 `modEnvToPitch`).
  final int? modEnvToPitch;

  /// Low-pass filter cutoff modulation depth from the modulation envelope in cents (SF2 Gen 11 `modEnvToFilterFc`).
  final int? modEnvToFilterFc;

  // Low-Pass Resonant Filter (SF2 Gen 8 & 9 / SFZ cutoff & resonance)

  /// Filter cutoff frequency in Hz (e.g. `20.0..20000.0`, SF2 Gen 8 `initialFilterFc`).
  final double? initialFilterCutoff;

  /// Filter resonance in dB (`0.0..96.0`, SF2 Gen 9 `initialFilterQ` centibels / 10).
  final double? initialFilterQ;

  // Modulation LFO & Vibrato LFO

  /// Delay in seconds before the modulation LFO begins oscillating (SF2 Gen 21 `delayModLFO`).
  final double? modLfoDelay;

  /// Modulation LFO frequency in Hz (SF2 Gen 22 `freqModLFO`).
  final double? modLfoFreq;

  /// Pitch modulation depth from the modulation LFO in cents (SF2 Gen 5 `modLfoToPitch`).
  final int? modLfoToPitch;

  /// Filter cutoff modulation depth from the modulation LFO in cents (SF2 Gen 10 `modLfoToFilterFc`).
  final int? modLfoToFilterFc;

  /// Volume modulation depth (tremolo) from the modulation LFO in dB (SF2 Gen 13 `modLfoToVolume`).
  final double? modLfoToVolume;

  /// Delay in seconds before the vibrato LFO begins oscillating (SF2 Gen 23 `delayVibLFO`).
  final double? vibLfoDelay;

  /// Vibrato LFO frequency in Hz (SF2 Gen 24 `freqVibLFO`).
  final double? vibLfoFreq;

  /// Pitch modulation depth (vibrato) from the vibrato LFO in cents (SF2 Gen 6 `vibLfoToPitch`).
  final int? vibLfoToPitch;

  // Exclusive Class (Choke Group - SF2 Gen 57 / SFZ group & off_by)

  /// Exclusive class group number (`1..127`, SF2 Gen 57 `exclusiveClass` / SFZ `group`).
  final int? exclusiveClass;

  /// Exclusive class group number that chokes voices in this zone (SF2 Gen 57 / SFZ `off_by`).
  final int? offByGroup;

  // Effects Send Levels (0.0 to 1.0)

  /// Reverb effects send level (`0.0..1.0`, SF2 Gen 16 `reverbEffectsSend`).
  final double? reverbSend;

  /// Chorus effects send level (`0.0..1.0`, SF2 Gen 15 `chorusEffectsSend`).
  final double? chorusSend;

  /// Raw generator IDs mapped to unsigned 16-bit values (for SF2 and SF3).
  final Map<int, int> generators;

  /// Raw SF2 modulator definitions attached to this zone.
  final List<ModulatorInfo> modulators;

  /// Raw SFZ opcode key-value pairs (for SFZ format).
  final Map<String, String> opcodes;

  /// Creates a synthesis [Zone] with the specified key/velocity bounds and synthesis parameters.
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

  /// Whether the given MIDI [key] (`0..127`) and [velocity] (`0..127`) fall within this zone's ranges.
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
