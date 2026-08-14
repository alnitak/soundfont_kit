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
  });

  /// End byte location in source stream
  int get byteEnd => byteOffset + byteLength;

  @override
  String toString() {
    return 'SampleInfo(id: $id, name: "$name", sampleRate: $sampleRate, '
        'originalPitch: $originalPitch, compression: $compression, '
        'byteOffset: $byteOffset, byteLength: $byteLength, samplePath: $samplePath)';
  }
}
