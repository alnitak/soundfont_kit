import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'realtime_synthesizer.dart';

/// Represents one or more active [SoundHandle] (or worker-isolate voice)
/// instances triggered for a note.
class SoundFontVoice {
  /// The MIDI key (0..127) for this voice.
  final int key;

  /// The MIDI velocity (0..127) for this voice.
  final int velocity;

  /// The active SoLoud sound handles playing this voice.
  final List<SoundHandle> handles;

  /// The backing audio sources.
  final List<AudioSource> sources;

  /// The volume envelope release duration.
  final Duration releaseDuration;

  /// Optional ID of the SampleInfo played by this voice.
  final int? sampleId;

  /// The baseline relative play speed per handle (derived from pitch calculation).
  final List<double> baseSpeeds;

  /// The baseline volume per handle.
  final List<double> baseVolumes;

  /// The baseline stereo pan per handle (-1.0 to 1.0).
  final List<double> basePans;

  /// The DAHDSR sustain level ratio (`0.0..1.0` relative to peak volume) per handle.
  final List<double> sustainRatios;

  /// The DAHDSR decay duration per handle.
  final List<Duration> decayDurations;

  /// The engine timestamp when the DAHDSR decay stage starts per handle.
  final List<Duration> decayStartEngineTimes;

  /// Exclusive class (choke group) IDs associated with this voice (SF2 Gen 57 / SFZ `group`).
  final Set<int> exclusiveClasses;

  /// Worker-isolate voice IDs when played via [RealtimeSoundFontSynthesizer].
  final List<int> realtimeVoiceIds;

  /// Backing [RealtimeSoundFontSynthesizer] when played in isolate synth mode.
  final RealtimeSoundFontSynthesizer? realtimeSynth;

  final List<Timer> _envelopeTimers = [];
  final List<Timer> _volumeTimers = [];

  bool _isReleased = false;
  DateTime? _releaseEndWallTime;

  /// Whether note-off release has already been triggered for this voice.
  bool get isReleased => _isReleased;

  /// Creates a [SoundFontVoice] tracking active [handles] for MIDI [key] and [velocity].
  SoundFontVoice({
    required this.key,
    required this.velocity,
    required this.handles,
    this.sources = const [],
    this.releaseDuration = const Duration(milliseconds: 150),
    this.sampleId,
    List<double>? baseSpeeds,
    List<double>? baseVolumes,
    List<double>? basePans,
    List<double>? sustainRatios,
    List<Duration>? decayDurations,
    List<Duration>? decayStartEngineTimes,
    double? initialVolumeMultiplier,
    double? initialPanOffset,
    Set<int>? exclusiveClasses,
    this.realtimeVoiceIds = const [],
    this.realtimeSynth,
  }) : baseSpeeds = baseSpeeds ?? List.filled(handles.length, 1.0),
       baseVolumes = baseVolumes ?? List.filled(handles.length, 1.0),
       basePans = basePans ?? List.filled(handles.length, 0.0),
       sustainRatios = sustainRatios ?? List.filled(handles.length, 1.0),
       decayDurations =
           decayDurations ?? List.filled(handles.length, Duration.zero),
       decayStartEngineTimes =
           decayStartEngineTimes ?? List.filled(handles.length, Duration.zero),
       _lastVolumeMultiplier = initialVolumeMultiplier,
       _lastPan = initialPanOffset,
       exclusiveClasses = exclusiveClasses ?? const {};

  /// Registers an internal DAHDSR stage [timer] that will be automatically
  /// cancelled if the voice is released or stopped early.
  void addEnvelopeTimer(Timer timer) {
    if (_isReleased) {
      timer.cancel();
      return;
    }
    _envelopeTimers.add(timer);
  }

  void _cancelVolumeTimers() {
    for (final t in _volumeTimers) {
      t.cancel();
    }
    _volumeTimers.clear();
  }

  void _cancelEnvelopeTimers() {
    _cancelVolumeTimers();
    for (final t in _envelopeTimers) {
      t.cancel();
    }
    _envelopeTimers.clear();
  }

  /// Fast 6 ms anti-click choke used when an Exclusive Class (`exclusiveClass` / `off_by`)
  /// group is re-triggered (e.g. Closed Hi-Hat choking Open Hi-Hat), optionally scheduled at [atTime].
  Future<void> choke({Duration? atTime}) async {
    _cancelEnvelopeTimers();
    await release(
      customRelease: const Duration(milliseconds: 6),
      atTime: atTime,
    );
  }

