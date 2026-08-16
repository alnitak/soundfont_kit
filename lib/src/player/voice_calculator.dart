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
    final rootKey = zone?.rootKey ??
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

  /// Calculates loop region timestamps ([loopingStartAt], [loopingEndAt])
  /// from sample frame loop boundaries.
  static ({bool isLooping, Duration loopStart, Duration? loopEnd})
      calculateLoopRegion({
    required SampleInfo sample,
    Zone? zone,
  }) {
    final startFrames = zone?.loopStart ?? sample.loopStart;
    final endFrames = zone?.loopEnd ?? sample.loopEnd;

    final loopMode = zone?.loopMode ??
        (endFrames > startFrames && sample.compression != SampleCompression.ogg
            ? LoopMode.continuous
            : LoopMode.none);

    final shouldLoop = loopMode == LoopMode.continuous ||
        loopMode == LoopMode.sustain;

    if (!shouldLoop || sample.sampleRate <= 0 || endFrames <= startFrames) {
      return (
        isLooping: false,
        loopStart: Duration.zero,
        loopEnd: null,
      );
    }

    final startMicros = ((startFrames / sample.sampleRate) * 1000000).round();
    final endMicros = ((endFrames / sample.sampleRate) * 1000000).round();

    if (endMicros <= startMicros) {
      return (
        isLooping: false,
        loopStart: Duration.zero,
        loopEnd: null,
      );
    }

    final loopStart = Duration(microseconds: math.max(0, startMicros));
    final loopEnd = Duration(microseconds: endMicros);

    return (
      isLooping: true,
      loopStart: loopStart,
      loopEnd: loopEnd,
    );
  }

  /// Resolves the volume envelope release duration.
  static Duration calculateReleaseDuration({
    Zone? zone,
    Zone? presetZone,
    Duration defaultDuration = const Duration(milliseconds: 150),
  }) {
    final releaseSec = zone?.volEnvRelease ?? presetZone?.volEnvRelease;
    if (releaseSec != null && releaseSec > 0) {
      final micros = (releaseSec * 1000000).round();
      return Duration(microseconds: math.max(10000, micros));
    }
    return defaultDuration;
  }
}
