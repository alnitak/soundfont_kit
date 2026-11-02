import 'dart:math' as math;

import '../models/sample_info.dart';
import '../models/soundfont_format.dart';
import '../models/zone.dart';

/// SoundFont voice synthesis and parameter calculation utilities.
class VoiceCalculator {
  const VoiceCalculator._();

  /// Calculates the relative playback speed ratio for a given MIDI key.
  ///
  /// SoundFont pitch calculation:
  /// - `rootKey` defaults to [Zone.rootKey], then [SampleInfo.originalPitch], or 60 (Middle C).
  /// - `fineTune` is the sum of [Zone.pitchCorrection], [SampleInfo.pitchCorrection], and generator tuning.
  /// - Ratio: 2 ^ ((key - rootKey + (cents / 100)) / 12).
  static double calculatePitchRatio({
    required int key,
    required SampleInfo sample,
    Zone? zone,
    Zone? presetZone,
  }) {
    // Root key
    final rootKey =
        zone?.rootKey ??
        presetZone?.rootKey ??
        (sample.originalPitch > 0 ? sample.originalPitch : 60);

    // Fine tune in cents
    final zoneCents = zone?.pitchCorrection ?? 0;
    final presetCents = presetZone?.pitchCorrection ?? 0;
    final sampleCents = sample.pitchCorrection;
    final totalCents = zoneCents + presetCents + sampleCents;

    final semitones = (key - rootKey) + (totalCents / 100.0);
    final ratio = math.pow(2.0, semitones / 12.0).toDouble();

    // SoLoud clamps minimum speed to 0.05 to avoid undefined engine behavior
    return math.max(0.05, ratio);
  }

  /// Calculates the linear playback volume (0.0 to 1.0+) from MIDI velocity,
  /// zone attenuation in dB, and master volume.
  static double calculateVolume({
    required int velocity,
    Zone? zone,
    Zone? presetZone,
    double masterVolume = 1.0,
  }) {
    if (velocity <= 0) return 0.0;

    // Standard quadratic velocity response
    final normalizedVel = (velocity.clamp(1, 127)) / 127.0;
    final velGain = normalizedVel * normalizedVel;

    // Attenuation in dB (0 dB = full volume, positive values reduce volume)
    final zoneAtten = zone?.attenuation ?? 0.0;
    final presetAtten = presetZone?.attenuation ?? 0.0;
    final totalAttenDb = zoneAtten + presetAtten;

    // Convert dB attenuation to linear gain: 10 ^ (-dB / 20)
    final attenGain = totalAttenDb > 0
        ? math.pow(10.0, -totalAttenDb / 20.0).toDouble()
        : 1.0;

    final vol = masterVolume * velGain * attenGain;
    return vol.clamp(0.0, 2.0);
  }

  /// Calculates pan position (-1.0 left to +1.0 right).
  static double calculatePan({
    Zone? zone,
    Zone? presetZone,
    SampleInfo? sample,
  }) {
    // Check zone pan
    double pan = 0.0;
    if (zone?.pan != null) {
      pan += zone!.pan!;
    }
    if (presetZone?.pan != null) {
      pan += presetZone!.pan!;
    }

    // If sample is left or right, adjust default pan if zone pan is neutral
    if (sample != null && zone?.pan == null && presetZone?.pan == null) {
      if (sample.isLeft) {
        pan = -1.0;
      } else if (sample.isRight) {
        pan = 1.0;
      }
    }

    return pan.clamp(-1.0, 1.0);
  }

  /// Calculates loop region frame boundaries (`startFrames` and `endFrames`)
  /// from [sample] and optional [zone] overrides.
  static ({bool isLooping, int startFrames, int? endFrames})
  calculateLoopRegion({required SampleInfo sample, Zone? zone}) {
    final startFrames = zone?.loopStart ?? sample.loopStart;
    final endFrames = zone?.loopEnd ?? sample.loopEnd;

    // Minimum frames for a valid audible loop. Dummy header loops
    // (startloop=start, endloop=start+1) used for unlooped SF2 samples are < 16 frames.
    const minLoopFrames = 16;
    final hasValidLoopSpan =
        startFrames >= 0 && (endFrames - startFrames) >= minLoopFrames;

    final loopMode =
        zone?.loopMode ??
        (hasValidLoopSpan && sample.compression != SampleCompression.ogg
            ? LoopMode.continuous
            : LoopMode.none);

    final shouldLoop =
        (loopMode == LoopMode.continuous || loopMode == LoopMode.sustain) &&
        hasValidLoopSpan;

    if (!shouldLoop || startFrames < 0 || endFrames <= startFrames) {
      return (isLooping: false, startFrames: 0, endFrames: null);
    }

    return (isLooping: true, startFrames: startFrames, endFrames: endFrames);
  }

