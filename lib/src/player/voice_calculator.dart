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

  /// Calculates loop region frame boundaries ([startFrames], [endFrames])
  /// from sample frame loop boundaries.
  static ({bool isLooping, int startFrames, int? endFrames})
  calculateLoopRegion({required SampleInfo sample, Zone? zone}) {
    final startFrames = zone?.loopStart ?? sample.loopStart;
    final endFrames = zone?.loopEnd ?? sample.loopEnd;

    final loopMode =
        zone?.loopMode ??
        (endFrames > startFrames && sample.compression != SampleCompression.ogg
            ? LoopMode.continuous
            : LoopMode.none);

    final shouldLoop =
        loopMode == LoopMode.continuous || loopMode == LoopMode.sustain;

    if (!shouldLoop || endFrames <= startFrames) {
      return (isLooping: false, startFrames: 0, endFrames: null);
    }

    return (isLooping: true, startFrames: startFrames, endFrames: endFrames);
  }

  /// Resolves the volume envelope release duration.
  /// If the zone or preset zone has native release ([volEnvRelease] > 0),
  /// [sustainMultiplier] scales that duration.
  /// Otherwise, [sustainTime] (or [defaultDuration]) is applied.
  static Duration calculateReleaseDuration({
    Zone? zone,
    Zone? presetZone,
    Duration defaultDuration = const Duration(milliseconds: 150),
    double? sustainTime,
    double sustainMultiplier = 1.0,
  }) {
    final releaseSec = zone?.volEnvRelease ?? presetZone?.volEnvRelease;
    if (releaseSec != null && releaseSec > 0) {
      if (sustainMultiplier <= 0.0) return Duration.zero;
      final effectiveSec = releaseSec * sustainMultiplier;
      final micros = (effectiveSec * 1000000).round();
      return Duration(microseconds: math.max(1000, micros));
    }
    if (sustainTime != null) {
      if (sustainTime <= 0.0) return Duration.zero;
      final micros = (sustainTime * 1000000).round();
      return Duration(microseconds: math.max(1000, micros));
    }
    return defaultDuration;
  }
}
