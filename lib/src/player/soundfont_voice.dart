import 'package:flutter_soloud/flutter_soloud.dart';

/// Represents one or more active [SoundHandle] instances triggered for a note.
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

  bool _isReleased = false;

  /// Whether note-off release has already been triggered for this voice.
  bool get isReleased => _isReleased;

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
  })  : baseSpeeds = baseSpeeds ?? List.filled(handles.length, 1.0),
        baseVolumes = baseVolumes ?? List.filled(handles.length, 1.0),
        basePans = basePans ?? List.filled(handles.length, 0.0);

  /// Triggers note-off volume fade and stop on the audio engine timeline.
  Future<void> release({Duration? customRelease, Duration? atTime}) async {
    if (customRelease != null && customRelease <= Duration.zero) {
      await stop();
      return;
    }
    if (_isReleased) return;
    _isReleased = true;

    final duration = customRelease ?? releaseDuration;
    if (duration <= Duration.zero) {
      await stop();
      return;
    }

    final fadeDuration = duration;

    for (final handle in handles) {
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) continue;
      try {
        if (atTime != null) {
          SoLoud.instance.fadeScheduled(
            handle,
            atTime,
            0.0,
            fadeDuration,
            thenStop: true,
          );
        } else {
          SoLoud.instance.fadeVolume(handle, 0.0, fadeDuration);
          SoLoud.instance.scheduleStop(handle, fadeDuration);
        }
      } catch (_) {
        try {
          SoLoud.instance.stop(handle);
        } catch (_) {}
      }
    }
  }

  /// Stops this voice at an absolute engine time with sample accuracy.
  void stopScheduled(Duration atTime) {
    _isReleased = true;
    for (final handle in handles) {
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) continue;
      try {
        SoLoud.instance.stopScheduled(handle, atTime);
      } catch (_) {}
    }
  }

  /// Fades this voice starting at an absolute engine time.
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
    _isReleased = true;
    for (final handle in handles) {
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) continue;
      try {
        await SoLoud.instance.stop(handle);
      } catch (_) {}
    }
  }

  /// Dynamically applies a relative pitch bend multiplier to all active handles.
  void applyPitchBend(double bendMultiplier) {
    if (_isReleased) return;
    for (int i = 0; i < handles.length; i++) {
      final handle = handles[i];
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) continue;
      final base = i < baseSpeeds.length ? baseSpeeds[i] : 1.0;
      try {
        SoLoud.instance.setRelativePlaySpeed(handle, base * bendMultiplier);
      } catch (_) {}
    }
  }

  /// Dynamically scales the volume of all active handles by [multiplier].
  void applyVolumeMultiplier(double multiplier) {
    if (_isReleased) return;
    for (int i = 0; i < handles.length; i++) {
      final handle = handles[i];
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) continue;
      final base = i < baseVolumes.length ? baseVolumes[i] : 1.0;
      try {
        SoLoud.instance.setVolume(
          handle,
          (base * multiplier).clamp(0.0, 1.0),
        );
      } catch (_) {}
    }
  }

  /// Dynamically adjusts the stereo pan of all active handles.
  void applyPan(double pan) {
    if (_isReleased) return;
    for (final handle in handles) {
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) continue;
      try {
        SoLoud.instance.setPan(handle, pan.clamp(-1.0, 1.0));
      } catch (_) {}
    }
  }
}
