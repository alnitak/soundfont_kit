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

  const SoundFontPlayerOptions({
    this.joinStereoChannels = true,
    this.cacheAudioSources = true,
    this.streamChunkSize = 65536,
    this.defaultBusId = 0,
    this.defaultReleaseDuration = const Duration(milliseconds: 150),
    this.masterVolume = 1.0,
  });

  SoundFontPlayerOptions copyWith({
    bool? joinStereoChannels,
    bool? cacheAudioSources,
    int? streamChunkSize,
    int? defaultBusId,
    Duration? defaultReleaseDuration,
    double? masterVolume,
  }) {
    return SoundFontPlayerOptions(
      joinStereoChannels: joinStereoChannels ?? this.joinStereoChannels,
      cacheAudioSources: cacheAudioSources ?? this.cacheAudioSources,
      streamChunkSize: streamChunkSize ?? this.streamChunkSize,
      defaultBusId: defaultBusId ?? this.defaultBusId,
      defaultReleaseDuration:
          defaultReleaseDuration ?? this.defaultReleaseDuration,
      masterVolume: masterVolume ?? this.masterVolume,
    );
  }
}
