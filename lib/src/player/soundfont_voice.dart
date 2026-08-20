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
  });

  /// Triggers note-off volume fade and stop on the audio engine timeline.
  Future<void> release({Duration? customRelease, Duration? atTime}) async {
    if (_isReleased) return;
    _isReleased = true;

    final duration = customRelease ?? releaseDuration;
    final scheduledAt = atTime ??
        (SoLoud.instance.isInitialized
            ? (SoLoud.instance.isRenderAheadEnabled
                ? SoLoud.instance.getPlayheadTime()
                : SoLoud.instance.getEngineTime())
            : Duration.zero);

    for (final handle in handles) {
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) continue;
      try {
        if (duration > Duration.zero) {
          SoLoud.instance.fadeScheduled(
            handle,
            scheduledAt,
            0.0,
            duration,
            thenStop: true,
          );
        } else {
          SoLoud.instance.stopScheduled(handle, scheduledAt);
        }
      } catch (_) {
        try {
          if (duration > Duration.zero) {
            SoLoud.instance.fadeVolume(handle, 0.0, duration);
            SoLoud.instance.scheduleStop(handle, duration);
          } else {
            await SoLoud.instance.stop(handle);
          }
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
}
