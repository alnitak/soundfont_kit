import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
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

  test('Rapid note changing crackle analysis', () async {
    const sampleRate = 44100;
    await SoLoud.instance.init(
      sampleRate: sampleRate,
      bufferSize: 1024,
      devicePeriodFrames: 128,
      renderAheadFrames: 1024,
    );

    final sfPath = p.join(Directory.current.path, 'example', 'assets', 'Celesta_minimal.sf3');
    final sf = await SoundFontFile.fromFile(sfPath);
    final player = sf.createPlayer(options: const SoundFontPlayerOptions(joinStereoChannels: true));
    final preset = sf.presets.first;

    final capturedFloats = <double>[];
    final sub = SoLoud.instance.startMixerOutputStream(
      format: MixerOutputFormat.pcmF32le,
      sampleRate: sampleRate,
      channels: 2,
      notificationThresholdBytes: 128 * 4 * 2,
    ).listen((uint8) {
      capturedFloats.addAll(Float32List.sublistView(uint8));
    });

    await Future.delayed(const Duration(milliseconds: 50));

    // Rapidly change notes like a user sliding finger across keys: 50, 51, 52, 53, 54, 55
    final notes = [50, 51, 52, 53, 54, 55, 60, 61, 62, 63];
    int prevNote = -1;

    for (final note in notes) {
      if (prevNote >= 0) {
        player.noteOff(prevNote);
      }
      await player.playPreset(preset, key: note, velocity: 100);
      prevNote = note;
      // 30ms between rapid key glides
      await Future.delayed(const Duration(milliseconds: 30));
    }

    if (prevNote >= 0) {
      await player.noteOff(prevNote);
    }

    await Future.delayed(const Duration(milliseconds: 300));

    SoLoud.instance.stopMixerOutputStream();
    await sub.cancel();

    // Check maximum sample-to-sample delta (instant jump / click)
    double maxJump = 0.0;
    int maxJumpFrame = 0;
    final totalFrames = capturedFloats.length ~/ 2;
    int clickCount = 0;

    for (int i = 1; i < totalFrames; i++) {
      final dL = (capturedFloats[i * 2] - capturedFloats[(i - 1) * 2]).abs();
      final dR = (capturedFloats[i * 2 + 1] - capturedFloats[(i - 1) * 2 + 1]).abs();
      final d = dL > dR ? dL : dR;

      if (d > maxJump) {
        maxJump = d;
        maxJumpFrame = i;
      }
      if (d > 0.05) {
        clickCount++;
        print('Click at frame $i (${(i / sampleRate * 1000).toStringAsFixed(1)}ms): delta = ${d.toStringAsFixed(4)}');
      }
    }

    print('\nTotal Frames: $totalFrames, Max Jump: ${maxJump.toStringAsFixed(5)} at frame $maxJumpFrame, Clicks (>0.05): $clickCount\n');

    await player.dispose();
    SoLoud.instance.deinit();
  });
}
