import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundfont_kit/soundfont_kit.dart';

void main() {
  group('VoiceCalculator 6-Stage DAHDSR, Filter & Exclusive Class', () {
    test(
      'calculateVolEnvStages resolves instrument and preset zone fallback stages accurately',
      () {
        const instZone = Zone(
          volEnvDelay: 0.05,
          volEnvAttack: 0.1,
          volEnvHold: 0.2,
          volEnvDecay: 0.5,
          volEnvSustain: 0.06, // 6 dB attenuation in SF2 (60 centibels / 1000)
          volEnvRelease: 0.3,
        );
        const presetZone = Zone(volEnvHold: 0.4);

        final stages = VoiceCalculator.calculateVolEnvStages(
          zone: instZone,
          presetZone: presetZone,
          peakVolume: 0.8,
        );

        expect(stages.delay.inMilliseconds, 50);
        expect(stages.attack.inMilliseconds, 100);
        expect(stages.hold.inMilliseconds, 200);
        expect(stages.decay.inMilliseconds, 500);
        expect(stages.sustainVolume, closeTo(0.8 * 0.501187, 1e-3));
      },
    );

    test(
      'calculateFilterParams activates when cutoff < 18500 Hz or Q > 1.05',
      () {
        const openZone = Zone(
          initialFilterCutoff: 20000.0,
          initialFilterQ: 0.0,
        );
        final openParams = VoiceCalculator.calculateFilterParams(
          zone: openZone,
        );
        expect(openParams.enabled, isFalse);

        const filteredZone = Zone(
          initialFilterCutoff: 1200.0,
          initialFilterQ: 12.0, // 12 dB resonance peak
        );
        final activeParams = VoiceCalculator.calculateFilterParams(
          zone: filteredZone,
        );
        expect(activeParams.enabled, isTrue);
        expect(activeParams.cutoffHz, closeTo(1200.0, 1e-3));
        expect(activeParams.resonanceQ, greaterThan(1.3));
      },
    );

    test('resolveExclusiveClass extracts group and offByGroup', () {
      const hiHatClosed = Zone(exclusiveClass: 42);
      const hiHatOpen = Zone(exclusiveClass: 42, offByGroup: 42);

      final closedExc = VoiceCalculator.resolveExclusiveClass(
        zone: hiHatClosed,
      );
      expect(closedExc.exclusiveClass, 42);
      expect(closedExc.offByGroup, 42);

      final openExc = VoiceCalculator.resolveExclusiveClass(zone: hiHatOpen);
      expect(openExc.exclusiveClass, 42);
      expect(openExc.offByGroup, 42);
    });
  });

  group('SoundFontFilterRack & SoundFontSynthMode', () {
    test('SoundFontFilterType custom slots map 0..7 accurately', () {
      for (var i = 0; i < 8; i++) {
        final type = SoundFontFilterType.fromCustomSlotIndex(i);
        expect(type.isCustomSlot, isTrue);
        expect(type.customSlotIndex, i);
      }
      expect(SoundFontFilterType.compressor.isCustomSlot, isFalse);
      expect(SoundFontFilterType.limiter.isCustomSlot, isFalse);
      expect(SoundFontFilterType.parametricEq.isCustomSlot, isFalse);
    });

    test(
      'SoundFontPlayerOptions defaults to soloudVoices with per-voice filter enabled',
      () {
        const opts = SoundFontPlayerOptions();
        expect(opts.synthMode, SoundFontSynthMode.soloudVoices);
        expect(opts.enablePerVoiceFilter, isTrue);
        expect(opts.defaultBusId, 0);
      },
    );

    test('MidiChannelState tracks reverbSend, chorusSend, and modulation', () {
      final ch = MidiChannelState(channel: 0);
      ch.applyModulation(0.5);
      ch.applyReverbSend(0.4);
      ch.applyChorusSend(0.3);

      expect(ch.modulation, closeTo(0.5, 1e-6));
      expect(ch.reverbSend, closeTo(0.4, 1e-6));
      expect(ch.chorusSend, closeTo(0.3, 1e-6));

      ch.resetControllers();
      expect(ch.modulation, 0.0);
      expect(ch.reverbSend, 0.0);
      expect(ch.chorusSend, 0.0);
    });

    test(
      'RealtimeIsolateSynth produces audible output and recovers after stopMixerOutput',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (MethodCall methodCall) async => Directory.systemTemp.path,
            );
        await SoLoud.instance.init(
          bufferSize: 1024,
          devicePeriodFrames: 128,
          renderAheadFrames: 1024,
        );
        double maxAbsSample = 0.0;
        final sub = SoLoud.instance
            .startMixerOutputStream(
              format: MixerOutputFormat.pcmF32le,
              chunkPCMFrames: 2048,
            )
            .listen((chunk) {
              final floats = chunk.buffer.asFloat32List(
                chunk.offsetInBytes,
                chunk.lengthInBytes ~/ 4,
              );
              for (final s in floats) {
                if (s.abs() > maxAbsSample) maxAbsSample = s.abs();
              }
            });

        final sf = await SoundFontFile.fromFile('example/assets/RatAttack.sf2');
        final player = sf.createPlayer(
          options: const SoundFontPlayerOptions(
            synthMode: SoundFontSynthMode.realtimeIsolateSynth,
          ),
        );
        await player.ensureRealtimeSynthesizer();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Verify very short percussive notes (< 1024 renderAheadFrames, e.g. Note 77 on Drum Kit / Wood Block)
        for (var rep = 1; rep <= 3; rep++) {
          maxAbsSample = 0.0;
          final v = await player.playPreset(
            sf.presets[0],
            key: 77,
            velocity: 100,
          );
          await Future<void>.delayed(const Duration(milliseconds: 80));
          await v.release();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          expect(maxAbsSample, greaterThan(0.15));
        }

        maxAbsSample = 0.0;
        final preset = sf.presets[1]; // Brass
        final voice1 = await player.playPreset(preset, key: 60, velocity: 100);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(maxAbsSample, greaterThan(0.05));
        await voice1.release();

        // Simulate selecting another preset / stopMixerOutput in main_full.dart
        await player.stopMixerOutput();
        maxAbsSample = 0.0;
        final voice2 = await player.playPreset(preset, key: 60, velocity: 100);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(maxAbsSample, greaterThan(0.05));
        await voice2.release();

        await sub.cancel();
        SoLoud.instance.stopMixerOutputStream();
        await player.dispose();
        SoLoud.instance.deinit();
      },
    );

    test(
      'Fast glissando on Celesta_minimal.sf3 with renderAheadFrames does not click or clip',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (MethodCall methodCall) async => Directory.systemTemp.path,
            );
        await SoLoud.instance.init(
          bufferSize: 1024,
          devicePeriodFrames: 128,
          renderAheadFrames: 1024,
        );
        SoLoud.instance.setMaxActiveVoiceCount(1023);

        final sf = await SoundFontFile.fromFile(
          'example/assets/Celesta_minimal.sf3',
        );

        final allSamplesL = <double>[];
        final allSamplesR = <double>[];
        final sub = SoLoud.instance
            .startMixerOutputStream(
              format: MixerOutputFormat.pcmF32le,
              chunkPCMFrames: 2048,
            )
            .listen((chunk) {
              final floats = chunk.buffer.asFloat32List(
                chunk.offsetInBytes,
                chunk.lengthInBytes ~/ 4,
              );
              for (var i = 0; i < floats.length; i += 2) {
                allSamplesL.add(floats[i]);
                allSamplesR.add(floats[i + 1]);
              }
            });

        final player = sf.createPlayer();
        final preset = sf.presets.first;

        // Cold-cache fast glissando (5ms per key)
        int? prevKey;
        for (var key = 48; key <= 72; key++) {
          if (prevKey != null) {
            player.noteOff(prevKey);
          }
          player.playPreset(preset, key: key, velocity: 100);
          prevKey = key;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        if (prevKey != null) {
          player.noteOff(prevKey);
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));

        int clicksCold = 0;
        for (var i = 1; i < allSamplesL.length; i++) {
          final dL = (allSamplesL[i] - allSamplesL[i - 1]).abs();
          final dR = (allSamplesR[i] - allSamplesR[i - 1]).abs();
          if (dL > 0.25 || dR > 0.25) {
            clicksCold++;
          }
        }
        expect(clicksCold, 0);

        allSamplesL.clear();
        allSamplesR.clear();

        // Warm-cache fast glissando (12ms per key)
        prevKey = null;
        for (var key = 48; key <= 72; key++) {
          if (prevKey != null) {
            player.noteOff(prevKey);
          }
          player.playPreset(preset, key: key, velocity: 100);
          prevKey = key;
          await Future<void>.delayed(const Duration(milliseconds: 12));
        }
        if (prevKey != null) {
          player.noteOff(prevKey);
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));

        int clicksWarm = 0;
        int clipCount = 0;
        for (var i = 1; i < allSamplesL.length; i++) {
          final dL = (allSamplesL[i] - allSamplesL[i - 1]).abs();
          final dR = (allSamplesR[i] - allSamplesR[i - 1]).abs();
          if (dL > 0.25 || dR > 0.25) clicksWarm++;
          if (allSamplesL[i].abs() >= 0.999 || allSamplesR[i].abs() >= 0.999) {
            clipCount++;
          }
        }
        expect(clicksWarm, 0);
        expect(clipCount, 0);

        await sub.cancel();
        SoLoud.instance.stopMixerOutputStream();
        await player.dispose();
        SoLoud.instance.deinit();
      },
    );
  });
}
