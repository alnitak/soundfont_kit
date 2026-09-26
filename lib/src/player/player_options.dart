/// Configuration options for [SoundFontPlayer].
class SoundFontPlayerOptions {
  /// Whether to automatically interleave and join paired Left and Right
  /// 16-bit PCM channels into a single stereo audio source.
  final bool joinStereoChannels;

  /// Whether to cache created [AudioSource] instances in memory for fast
  /// repeated note playback (e.g. real-time keyboard).
  final bool cacheAudioSources;

  /// Chunk size in bytes when streaming sample bytes into SoLoud.
  final int streamChunkSize;

  /// Default mixing bus ID to route audio to (0 = main engine output).
  final int defaultBusId;

  /// Default release duration applied when stopping or releasing a note if
  /// the zone does not specify a volume envelope release time.
  final Duration defaultReleaseDuration;

  /// Master volume scale (0.0 to 1.0+).
  final double masterVolume;

  /// Whether to use SoLoud's sample-accurate [playScheduled] and [fadeScheduled]
  /// engine clock by default for unlooped voice playback.
  final bool useScheduledPlayback;

  /// Whether to eagerly preload all samples and prepare audio sources
  /// upon player creation.
  final bool preloadAllSamples;

  /// Optional fallback sustain/release duration in seconds (e.g. 0.05 to 5.0).
  /// Used when an instrument or zone has no native release envelope.
  /// If provided, this base duration is multiplied by [sustain].
  final double? sustainTime;

  /// Global master sustain factor (e.g. 0.0 to 10.0, default 1.0).
  ///
  /// Works across all SoundFonts:
  /// - Scales authentic release envelopes for instruments with native release.
  /// - Scales fallback decay ([sustainTime] or default duration) for instruments without.
  /// - `0.0`: Staccato cutoff upon note release.
  /// - `1.0`: Natural authentic release.
  /// - `> 1.0`: Extended sustain (damper pedal simulation).
  final double sustain;

  /// Deprecated alias for [sustain].
  double get sustainMultiplier => sustain;

  const SoundFontPlayerOptions({
    this.joinStereoChannels = true,
    this.cacheAudioSources = true,
    this.streamChunkSize = 16384,
    this.defaultBusId = 0,
    this.defaultReleaseDuration = const Duration(milliseconds: 150),
    this.masterVolume = 1.0,
    this.useScheduledPlayback = false,
    this.preloadAllSamples = false,
    double sustain = 1.0,
    double? sustainMultiplier,
    this.sustainTime,
  }) : sustain = sustainMultiplier ?? sustain;

  SoundFontPlayerOptions copyWith({
    bool? joinStereoChannels,
    bool? cacheAudioSources,
    int? streamChunkSize,
    int? defaultBusId,
    Duration? defaultReleaseDuration,
    double? masterVolume,
    bool? useScheduledPlayback,
    bool? preloadAllSamples,
    double? sustain,
    double? sustainMultiplier,
    double? sustainTime,
  }) {
    return SoundFontPlayerOptions(
      joinStereoChannels: joinStereoChannels ?? this.joinStereoChannels,
      cacheAudioSources: cacheAudioSources ?? this.cacheAudioSources,
      streamChunkSize: streamChunkSize ?? this.streamChunkSize,
      defaultBusId: defaultBusId ?? this.defaultBusId,
      defaultReleaseDuration:
          defaultReleaseDuration ?? this.defaultReleaseDuration,
      masterVolume: masterVolume ?? this.masterVolume,
      useScheduledPlayback: useScheduledPlayback ?? this.useScheduledPlayback,
      preloadAllSamples: preloadAllSamples ?? this.preloadAllSamples,
      sustain: sustain ?? sustainMultiplier ?? this.sustain,
      sustainTime: sustainTime ?? this.sustainTime,
    );
  }
}
