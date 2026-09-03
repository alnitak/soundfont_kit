import 'soundfont_format.dart';

/// Metadata for a sample stored or referenced by a SoundFont.
class SampleInfo {
  final int id;
  final String name;
  final int sampleRate;
  final int originalPitch;
  final int pitchCorrection;
  final int loopStart;
  final int loopEnd;
  final int sampleCount;
  final int byteOffset;
  final int byteLength;
  final SampleCompression compression;
  final String? samplePath;
  final int channels;
  final int sampleType;
  final int sampleLink;

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

  /// End byte location in source stream
  int get byteEnd => byteOffset + byteLength;

  /// Whether this sample is tagged as mono in SoundFont 2 (sampleType 1 or 0x8001)
  bool get isMono =>
      (sampleType & 0x07) == 1 || channels == 1 && !isLeft && !isRight;

  /// Whether this sample is tagged as right channel in SoundFont 2 (sampleType 2 or 0x8002)
  bool get isRight => (sampleType & 0x07) == 2;

  /// Whether this sample is tagged as left channel in SoundFont 2 (sampleType 4 or 0x8004)
  bool get isLeft => (sampleType & 0x07) == 4;

  /// Whether this sample is linked to another sample in SoundFont 2 (sampleType 8 or 0x8008)
  bool get isLinked => (sampleType & 0x08) != 0;

  @override
  String toString() {
    return 'SampleInfo(id: $id, name: "$name", sampleRate: $sampleRate, '
        'originalPitch: $originalPitch, compression: $compression, '
        'byteOffset: $byteOffset, byteLength: $byteLength, samplePath: $samplePath, '
        'sampleType: $sampleType, sampleLink: $sampleLink)';
  }
}
