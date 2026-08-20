import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundfont_kit/soundfont_kit.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (methodCall) async {
      return Directory.systemTemp.path;
    },
  );

  final sfPath = p.join(Directory.current.path, 'assets', 'Celesta_minimal.sf3');

  group('Celesta_minimal.sf3 OGG Playback and Noise Tests', () {
    setUp(() async {
      if (SoLoud.instance.isInitialized) {
        SoLoud.instance.stopMixerOutputStream();
        SoLoud.instance.deinit();
      }
    });

    tearDown(() async {
      if (SoLoud.instance.isInitialized) {
        SoLoud.instance.stopMixerOutputStream();
        SoLoud.instance.deinit();
      }
    });

    test('Plays Celesta_minimal.sf3 notes and checks for discontinuities or noise', () async {
      const sampleRate = 44100;
      await SoLoud.instance.init(
        sampleRate: sampleRate,
        bufferSize: 1024,
      );

      final sf = await SoundFontFile.fromFile(sfPath);
      print('SoundFont name: ${sf.name}, format: ${sf.format}');
      print('Presets count: ${sf.presets.length}, samples count: ${sf.samples.length}');
      for (int i = 0; i < sf.samples.length && i < 5; i++) {
        final s = sf.samples[i];
        print('Sample $i: name=${s.name}, rate=${s.sampleRate}, comp=${s.compression}, channels=${s.channels}');
      }

      final player = sf.createPlayer();
      final preset = sf.presets.first;

      final capturedFloats = <double>[];
      final streamSubscription = SoLoud.instance.startMixerOutputStream(
        format: MixerOutputFormat.pcmF32le,
        sampleRate: sampleRate,
        channels: 2,
        notificationThresholdBytes: 256 * 4 * 2,
      ).listen((uint8Data) {
        final floatList = Float32List.sublistView(uint8Data);
        capturedFloats.addAll(floatList);
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final notes = [60, 62, 64, 65, 67, 69, 71, 72];
      for (final note in notes) {
        print('\n--- Playing Note $note ---');
        final matchingPresetZones = preset.zones.where((pz) => pz.matches(note, 100)).toList();
        print('Matching preset zones: ${matchingPresetZones.length}');
        for (final pz in matchingPresetZones) {
          final inst = (pz.instrumentID != null && pz.instrumentID! < sf.instruments.length)
              ? sf.instruments[pz.instrumentID!]
              : null;
          print('PresetZone: instID=${pz.instrumentID}, instName=${inst?.name}');
          if (inst != null) {
            final matchingInstZones = inst.zones.where((iz) => iz.matches(note, 100)).toList();
            print('  Matching inst zones: ${matchingInstZones.length}');
            for (final iz in matchingInstZones) {
              final sample = iz.sampleRef ??
                  (iz.sampleID != null && iz.sampleID! < sf.samples.length
                      ? sf.samples[iz.sampleID!]
                      : null);
              print('  InstZone: sample=${sample?.name}, rate=${sample?.sampleRate}, origPitch=${sample?.originalPitch}, keyRange=[${iz.keyRangeMin}, ${iz.keyRangeMax}], pan=${iz.pan}, volEnvRelease=${iz.volEnvRelease}, presetVolEnvRelease=${pz.volEnvRelease}');
            }
          }
        }
        final framesBefore = capturedFloats.length ~/ 2;
        final voice = await player.playPreset(preset, key: note, velocity: 100);
        await Future.delayed(const Duration(milliseconds: 150));
        await player.noteOff(note);
        await Future.delayed(const Duration(milliseconds: 150));
        final framesAfter = capturedFloats.length ~/ 2;

        // Check for large sudden jumps (clicks/crackles) in the waveform
        double maxDelta = 0.0;
        int deltaIndex = 0;
        for (int f = framesBefore + 1; f < framesAfter; f++) {
          final prevL = capturedFloats[(f - 1) * 2];
          final currL = capturedFloats[f * 2];
          final delta = (currL - prevL).abs();
          if (delta > maxDelta) {
            maxDelta = delta;
            deltaIndex = f - framesBefore;
          }
        }
        print('Note $note: max frame-to-frame delta = $maxDelta at relative frame $deltaIndex');
      }

      SoLoud.instance.stopMixerOutputStream();
      await streamSubscription.cancel();
      await player.dispose();
    });
  });
}
