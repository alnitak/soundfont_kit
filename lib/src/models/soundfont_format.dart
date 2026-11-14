/// Supported SoundFont file formats.
enum SoundFontFormat {
  /// SoundFont 2 (`.sf2`) RIFF binary container with uncompressed PCM samples.
  sf2,

  /// SoundFont 3 (`.sf3`) RIFF binary container with Ogg Vorbis or FLAC compressed samples.
  sf3,

  /// SFZ (`.sfz`) text definition format with external `.wav`, `.flac`, or `.ogg` sample files.
  sfz,
}

/// Compression or encoding type of sample audio data.
enum SampleCompression {
  /// Uncompressed 8-bit signed PCM.
  pcm8,

  /// Uncompressed 16-bit signed little-endian PCM (standard SF2 format).
  pcm16,

  /// Uncompressed 24-bit signed little-endian PCM (high-definition SF2 `sm24`).
  pcm24,

  /// Uncompressed 32-bit signed little-endian integer PCM.
  pcm32,

  /// Uncompressed 32-bit IEEE floating-point PCM.
  pcmFloat32,

  /// Ogg Vorbis compressed audio (standard SF3 format).
  ogg,

  /// Free Lossless Audio Codec (FLAC) compressed audio.
  flac,

  /// RIFF WAVE (`.wav`) container format.
  wav,
}

/// Loop playback mode for a SoundFont sample or zone.
enum LoopMode {
  /// Sample plays once from start to end without looping.
  none,

  /// Sample loops continuously between `loopStart` and `loopEnd` for the entire voice duration.
  continuous,

  /// Sample loops between `loopStart` and `loopEnd` while the key is held, then plays to the end on release.
  sustain,
}
