import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundfont_kit/soundfont_kit.dart';

void main() {
  group('StereoJoiner tests', () {
    test('Interleaves two 16-bit mono PCM buffers into stereo PCM', () {
      // Left channel: [1000, 2000]
      final leftBytes = Uint8List(4);
      final leftData = ByteData.sublistView(leftBytes);
      leftData.setInt16(0, 1000, Endian.little);
      leftData.setInt16(2, 2000, Endian.little);

      // Right channel: [3000, 4000]
      final rightBytes = Uint8List(4);
      final rightData = ByteData.sublistView(rightBytes);
      rightData.setInt16(0, 3000, Endian.little);
      rightData.setInt16(2, 4000, Endian.little);

      final stereoBytes = StereoJoiner.interleavePcm16(
        leftBytes: leftBytes,
        rightBytes: rightBytes,
      );

      expect(stereoBytes.length, equals(8));

      final outData = ByteData.sublistView(stereoBytes);
      // Frame 0: Left=1000, Right=3000
      expect(outData.getInt16(0, Endian.little), equals(1000));
      expect(outData.getInt16(2, Endian.little), equals(3000));
      // Frame 1: Left=2000, Right=4000
      expect(outData.getInt16(4, Endian.little), equals(2000));
      expect(outData.getInt16(6, Endian.little), equals(4000));
    });

    test('Identifies stereo candidate samples correctly', () {
      const monoSample = SampleInfo(id: 0, name: 'Mono', sampleType: 1);
      const rightSample = SampleInfo(id: 1, name: 'Right', sampleType: 2);
      const leftSample = SampleInfo(id: 2, name: 'Left', sampleType: 4);

      expect(StereoJoiner.isStereoCandidate(monoSample), isFalse);
      expect(StereoJoiner.isStereoCandidate(rightSample), isTrue);
      expect(StereoJoiner.isStereoCandidate(leftSample), isTrue);
    });
  });
}
