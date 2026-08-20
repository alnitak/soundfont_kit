import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundfont_kit/soundfont_kit.dart';
import 'package:path/path.dart' as p;

import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (methodCall) async {
      return Directory.systemTemp.path;
    },
  );

  final sfPath = p.join(Directory.current.path, 'assets', 'RatAttack.sf2');

  group('RatAttack.sf2 Real Note Playback Latency Tests', () {
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

    test('Continuously plays notes on RatAttack.sf2 with bufferSize 8192 and measures onset timing', () async {
      const sampleRate = 44100;
      const bufferSize = 8192;
      const devicePeriod = 256;
      const renderAhead = 8192;

      await SoLoud.instance.init(
        sampleRate: sampleRate,
        bufferSize: bufferSize,
        devicePeriodFrames: devicePeriod,
        renderAheadFrames: renderAhead,
      );

      final sf = await SoundFontFile.fromFile(sfPath);
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

      await Future.delayed(const Duration(milliseconds: 100));

      final notesToPlay = [48, 52, 55, 60, 64, 67, 72];
      final noteResults = <String>[];

      for (final note in notesToPlay) {
        final framesBefore = capturedFloats.length ~/ 2;
        print('\n--- Playing Note $note ---');
        final matchingPresetZones = preset.zones.where((pz) => pz.matches(note, 100)).toList();
        print('Matching preset zones count: ${matchingPresetZones.length}');
        for (final pz in matchingPresetZones) {
          final inst = (pz.instrumentID != null && pz.instrumentID! < sf.instruments.length)
              ? sf.instruments[pz.instrumentID!]
              : null;
          print('PresetZone: instID=${pz.instrumentID}, instName=${inst?.name}, sampleID=${pz.sampleID}');
          if (inst != null) {
            final matchingInstZones = inst.zones.where((iz) => iz.matches(note, 100)).toList();
            print('  Matching inst zones count: ${matchingInstZones.length}');
            for (final iz in matchingInstZones) {
              print('  InstZone: sampleID=${iz.sampleID}, sampleRef=${iz.sampleRef?.name}');
            }
          }
        }

        final voice = await player.playPreset(preset, key: note, velocity: 100);
        print('Triggered voice handles: ${voice.handles.length}');

        // Keep note down for 100 ms
        await Future.delayed(const Duration(milliseconds: 100));
        await player.noteOff(note);

        // Wait 50 ms before next note
        await Future.delayed(const Duration(milliseconds: 50));

        final framesAfter = capturedFloats.length ~/ 2;
        int? onsetFrame;
        double peak = 0.0;

        for (int f = framesBefore; f < framesAfter; f++) {
          final amp = capturedFloats[f * 2].abs();
          if (amp > peak) peak = amp;
          if (amp > 0.05 && onsetFrame == null) {
            onsetFrame = f;
          }
        }

        if (onsetFrame != null) {
          final delayFrames = onsetFrame - framesBefore;
          final delayMs = (delayFrames / sampleRate) * 1000.0;
          noteResults.add('Note $note: onset after $delayFrames frames (${delayMs.toStringAsFixed(2)} ms), peak=${peak.toStringAsFixed(2)}');
        } else {
          noteResults.add('Note $note: NO ONSET DETECTED (peak=${peak.toStringAsFixed(2)})');
        }
      }

      SoLoud.instance.stopMixerOutputStream();
      await streamSubscription.cancel();

      print('=== RatAttack.sf2 Continuous Note Sequence Latency Results ===');
      for (final res in noteResults) {
        print(res);
      }

      await player.dispose();
    });
  });
}
