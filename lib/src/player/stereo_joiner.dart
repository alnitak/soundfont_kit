import 'dart:math' as math;
import 'dart:typed_data';

import '../models/sample_info.dart';
import '../soundfont_file.dart';

/// Helper to identify and join stereo 16-bit PCM sample pairs.
class StereoJoiner {
  const StereoJoiner._();

  /// Checks if [sample] has a paired opposite-channel sample.
  static bool isStereoCandidate(SampleInfo sample) {
    return sample.isLeft || sample.isRight;
  }

  /// Finds the paired stereo [SampleInfo] for a given [sample] in [soundFont].
  static SampleInfo? findLinkedSample(
    SoundFontFile soundFont,
    SampleInfo sample,
  ) {
    if (!isStereoCandidate(sample)) return null;

    // Check direct sampleLink index
    if (sample.sampleLink >= 0 &&
        sample.sampleLink < soundFont.samples.length) {
      final linked = soundFont.samples[sample.sampleLink];
      if (linked.id != sample.id &&
          ((sample.isLeft && linked.isRight) ||
              (sample.isRight && linked.isLeft))) {
        return linked;
      }
    }

    // Name-based pairing fallback (e.g., Piano_L <-> Piano_R)
    final baseName = _stripChannelSuffix(sample.name);
    for (final other in soundFont.samples) {
      if (other.id == sample.id) continue;
      if (sample.isLeft && other.isRight || sample.isRight && other.isLeft) {
        if (_stripChannelSuffix(other.name) == baseName) {
          return other;
        }
      }
    }

    return null;
  }

  static String _stripChannelSuffix(String name) {
    var clean = name.trim();
    if (clean.endsWith('-L') ||
        clean.endsWith('-R') ||
        clean.endsWith('_L') ||
        clean.endsWith('_R') ||
        clean.endsWith('.L') ||
        clean.endsWith('.R')) {
      clean = clean.substring(0, clean.length - 2);
    } else if (clean.endsWith(' L') || clean.endsWith(' R')) {
      clean = clean.substring(0, clean.length - 2);
    } else if (clean.endsWith('(L)') || clean.endsWith('(R)')) {
      clean = clean.substring(0, clean.length - 3);
    }
    return clean.trim().toLowerCase();
  }

  /// Interleaves two 16-bit PCM mono byte lists into a single stereo 16-bit PCM byte list.
  static Uint8List interleavePcm16({
    required Uint8List leftBytes,
    required Uint8List rightBytes,
  }) {
    final leftFrames = leftBytes.length ~/ 2;
    final rightFrames = rightBytes.length ~/ 2;
    final frameCount = math.max(leftFrames, rightFrames);

    final interleaved = Uint8List(frameCount * 4);

    final leftData = ByteData.sublistView(leftBytes);
    final rightData = ByteData.sublistView(rightBytes);
    final outData = ByteData.sublistView(interleaved);

    for (int i = 0; i < frameCount; i++) {
      final leftSample = i < leftFrames
          ? leftData.getInt16(i * 2, Endian.little)
          : 0;
      final rightSample = i < rightFrames
          ? rightData.getInt16(i * 2, Endian.little)
          : 0;

      outData.setInt16(i * 4, leftSample, Endian.little);
      outData.setInt16(i * 4 + 2, rightSample, Endian.little);
    }

    return interleaved;
  }
}
