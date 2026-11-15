import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:soundfont_kit/soundfont_kit.dart';

void main() {
  final assetDir = p.join(Directory.current.path, 'example', 'assets');
  final midiPath = p.join(assetDir, 'Piano Sonata n14 op27 - Moonlight.mid');
  final sf2Path = p.join(assetDir, 'RatAttack.sf2');

  group('MidiClockSlave unit tests', () {
    test('Calculates 120 BPM from 24-PPQ 0xF8 pulses and tracks tempo shift to 100 BPM', () {
      final slave = MidiClockSlave(initialBpm: 90.0);

      // 120 BPM => 60,000,000 / (120 * 24) = 20,833.33 us per 0xF8 tick
      var ts = 0;
      for (var i = 0; i < 48; i++) {
        slave.feedByte(kMidiTimingClock, timestampUs: ts);
        ts += 20833;
      }
      expect(slave.bpm, closeTo(120.0, 0.2));

      // Switch to 100 BPM => 60,000,000 / (100 * 24) = 25,000 us per 0xF8 tick
      for (var i = 0; i < 48; i++) {
        slave.feedByte(kMidiTimingClock, timestampUs: ts);
        ts += 25000;
      }
      expect(slave.bpm, closeTo(100.0, 0.2));

      slave.dispose();
    });

    test('Smooths alternating jitter and ignores dropout gaps > threshold', () {
      final slave = MidiClockSlave(initialBpm: 120.0, smoothing: 0.15);

      var ts = 0;
      slave.feedByte(kMidiTimingClock, timestampUs: ts);

      // Feed 60 ticks with alternating +3000 / -3000 us jitter around 20,833 us
      for (var i = 0; i < 60; i++) {
        final jitter = i.isEven ? 3000 : -3000;
        ts += 20833 + jitter;
        slave.feedByte(kMidiTimingClock, timestampUs: ts);
      }

      // Raw instantaneous BPM swings ~105..140, while smoothed BPM stays near 120
      expect(slave.bpm, closeTo(120.0, 3.0));

      // Inject a 2.0-second dropout (> 1.5s default threshold)
      ts += 2000000;
      slave.feedByte(kMidiTimingClock, timestampUs: ts);
      expect(slave.bpm, closeTo(120.0, 3.0));

      // Re-lock cleanly at 120 BPM after dropout
      for (var i = 0; i < 12; i++) {
        ts += 20833;
        slave.feedByte(kMidiTimingClock, timestampUs: ts);
      }
      expect(slave.bpm, closeTo(120.0, 0.5));

      slave.dispose();
    });

    test(
      'Handles 0xFA Start, 0xFC Stop, 0xFB Continue, and interleaved 0xF2 SPP',
      () {
        final slave = MidiClockSlave();

        // Start resets ticks to 0 and starts running
        slave.feedByte(kMidiStart, timestampUs: 0);
        expect(slave.isRunning, isTrue);
        expect(slave.clockTickCount, equals(0));

        // 24 clocks = 1 quarter note
        var ts = 20833;
        for (var i = 0; i < 24; i++) {
          slave.feedByte(kMidiTimingClock, timestampUs: ts);
          ts += 20833;
        }
        expect(slave.clockTickCount, equals(24));
        expect(slave.ppqPosition, equals(1.0));

        // Stop freezes running state and preserves tick position
        slave.feedByte(kMidiStop, timestampUs: ts);
        expect(slave.isRunning, isFalse);
        expect(slave.clockTickCount, equals(24));

        // Clocks arriving while stopped still measure BPM, without advancing ticks
        ts += 20833;
        slave.feedByte(kMidiTimingClock, timestampUs: ts);
        expect(slave.clockTickCount, equals(24));

        // Continue resumes without resetting tick counter
        slave.feedByte(kMidiContinue, timestampUs: ts + 1000);
        expect(slave.isRunning, isTrue);
        expect(slave.clockTickCount, equals(24));

        // Song Position Pointer: 0xF2, LSB=4, interleaved 0xF8, MSB=0
        // 4 MIDI beats * 6 clocks/beat = 24 ticks (and +1 tick for interleaved 0xF8 -> 25 -> then SPP sets 24)
        slave.feedByte(kMidiSongPositionPointer, timestampUs: ts + 2000);
        slave.feedByte(0x04, timestampUs: ts + 2100);
        slave.feedByte(kMidiTimingClock, timestampUs: ts + 20833);
        slave.feedByte(0x00, timestampUs: ts + 20900);
        expect(slave.clockTickCount, equals(24));
        expect(slave.ppqPosition, equals(1.0));

        slave.dispose();
      },
    );
  });

  group('MidiClockSimulator tests', () {
    test('Emits 0xFA, 0xF8 pulses, 0xFC, 0xFB, and 0xF2 SPP into MidiClockSlave', () async {
      final slave = MidiClockSlave();
      final sentBytes = <int>[];
      final sim = MidiClockSimulator(
        bpm: 150.0,
        jitterMs: 0.5,
        randomSeed: 7,
        onSendByte: (byte, ts) {
          sentBytes.add(byte);
          slave.feedByte(byte, timestampUs: ts);
        },
      );

      sim.start();
      expect(sim.isRunning, isTrue);
      expect(sentBytes.first, equals(kMidiStart));

      await Future<void>.delayed(const Duration(milliseconds: 160));
      sim.stop();
      expect(sim.isRunning, isFalse);
      expect(sentBytes.last, equals(kMidiStop));
      expect(sentBytes.where((b) => b == kMidiTimingClock).length, greaterThan(4));
      expect(slave.isRunning, isFalse);
      expect(slave.clockTickCount, greaterThan(4));
      expect(slave.bpm, closeTo(150.0, 20.0));

      final ticksAtStop = slave.clockTickCount;
      sim.continuePlayback();
      expect(sim.isRunning, isTrue);
      expect(slave.isRunning, isTrue);
      expect(sentBytes.last, equals(kMidiTimingClock)); // initial pulse on continue
      expect(sentBytes, contains(kMidiContinue));
      expect(slave.clockTickCount, greaterThanOrEqualTo(ticksAtStop));

      sim.stop();
      sim.sendSongPosition(8); // 8 sixteenth notes = 48 clocks = 2.0 quarter notes
      expect(slave.clockTickCount, equals(48));
      expect(slave.ppqPosition, equals(2.0));

      sim.dispose();
      await slave.dispose();
    });
  });

  group('MidiPlayer 0xF8 Slave integration tests', () {
    test('Starts, tracks BPM, pauses, resumes, and seeks via 0xF8/0xFA/0xFC/0xFB/0xF2', () async {
      final sf = await SoundFontFile.fromFile(sf2Path);
      final player = sf.createPlayer();
      final midiPlayer = MidiPlayer(player: player);
      final midi = await MidiReader.fromFile(File(midiPath));
      await midiPlayer.load(midi, autoPreload: false);

      // 1. Start via 0xFA
      midiPlayer.feedMidiClockByte(kMidiStart, timestampUs: 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(midiPlayer.externalClockSync, isTrue);
      expect(midiPlayer.isPlaying, isTrue);

      // 2. Drive 24 clocks at 150 BPM (16,666.67 us per tick)
      var ts = 16667;
      for (var i = 0; i < 24; i++) {
        midiPlayer.feedMidiClockByte(kMidiTimingClock, timestampUs: ts);
        ts += 16667;
      }
      expect(midiPlayer.currentBpm, closeTo(150.0, 0.5));

      final posBeforeTempoShift = midiPlayer.position;

      // 3. Shift tempo smoothly to 90 BPM (27,777.78 us per tick) without jumping position
      for (var i = 0; i < 40; i++) {
        midiPlayer.feedMidiClockByte(kMidiTimingClock, timestampUs: ts);
        ts += 27778;
      }
      expect(midiPlayer.currentBpm, closeTo(90.0, 0.5));
      expect(
        (midiPlayer.position - posBeforeTempoShift).abs(),
        lessThan(const Duration(milliseconds: 250)),
      );

      // 4. Stop (0xFC) pauses playback
      midiPlayer.feedMidiClockByte(kMidiStop, timestampUs: ts);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(midiPlayer.isPlaying, isFalse);
      expect(midiPlayer.isPaused, isTrue);
      final pausedPos = midiPlayer.position;

      // 5. Continue (0xFB) resumes from paused position
      midiPlayer.feedMidiClockByte(kMidiContinue, timestampUs: ts + 10000);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(midiPlayer.isPlaying, isTrue);
      expect(midiPlayer.position, greaterThanOrEqualTo(pausedPos));

      // 6. Song Position Pointer (0xF2, 16 MIDI beats = 4 quarter notes) seeks cleanly
      midiPlayer.feedMidiClockBytes([kMidiSongPositionPointer, 16, 0], timestampUs: ts + 20000);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final expectedTick = 4 * midi.ticksPerQuarterNote;
      final expectedPos = midiPlayer.timeline!.tempoMap.tickToDuration(expectedTick);
      expect(
        (midiPlayer.position - expectedPos).abs(),
        lessThan(const Duration(milliseconds: 200)),
      );

      await midiPlayer.dispose();
      await player.dispose();
    });
  });
}
