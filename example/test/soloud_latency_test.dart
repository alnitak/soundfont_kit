import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
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

  final ticPath = p.join(Directory.current.path, 'assets', 'tic-1.wav');
  final sfPath = p.join(Directory.current.path, 'assets', 'RatAttack.sf2');

  group('SoLoud PCM Capture Latency Tests with tic-1.wav', () {
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

    test('Captures PCM mixer output and verifies tic-1.wav onset latency', () async {
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

      expect(SoLoud.instance.isInitialized, isTrue);
      expect(
        File(ticPath).existsSync(),
        isTrue,
        reason: 'tic-1.wav must exist at $ticPath',
      );

      final sound = await SoLoud.instance.loadFile(ticPath);
      expect(sound, isNotNull);

      // Start capturing raw PCM 32-bit float output
      final capturedFloats = <double>[];
      final streamSubscription = SoLoud.instance
          .startMixerOutputStream(
            format: MixerOutputFormat.pcmF32le,
            sampleRate: sampleRate,
            channels: 2,
            notificationThresholdBytes: 256 * 4 * 2, // 256 stereo frames
          )
          .listen((uint8Data) {
            final floatList = Float32List.sublistView(uint8Data);
            capturedFloats.addAll(floatList);
          });

      // Let the engine spin up and record baseline silence for ~100 ms
      await Future.delayed(const Duration(milliseconds: 100));

      final framesBeforePlay = capturedFloats.length ~/ 2;
      final playTimestamp = DateTime.now();

      // Trigger the tic sound with playScheduled at the playhead
      final handle = SoLoud.instance.playScheduled(
        sound,
        SoLoud.instance.getPlayheadTime(),
      );
      expect(handle.id != 0, isTrue);

      // Collect audio for 300 ms after play
      await Future.delayed(const Duration(milliseconds: 300));

      SoLoud.instance.stopMixerOutputStream();
      await streamSubscription.cancel();

      // Analyze PCM frames to locate the tic onset (threshold amplitude > 0.05)
      final totalStereoFrames = capturedFloats.length ~/ 2;
      int? audibleFrameIndex;
      double peakAmplitude = 0.0;

      for (int f = framesBeforePlay; f < totalStereoFrames; f++) {
        final left = capturedFloats[f * 2].abs();
        final right = capturedFloats[f * 2 + 1].abs();
        final maxAmp = left > right ? left : right;
        if (maxAmp > peakAmplitude) {
          peakAmplitude = maxAmp;
        }
        if (maxAmp > 0.05 && audibleFrameIndex == null) {
          audibleFrameIndex = f;
        }
      }

      print('=== Mixer Output Capture Results ===');
      print(
        'Total captured frames: $totalStereoFrames (${(totalStereoFrames / sampleRate * 1000).toStringAsFixed(1)} ms)',
      );
      print(
        'Frames before play() call: $framesBeforePlay (${(framesBeforePlay / sampleRate * 1000).toStringAsFixed(1)} ms)',
      );
      print('Peak amplitude detected: ${peakAmplitude.toStringAsFixed(3)}');

      expect(
        audibleFrameIndex,
        isNotNull,
        reason: 'The tic sound must be audible in the captured output',
      );

      final onsetFramesAfterPlay = audibleFrameIndex! - framesBeforePlay;
      final onsetLatencyMs = (onsetFramesAfterPlay / sampleRate) * 1000.0;

      print('Audible onset frame index: $audibleFrameIndex');
      print(
        'Onset delay after play(): $onsetFramesAfterPlay frames (${onsetLatencyMs.toStringAsFixed(2)} ms)',
      );

      // With bufferSize=8192, legacy playback would have >= 8192 frames (>= 185 ms) latency.
      // With render-ahead retroactive re-mixing, the onset should appear in near-device-period latency (< 30 ms).
      print('Acoustic latency result: ${onsetLatencyMs.toStringAsFixed(2)} ms');

      await SoLoud.instance.disposeSource(sound);
    });

    test(
      'Captures PCM mixer output and verifies SoundFont preset note onset latency',
      () async {
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

        expect(File(sfPath).existsSync(), isTrue);
        final sf = await SoundFontFile.fromFile(sfPath);
        final player = sf.createPlayer();

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

        // Let the engine spin up and record baseline silence
        await Future.delayed(const Duration(milliseconds: 100));

        final framesBeforePlay = capturedFloats.length ~/ 2;

        // Play SoundFont note
        final voice = await player.playPreset(
          sf.presets.first,
          key: 60,
          velocity: 100,
        );
        expect(voice.handles, isNotEmpty);

        // Collect audio for 300 ms
        await Future.delayed(const Duration(milliseconds: 300));

        SoLoud.instance.stopMixerOutputStream();
        await streamSubscription.cancel();

        final totalStereoFrames = capturedFloats.length ~/ 2;
        int? audibleFrameIndex;
        double peakAmplitude = 0.0;

        for (int f = framesBeforePlay; f < totalStereoFrames; f++) {
          final left = capturedFloats[f * 2].abs();
          final right = capturedFloats[f * 2 + 1].abs();
          final maxAmp = left > right ? left : right;
          if (maxAmp > peakAmplitude) {
            peakAmplitude = maxAmp;
          }
          if (maxAmp > 0.05 && audibleFrameIndex == null) {
            audibleFrameIndex = f;
          }
        }

        print('=== SoundFont Preset PCM Capture Results ===');
        print('Frames before playPreset(): $framesBeforePlay');
        print('Peak amplitude detected: ${peakAmplitude.toStringAsFixed(3)}');

        expect(
          audibleFrameIndex,
          isNotNull,
          reason: 'SoundFont note must be audible in the output',
        );

        final onsetFramesAfterPlay = audibleFrameIndex! - framesBeforePlay;
        final onsetLatencyMs = (onsetFramesAfterPlay / sampleRate) * 1000.0;

        print(
          'SoundFont Note onset delay: $onsetFramesAfterPlay frames (${onsetLatencyMs.toStringAsFixed(2)} ms)',
        );

        await player.dispose();
      },
    );

    test(
      'Captures PCM mixer output for preloaded SoundFont preset and rapid note triggers',
      () async {
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

        // Preload the preset upfront (user choice / explicit preload)
        await player.preloadPreset(sf.presets.first);

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

        await Future.delayed(const Duration(milliseconds: 100));

        final framesBeforeNote1 = capturedFloats.length ~/ 2;
        final v1 = await player.playPreset(
          sf.presets.first,
          key: 60,
          velocity: 100,
        );
        expect(v1.handles, isNotEmpty);

        // Play note 64 after 50 ms
        await Future.delayed(const Duration(milliseconds: 50));
        final framesBeforeNote2 = capturedFloats.length ~/ 2;
        final v2 = await player.playPreset(
          sf.presets.first,
          key: 64,
          velocity: 100,
        );
        expect(v2.handles, isNotEmpty);

        // Collect audio for 200 ms
        await Future.delayed(const Duration(milliseconds: 200));

        SoLoud.instance.stopMixerOutputStream();
        await streamSubscription.cancel();

        final totalFrames = capturedFloats.length ~/ 2;
        int? onset1;
        int? onset2;

        for (int f = framesBeforeNote1; f < totalFrames; f++) {
          final maxAmp = capturedFloats[f * 2].abs();
          if (maxAmp > 0.05 && onset1 == null) {
            onset1 = f;
          }
        }

        for (int f = framesBeforeNote2; f < totalFrames; f++) {
          final maxAmp = capturedFloats[f * 2].abs();
          if (maxAmp > 0.05 && onset2 == null) {
            onset2 = f;
          }
        }

        print('=== Preloaded SoundFont Preset Note Latency Results ===');
        if (onset1 != null) {
          final delay1 = ((onset1 - framesBeforeNote1) / sampleRate) * 1000.0;
          print(
            'Note 1 (C4) onset delay: ${onset1 - framesBeforeNote1} frames (${delay1.toStringAsFixed(2)} ms)',
          );
        }
        if (onset2 != null) {
          final delay2 = ((onset2 - framesBeforeNote2) / sampleRate) * 1000.0;
          print(
            'Note 2 (E4) onset delay: ${onset2 - framesBeforeNote2} frames (${delay2.toStringAsFixed(2)} ms)',
          );
        }

        await player.dispose();
      },
    );
  });
}