  /// Triggers note-off volume fade and stop on the audio engine timeline,
  /// using [customRelease] (or [releaseDuration]) starting at [atTime].
  Future<void> release({Duration? customRelease, Duration? atTime}) async {
    _cancelEnvelopeTimers();
    if (customRelease != null && customRelease <= Duration.zero) {
      await stop();
      return;
    }
    final duration = customRelease ?? releaseDuration;
    if (duration <= Duration.zero) {
      await stop();
      return;
    }
    final nowWall = DateTime.now();
    final newEndWall = nowWall.add(duration);
    if (_isReleased) {
      if (customRelease == null) return;
      if (_releaseEndWallTime != null &&
          !newEndWall.isBefore(
            _releaseEndWallTime!.subtract(const Duration(milliseconds: 5)),
          )) {
        return;
      }
    }
    _isReleased = true;
    _releaseEndWallTime = newEndWall;

    if (realtimeSynth != null && realtimeVoiceIds.isNotEmpty) {
      for (final id in realtimeVoiceIds) {
        realtimeSynth!.releaseVoiceId(id, customRelease: duration);
      }
    }

    final fadeDuration = duration;
    final effectiveAtTime = atTime;

    for (final handle in handles) {
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) continue;
      try {
        final at = effectiveAtTime ??
            (SoLoud.instance.isInitialized
                ? SoLoud.instance.getEngineTime()
                : Duration.zero);
        SoLoud.instance.fadeScheduled(
          handle,
          at,
          0.0,
          fadeDuration,
          thenStop: true,
        );
      } catch (_) {
        try {
          SoLoud.instance.stop(handle);
        } catch (_) {}
      }
    }
  }

  /// Stops this voice at an absolute engine time [atTime] with sample accuracy.
  void stopScheduled(Duration atTime) {
    _cancelEnvelopeTimers();
    _isReleased = true;
    for (final handle in handles) {
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) continue;
      try {
        SoLoud.instance.stopScheduled(handle, atTime);
      } catch (_) {}
    }
  }

  /// Fades this voice to volume [to] over [time] starting at absolute engine time [atTime],
  /// optionally stopping the voice when the fade completes if [thenStop] is `true`.
  void fadeScheduled(
    Duration atTime, {
    required double to,
    required Duration time,
    bool thenStop = false,
  }) {
    for (final handle in handles) {
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) continue;
      try {
        SoLoud.instance.fadeScheduled(
          handle,
          atTime,
          to,
          time,
          thenStop: thenStop,
        );
      } catch (_) {}
    }
  }

  /// Immediately stops all voice handles.
  Future<void> stop() async {
    _cancelEnvelopeTimers();
    _isReleased = true;
    if (realtimeSynth != null && realtimeVoiceIds.isNotEmpty) {
      for (final id in realtimeVoiceIds) {
        realtimeSynth!.stopVoiceId(id);
      }
    }
    for (final handle in handles) {
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) continue;
      try {
        await SoLoud.instance.stop(handle);
      } catch (_) {}
    }
  }

  /// Dynamically applies a relative pitch bend [bendMultiplier] to all active handles.
  void applyPitchBend(double bendMultiplier) {
    if (_isReleased) return;
    if (_lastPitchBendMultiplier != null &&
        (_lastPitchBendMultiplier! - bendMultiplier).abs() < 0.0005) {
      return;
    }
    _lastPitchBendMultiplier = bendMultiplier;
    realtimeSynth?.setPitchBend(bendMultiplier);
    for (int i = 0; i < handles.length; i++) {
      final handle = handles[i];
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) continue;
      final base = i < baseSpeeds.length ? baseSpeeds[i] : 1.0;
      try {
        SoLoud.instance.setRelativePlaySpeed(handle, base * bendMultiplier);
      } catch (_) {}
    }
  }

  double? _lastPitchBendMultiplier = 1.0;
  double? _lastVolumeMultiplier;
  double? _lastPan;

  /// Dynamically scales the volume of all active handles by [multiplier],
  /// optionally scheduled at engine time [atTime].
  void applyVolumeMultiplier(double multiplier, {Duration? atTime}) {
    if (_isReleased) return;
    if (_lastVolumeMultiplier != null &&
        (_lastVolumeMultiplier! - multiplier).abs() < 0.002) {
      return;
    }
    _lastVolumeMultiplier = multiplier;
    _cancelVolumeTimers();
    final nowEngine = SoLoud.instance.isInitialized
        ? SoLoud.instance.getEngineTime()
        : Duration.zero;
    final effectiveAt =
        (atTime != null && atTime > nowEngine) ? atTime : nowEngine;
    for (int i = 0; i < handles.length; i++) {
      final handle = handles[i];
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) continue;
      final base = i < baseVolumes.length ? baseVolumes[i] : 1.0;
      final peak = (base * multiplier).clamp(0.0, 1.0);
      final sustainRatio = i < sustainRatios.length ? sustainRatios[i] : 1.0;
      final decayDur = i < decayDurations.length
          ? decayDurations[i]
          : Duration.zero;
      final decayStart = i < decayStartEngineTimes.length
          ? decayStartEngineTimes[i]
          : Duration.zero;
      final hasDecay =
          decayDur > const Duration(milliseconds: 5) &&
          (1.0 - sustainRatio).abs() > 0.005;
      try {
        if (!hasDecay) {
          SoLoud.instance.fadeScheduled(
            handle,
            effectiveAt,
            peak,
            const Duration(milliseconds: 10),
          );
        } else if (effectiveAt <= decayStart) {
          SoLoud.instance.fadeScheduled(
            handle,
            effectiveAt,
            peak,
            const Duration(milliseconds: 6),
          );
          final targetSustain = (peak * sustainRatio).clamp(0.0, 1.0);
          final timeToDecay = decayStart - nowEngine;
          if (timeToDecay > Duration.zero) {
            _volumeTimers.add(
              Timer(timeToDecay, () {
                if (!_isReleased &&
                    SoLoud.instance.getIsValidVoiceHandle(handle)) {
                  try {
                    SoLoud.instance.fadeScheduled(
                      handle,
                      decayStart,
                      targetSustain,
                      decayDur,
                      thenStop: targetSustain <= 0.0005,
                    );
                  } catch (_) {}
                }
              }),
            );
          }
        } else {
          final elapsedUs = (effectiveAt - decayStart).inMicroseconds;
          final totalDecayUs = decayDur.inMicroseconds;
          final targetSustain = (peak * sustainRatio).clamp(0.0, 1.0);
          if (elapsedUs >= totalDecayUs) {
            SoLoud.instance.fadeScheduled(
              handle,
              effectiveAt,
              targetSustain,
              const Duration(milliseconds: 10),
            );
          } else {
            final t = (elapsedUs / totalDecayUs).clamp(0.0, 1.0);
            final currentVol = (peak + (targetSustain - peak) * t).clamp(
              0.0,
              1.0,
            );
            final remainingUs = totalDecayUs - elapsedUs;
            const rampDur = Duration(milliseconds: 12);
            SoLoud.instance.fadeScheduled(
              handle,
              effectiveAt,
              currentVol,
              rampDur,
            );
            if (remainingUs > 20000) {
              final resumeEngineAt = effectiveAt + rampDur;
              final resumeWallDelay =
                  (effectiveAt > nowEngine
                      ? effectiveAt - nowEngine
                      : Duration.zero) +
                  const Duration(milliseconds: 15);
              final remainingAfterRamp = Duration(
                microseconds: remainingUs - rampDur.inMicroseconds,
              );
              _volumeTimers.add(
                Timer(resumeWallDelay, () {
                  if (!_isReleased &&
                      SoLoud.instance.getIsValidVoiceHandle(handle)) {
                    try {
                      SoLoud.instance.fadeScheduled(
                        handle,
                        resumeEngineAt,
                        targetSustain,
                        remainingAfterRamp,
                        thenStop: targetSustain <= 0.0005,
                      );
                    } catch (_) {}
                  }
                }),
              );
            }
          }
        }
      } catch (_) {}
    }
  }

  /// Dynamically adjusts the stereo [pan] (`-1.0` to `1.0`) of all active handles.
  void applyPan(double pan) {
    if (_isReleased) return;
    if (_lastPan != null && (_lastPan! - pan).abs() < 0.002) {
      return;
    }
    _lastPan = pan;
    for (int i = 0; i < handles.length; i++) {
      final handle = handles[i];
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) continue;
      final basePan = i < basePans.length ? basePans[i] : 0.0;
      try {
        SoLoud.instance.setPan(handle, (basePan + pan).clamp(-1.0, 1.0));
      } catch (_) {}
    }
  }
}
