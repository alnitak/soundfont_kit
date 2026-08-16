import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:soundfont_reader/soundfont_reader.dart';

void main() {
  final assetDir = p.join(Directory.current.path, 'example', 'assets');
  final sf2Path = p.join(assetDir, 'Celesta (minimal).sf2');
  final sf3Path = p.join(assetDir, 'Celesta (minimal).sf3');
  final sfzZipPath = p.join(assetDir, 'Celesta (converted).sfz+flac.zip');

  group('SoundFontReader SF2 tests', () {
    test('Loads and parses SF2 file correctly', () async {
      final sf = await SoundFontFile.fromFile(sf2Path);

      expect(sf.format, equals(SoundFontFormat.sf2));
      expect(sf.presets, isNotEmpty);
      expect(sf.instruments, isNotEmpty);
      expect(sf.samples, isNotEmpty);

      final preset = sf.presets.first;
      expect(preset.name, isNotEmpty);

      final sample = sf.samples.first;
      expect(sample.byteLength, greaterThan(0));
      expect(sample.channels, equals(1));

      final sampleBytes = await sf.getSampleBytes(sample);
      expect(sampleBytes.length, equals(sample.byteLength));
    });
  });

  group('SoundFontReader SF3 tests', () {
    test('Loads and parses SF3 file correctly and verifies OGG stream offsets', () async {
      final sf = await SoundFontFile.fromFile(sf3Path);

      expect(sf.format, equals(SoundFontFormat.sf3));
      expect(sf.presets, isNotEmpty);
      expect(sf.instruments, isNotEmpty);
      expect(sf.samples, isNotEmpty);

      // Verify all samples have OGG compression and start with 'OggS' magic header
      for (final sample in sf.samples) {
        expect(sample.compression, equals(SampleCompression.ogg));
        expect(sample.byteLength, greaterThan(0));

        final sampleBytes = await sf.getSampleBytes(sample);
        expect(sampleBytes.length, equals(sample.byteLength));

        // Verify OGG header magic 'OggS' (0x4F, 0x67, 0x67, 0x53)
        expect(
          sampleBytes.sublist(0, 4),
          equals([0x4F, 0x67, 0x67, 0x53]),
          reason: 'Sample "${sample.name}" does not start with OggS magic header',
        );
      }
    });
  });

  group('SoundFontReader SFZ Zip tests', () {
    test('Loads and parses zipped SFZ archive correctly', () async {
      final sf = await SoundFontFile.fromFile(sfzZipPath);

      expect(sf.format, equals(SoundFontFormat.sfz));
      expect(sf.presets, isNotEmpty);
      expect(sf.instruments.first.zones, isNotEmpty);
      final zoneF6 = sf.instruments.first.zones.firstWhere((z) => z.opcodes['key'] == 'F6');
      expect(zoneF6.keyRangeMin, equals(89));
      expect(zoneF6.keyRangeMax, equals(89));
      expect(zoneF6.rootKey, equals(89));

      final firstSample = sf.samples.first;
      expect(firstSample.samplePath, isNotNull);
      expect(firstSample.compression, equals(SampleCompression.flac));

      final sampleBytes = await sf.getSampleBytes(firstSample);
      expect(sampleBytes, isNotEmpty);

      // Verify FLAC magic header 'fLaC'
      expect(sampleBytes.sublist(0, 4), equals([0x66, 0x4C, 0x61, 0x43]));
    });
  });
}
