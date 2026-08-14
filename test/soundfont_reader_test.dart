import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:soundfont_reader/soundfont_reader.dart';

void main() {
  final assetDir = p.join(Directory.current.path, 'example', 'assets');
  final sf2Path = p.join(assetDir, 'Rhodes - minimal (from Dream Piano).sf2');
  final sf3Path = p.join(assetDir, 'Rhodes - minimal (from Dream Piano).sf3');
  final sfzZipPath = p.join(assetDir, 'Dream Piano (converted).sfz+flac.zip');

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

      final sampleBytes = await sf.getSampleBytes(sample);
      expect(sampleBytes.length, equals(sample.byteLength));
    });
  });

  group('SoundFontReader SF3 tests', () {
    test('Loads and parses SF3 file correctly', () async {
      final sf = await SoundFontFile.fromFile(sf3Path);

      expect(sf.format, equals(SoundFontFormat.sf3));
      expect(sf.presets, isNotEmpty);
      expect(sf.instruments, isNotEmpty);
      expect(sf.samples, isNotEmpty);

      // Verify that sample compression is OGG
      final oggSample = sf.samples.firstWhere(
        (s) => s.compression == SampleCompression.ogg,
        orElse: () => sf.samples.first,
      );

      expect(oggSample.compression, equals(SampleCompression.ogg));
      expect(oggSample.byteLength, greaterThan(0));

      final sampleBytes = await sf.getSampleBytes(oggSample);
      expect(sampleBytes.length, equals(oggSample.byteLength));

      // Verify OGG header magic 'OggS'
      expect(sampleBytes.sublist(0, 4), equals([0x4F, 0x67, 0x67, 0x53]));
    });
  });

  group('SoundFontReader SFZ Zip tests', () {
    test('Loads and parses zipped SFZ archive correctly', () async {
      final sf = await SoundFontFile.fromFile(sfzZipPath);

      expect(sf.format, equals(SoundFontFormat.sfz));
      expect(sf.presets, isNotEmpty);
      expect(sf.instruments, isNotEmpty);
      expect(sf.samples, isNotEmpty);

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
