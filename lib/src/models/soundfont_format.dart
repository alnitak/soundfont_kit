/// Supported SoundFont file formats.
enum SoundFontFormat {
  sf2,
  sf3,
  sfz,
}

/// Compression or encoding type of sample data.
enum SampleCompression {
  pcm8,
  pcm16,
  pcm24,
  pcm32,
  pcmFloat32,
  ogg,
  flac,
  wav,
}

/// Loop mode for sample playback.
enum LoopMode {
  none,
  continuous,
  sustain,
}
