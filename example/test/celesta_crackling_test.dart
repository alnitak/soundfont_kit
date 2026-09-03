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

  final sfPath = p.join(
    Directory.current.path,
    'assets',
    'Celesta_minimal.sf3',
  );

  group('Celesta_minimal.sf3 Crackling Investigation', () {
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

    test(
      'Plays rapid notes on Celesta_minimal.sf3 and analyzes frame deltas for clicks',
      () async {
        const sampleRate = 44100;
        await SoLoud.instance.init(sampleRate: sampleRate, bufferSize: 1024);

        final sf = await SoundFontFile.fromFile(sfPath);
        final player = sf.createPlayer();
        final preset = sf.presets.first;

        final capturedFloats = <double>[];
        final streamSubscription = SoLoud.instance
            .startMixerOutputStream(
              format: MixerOutputFormat.pcmF32le,
              sampleRate: sampleRate,
              channels: 2,
              notificationThresholdBytes: 256 * 4 * 2,
            )
            .listen((uint8Data) {
              final floatList = Float32List.sublistView(uint8Data);
              capturedFloats.addAll(floatList);
            });

        await Future.delayed(const Duration(milliseconds: 50));

        final notes = [60, 62, 64, 65, 67, 69, 71, 72];
        for (final note in notes) {
          final startIdx = capturedFloats.length ~/ 2;
          final voice = await player.playPreset(
            preset,
            key: note,
            velocity: 100,
          );
          await Future.delayed(const Duration(milliseconds: 100));
          await player.noteOff(note);
          await Future.delayed(const Duration(milliseconds: 100));
          final endIdx = capturedFloats.length ~/ 2;

          double peak = 0.0;
          for (int i = startIdx; i < endIdx; i++) {
            final ampL = capturedFloats[i * 2].abs();
            final ampR = capturedFloats[i * 2 + 1].abs();
            if (ampL > peak) peak = ampL;
            if (ampR > peak) peak = ampR;
          }
          print(
            'Note $note: peak amplitude = ${peak.toStringAsFixed(4)} (handles: ${voice.handles.length})',
          );
        }

        SoLoud.instance.stopMixerOutputStream();
        await streamSubscription.cancel();
        await player.dispose();
      },
    );
  });
}
