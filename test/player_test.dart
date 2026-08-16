import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:soundfont_reader/soundfont_reader.dart';

void main() {
  final assetDir = p.join(Directory.current.path, 'example', 'assets');
  final sf2Path = p.join(assetDir, 'Celesta (minimal).sf2');

  group('VoiceCalculator tests', () {
    test('Calculates pitch ratio accurately', () {
      const sample = SampleInfo(
        id: 0,
        name: 'Test',
        originalPitch: 60,
        pitchCorrection: 0,
      );

      // Same key as root: ratio 1.0
      final ratioSame = VoiceCalculator.calculatePitchRatio(
        key: 60,
        sample: sample,
      );
      expect(ratioSame, closeTo(1.0, 0.001));

      // One octave up (key 72 vs root 60): ratio 2.0
      final ratioOctaveUp = VoiceCalculator.calculatePitchRatio(
        key: 72,
        sample: sample,
      );
      expect(ratioOctaveUp, closeTo(2.0, 0.001));

      // One octave down (key 48 vs root 60): ratio 0.5
      final ratioOctaveDown = VoiceCalculator.calculatePitchRatio(
        key: 48,
        sample: sample,
      );
      expect(ratioOctaveDown, closeTo(0.5, 0.001));

      // Zone root key override (zone rootKey = 69, key = 69 -> ratio 1.0)
      const zone = Zone(rootKey: 69);
      final ratioZoneRoot = VoiceCalculator.calculatePitchRatio(
        key: 69,
        sample: sample,
        zone: zone,
      );
      expect(ratioZoneRoot, closeTo(1.0, 0.001));
    });

    test('Calculates volume and attenuation correctly', () {
      // Full velocity (127), 0 attenuation -> volume = 1.0
      final volFull = VoiceCalculator.calculateVolume(velocity: 127);
      expect(volFull, closeTo(1.0, 0.001));

      // Half velocity (64)
      final volHalf = VoiceCalculator.calculateVolume(velocity: 64);
      expect(volHalf, closeTo((64 / 127) * (64 / 127), 0.01));

      // Attenuation of 6 dB should halve amplitude (~0.5 linear gain)
      const zoneAtten = Zone(attenuation: 6.02);
      final volAtten = VoiceCalculator.calculateVolume(
        velocity: 127,
        zone: zoneAtten,
      );
      expect(volAtten, closeTo(0.5, 0.02));
    });

    test('Calculates pan positions correctly', () {
      const leftSample = SampleInfo(id: 0, name: 'L', sampleType: 4);
      const rightSample = SampleInfo(id: 1, name: 'R', sampleType: 2);
      const monoSample = SampleInfo(id: 2, name: 'M', sampleType: 1);

      expect(VoiceCalculator.calculatePan(sample: leftSample), equals(-1.0));
      expect(VoiceCalculator.calculatePan(sample: rightSample), equals(1.0));
      expect(VoiceCalculator.calculatePan(sample: monoSample), equals(0.0));

      const panZone = Zone(pan: 0.5);
      expect(VoiceCalculator.calculatePan(zone: panZone), equals(0.5));
    });

    test('Calculates loop regions correctly', () {
      const sample = SampleInfo(
        id: 0,
        name: 'Looping',
        sampleRate: 44100,
        loopStart: 4410,
        loopEnd: 8820,
      );

      final loopInfo = VoiceCalculator.calculateLoopRegion(sample: sample);
      expect(loopInfo.isLooping, isTrue);
      expect(loopInfo.loopStart, equals(const Duration(milliseconds: 100)));
      expect(loopInfo.loopEnd, equals(const Duration(milliseconds: 200)));
    });
  });

  group('SoundFontPlayer creation tests', () {
    test('SoundFontFile.createPlayer returns a functional player instance', () async {
      final sf = await SoundFontFile.fromFile(sf2Path);
      final player = sf.createPlayer(
        options: const SoundFontPlayerOptions(
          useScheduledPlayback: true,
        ),
      );

      expect(player.soundFont, equals(sf));
      expect(player.options.joinStereoChannels, isTrue);
      expect(player.options.cacheAudioSources, isTrue);
      expect(player.options.useScheduledPlayback, isTrue);

      final voice = SoundFontVoice(
        key: 60,
        velocity: 100,
        handles: [],
        releaseDuration: const Duration(milliseconds: 200),
      );
      expect(voice.isReleased, isFalse);
      voice.stopScheduled(Duration.zero);
      expect(voice.isReleased, isTrue);
    });
  });
}
