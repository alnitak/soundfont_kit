import 'soundfont_format.dart';

/// Metadata for an audio sample stored or referenced by a SoundFont.
class SampleInfo {
  /// The unique 0-based index of this sample within the SoundFont.
  final int id;

  /// The human-readable name of the sample.
  final String name;

  /// Sample rate in Hz (e.g., `44100`).
  final int sampleRate;

  /// Original MIDI root pitch of the recorded sample (`0..127`, where `60` is Middle C).
  final int originalPitch;

  /// Fine pitch correction in cents (`-99..99`) to apply when playing at [originalPitch].
  final int pitchCorrection;

  /// Loop start point in sample frames relative to the beginning of this sample.
  final int loopStart;

  /// Loop end point in sample frames relative to the beginning of this sample.
  final int loopEnd;

  /// Total number of sample frames in the audio waveform.
  final int sampleCount;

  /// Starting byte offset of the sample payload in the underlying SoundFont stream.
  final int byteOffset;

  /// Byte length of the sample payload in the underlying SoundFont stream.
  final int byteLength;

  /// Audio compression or PCM encoding format of the sample data.
  final SampleCompression compression;

  /// Relative file path to the external audio file (used by SFZ instruments).
  final String? samplePath;

  /// Number of audio channels (`1` for mono, `2` for stereo).
  final int channels;

  /// Raw SoundFont 2 `sfSampleType` bitmask (`1` = mono, `2` = right, `4` = left, `8` = linked).
  final int sampleType;

  /// Index of the linked partner sample header when [isLeft], [isRight], or [isLinked] is `true`.
  final int sampleLink;

  /// Creates a [SampleInfo] describing a SoundFont audio sample.
  const SampleInfo({
    required this.id,
    required this.name,
    this.sampleRate = 44100,
    this.originalPitch = 60,
    this.pitchCorrection = 0,
    this.loopStart = 0,
    this.loopEnd = 0,
    this.sampleCount = 0,
    this.byteOffset = 0,
    this.byteLength = 0,
    this.compression = SampleCompression.pcm16,
    this.samplePath,
    this.channels = 1,
    this.sampleType = 1,
    this.sampleLink = 0,
  });

  /// Exclusive end byte offset (`byteOffset + byteLength`) in the source stream.
  int get byteEnd => byteOffset + byteLength;

  /// Whether this sample is tagged as mono in SoundFont 2 (`sampleType` `1` or `0x8001`).
  bool get isMono =>
      (sampleType & 0x07) == 1 || channels == 1 && !isLeft && !isRight;

  /// Whether this sample is tagged as a right stereo channel in SoundFont 2 (`sampleType` `2` or `0x8002`).
  bool get isRight => (sampleType & 0x07) == 2;

  /// Whether this sample is tagged as a left stereo channel in SoundFont 2 (`sampleType` `4` or `0x8004`).
  bool get isLeft => (sampleType & 0x07) == 4;

  /// Whether this sample is linked to another sample in SoundFont 2 (`sampleType` `8` or `0x8008`).
  bool get isLinked => (sampleType & 0x08) != 0;

  @override
  String toString() {
    return 'SampleInfo(id: $id, name: "$name", sampleRate: $sampleRate, '
        'originalPitch: $originalPitch, compression: $compression, '
        'byteOffset: $byteOffset, byteLength: $byteLength, samplePath: $samplePath, '
        'sampleType: $sampleType, sampleLink: $sampleLink)';
  }
}