  /// Resolves the volume envelope release duration.
  ///
  /// Applies [sustain] proportionally across all SoundFont types:
  /// - Instruments with native release envelopes (`volEnvRelease > 0`):
  ///   scales the authentic envelope: `volEnvRelease * sustain`.
  /// - Instruments without native release envelopes:
  ///   scales the fallback release duration: `(sustainTime ?? defaultDuration) * sustain`.
  ///
  /// If [sustain] (or legacy [sustainMultiplier]) is `<= 0.0`, returns [Duration.zero]
  /// for immediate staccato key cutoff.
  static Duration calculateReleaseDuration({
    Zone? zone,
    Zone? presetZone,
    Duration defaultDuration = const Duration(milliseconds: 250),
    double? sustainTime,
    double sustain = 1.0,
    double? sustainMultiplier,
  }) {
    final effectiveSustain = sustainMultiplier ?? sustain;
    if (effectiveSustain <= 0.0) return Duration.zero;

    final releaseSec = zone?.volEnvRelease ?? presetZone?.volEnvRelease;
    final double baseSec;
    if (releaseSec != null && releaseSec > 0) {
      baseSec = releaseSec;
    } else if (sustainTime != null && sustainTime > 0) {
      baseSec = sustainTime;
    } else {
      baseSec = defaultDuration.inMicroseconds / 1000000.0;
    }

    final effectiveSec = baseSec * effectiveSustain;
    final micros = (effectiveSec * 1000000).round();
    return Duration(microseconds: math.max(1000, micros));
  }

  /// Resolves the 5 pre-release stages of the 6-stage DAHDSR Volume Envelope:
  /// Delay, Attack, Hold, Decay, and linear Sustain target volume.
  static ({
    Duration delay,
    Duration attack,
    Duration hold,
    Duration decay,
    double sustainVolume,
  })
  calculateVolEnvStages({
    Zone? zone,
    Zone? presetZone,
    required double peakVolume,
  }) {
    final delaySec = zone?.volEnvDelay ?? presetZone?.volEnvDelay ?? 0.0;
    final attackSec = zone?.volEnvAttack ?? presetZone?.volEnvAttack ?? 0.0;
    final holdSec = zone?.volEnvHold ?? presetZone?.volEnvHold ?? 0.0;
    final decaySec = zone?.volEnvDecay ?? presetZone?.volEnvDecay ?? 0.0;
    final rawSustain = zone?.volEnvSustain ?? presetZone?.volEnvSustain;

    double sustainRatio = 1.0;
    if (rawSustain != null) {
      if (zone?.opcodes.containsKey('ampeg_sustain') == true) {
        // SFZ ampeg_sustain is percentage 0..100
        sustainRatio = (rawSustain / 100.0).clamp(0.0, 1.0);
      } else {
        // SF2 generator 37 is stored as gens[37] / 1000.0 where 1.0 = 100 dB attenuation
        final attenDb = (rawSustain * 100.0).clamp(0.0, 144.0);
        sustainRatio = attenDb >= 100.0
            ? 0.0
            : math.pow(10.0, -attenDb / 20.0).toDouble();
      }
    }

    Duration toDur(double sec) => sec > 0.001
        ? Duration(microseconds: (sec * 1000000).round())
        : Duration.zero;

    return (
      delay: toDur(delaySec),
      attack: toDur(attackSec),
      hold: toDur(holdSec),
      decay: toDur(decaySec),
      sustainVolume: (peakVolume * sustainRatio).clamp(0.0, 2.0),
    );
  }

  /// Resolves per-voice low-pass filter cutoff (Hz) and resonance Q from
  /// instrument and preset zones.
  static ({bool enabled, double cutoffHz, double resonanceQ})
  calculateFilterParams({Zone? zone, Zone? presetZone}) {
    final cutoff = zone?.initialFilterCutoff ?? presetZone?.initialFilterCutoff;
    final qDb = zone?.initialFilterQ ?? presetZone?.initialFilterQ ?? 0.0;

    if (cutoff == null && qDb <= 0.0) {
      return (enabled: false, cutoffHz: 20000.0, resonanceQ: 0.707);
    }

    final effectiveCutoff = (cutoff ?? 19900.0).clamp(20.0, 20000.0);
    if (effectiveCutoff >= 18500.0 && qDb <= 0.5) {
      return (enabled: false, cutoffHz: effectiveCutoff, resonanceQ: 0.707);
    }

    // Convert resonance in dB (0..96 dB) to SoLoud Biquad / SVF Q factor (0.707..20.0)
    final linearQ = (0.707 * math.pow(10.0, qDb / 40.0)).clamp(0.5, 25.0);
    return (
      enabled: true,
      cutoffHz: effectiveCutoff,
      resonanceQ: linearQ.toDouble(),
    );
  }

  /// Resolves the Exclusive Class (choke group) and Off-By group IDs for a zone.
  static ({int? exclusiveClass, int? offByGroup}) resolveExclusiveClass({
    Zone? zone,
    Zone? presetZone,
  }) {
    final exc = zone?.exclusiveClass ?? presetZone?.exclusiveClass;
    final offBy = zone?.offByGroup ?? presetZone?.offByGroup ?? exc;
    if (exc == null || exc <= 0) {
      return (exclusiveClass: null, offByGroup: null);
    }
    return (exclusiveClass: exc, offByGroup: offBy);
  }
}
