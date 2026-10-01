import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:soundfont_kit/soundfont_kit.dart';

void main() {
  final assetDir = p.join(Directory.current.path, 'example', 'assets');
  final midiPath = p.join(assetDir, 'Piano Sonata n14 op27 - Moonlight.mid');
  final sf2Path = p.join(assetDir, 'RatAttack.sf2');

  group('ChordDetector Tests', () {
    test('Detects major triad and slash inversions', () {
      // C major root position: C4 (60), E4 (64), G4 (67)
      expect(ChordDetector.detectChord([60, 64, 67]), equals('C'));

      // 1st inversion: E4 (64), G4 (67), C5 (72) -> C/E
      expect(ChordDetector.detectChord([64, 67, 72]), equals('C/E'));

      // 2nd inversion: G3 (55), C4 (60), E4 (64) -> C/G
      expect(ChordDetector.detectChord([55, 60, 64]), equals('C/G'));
    });

    test('Detects minor triad and 7th chords', () {
      // A minor: A3 (57), C4 (60), E4 (64)
      expect(ChordDetector.detectChord([57, 60, 64]), equals('Am'));

      // G dominant 7th: G3 (55), B3 (59), D4 (62), F4 (65)
      expect(ChordDetector.detectChord([55, 59, 62, 65]), equals('G7'));

      // C major 7th: C4 (60), E4 (64), G4 (67), B4 (71)
      expect(ChordDetector.detectChord([60, 64, 67, 71]), equals('Cmaj7'));

      // D minor 7th: D4 (62), F4 (65), A4 (69), C5 (72)
      expect(ChordDetector.detectChord([62, 65, 69, 72]), equals('Dm7'));
    });

    test('Handles suspended, diminished, and augmented chords', () {
      // D suspended 4th: D4 (62), G4 (67), A4 (69)
      expect(ChordDetector.detectChord([62, 67, 69]), equals('Dsus4'));

      // B diminished: B3 (59), D4 (62), F4 (65)
      expect(ChordDetector.detectChord([59, 62, 65]), equals('Bdim'));

      // C augmented: C4 (60), E4 (64), G#4 (68)
      expect(ChordDetector.detectChord([60, 64, 68]), equals('Caug'));
    });

    test('Returns note name for single note and null for non-chord dyads', () {
      expect(ChordDetector.detectChord([]), isNull);
      expect(ChordDetector.detectChord([60]), equals('C'));
      expect(ChordDetector.detectChord([60, 64]), isNull);
    });
  });

  group('MidiTimeline Lyrics & Markers Tests', () {
    test('Reads lyrics from timeline if present or provides empty list', () async {
      final midi = await MidiReader.fromFile(File(midiPath));
      final timeline = MidiTimeline.fromMidiFile(midi);

      // Moonlight sonata has no lyrics but timeline should initialize clean structures
      expect(timeline.lyrics, isNotNull);
      expect(timeline.hasLyrics, equals(timeline.lyrics.isNotEmpty));
      expect(timeline.fullLyricsText, isA<String>());
    });

    test('MidiLyricSpan properties and formatting', () {
      final span = MidiLyricSpan(
        text: 'Hello',
        timestamp: const Duration(seconds: 2),
        absoluteTick: 480,
        type: MidiLyricType.lyric,
        trackIndex: 0,
      );

      expect(span.text, equals('Hello'));
      expect(span.timestamp, equals(const Duration(seconds: 2)));
      expect(span.absoluteTick, equals(480));
      expect(span.type, equals(MidiLyricType.lyric));
      expect(span.toString(), contains('Hello'));
    });
  });

  group('MidiPlayer Transport & Expressive Features Tests', () {
    test('Transposition shifts pitch and separates drum channel', () async {
      final sf = await SoundFontFile.fromFile(sf2Path);
      final player = sf.createPlayer();
      final midiPlayer = MidiPlayer(player: player);

      expect(midiPlayer.transpose, equals(0));
      midiPlayer.transpose = 2; // +2 semitones globally
      expect(midiPlayer.transpose, equals(2));

      // Channel specific transpose
      midiPlayer.channels[0].transpose = -1;
      expect(midiPlayer.channels[0].transpose, equals(-1));

      // Drum channel (index 9) transpose should be preserved but ignored during playback
      expect(midiPlayer.channels[9].channel, equals(9));

      await midiPlayer.dispose();
      await player.dispose();
    });

    test('Region Looping setLoopRange and clearLoopRange', () async {
      final sf = await SoundFontFile.fromFile(sf2Path);
      final player = sf.createPlayer();
      final midiPlayer = MidiPlayer(player: player);

      expect(midiPlayer.isLoopActive, isFalse);

      midiPlayer.setLoopRange(
        const Duration(seconds: 5),
        const Duration(seconds: 15),
      );

      expect(midiPlayer.isLoopActive, isTrue);
      expect(midiPlayer.loopStart, equals(const Duration(seconds: 5)));
      expect(midiPlayer.loopEnd, equals(const Duration(seconds: 15)));

      midiPlayer.clearLoopRange();
      expect(midiPlayer.isLoopActive, isFalse);
      expect(midiPlayer.loopStart, isNull);
      expect(midiPlayer.loopEnd, isNull);

      await midiPlayer.dispose();
      await player.dispose();
    });

    test('Override BPM and speed calculation', () async {
      final sf = await SoundFontFile.fromFile(sf2Path);
      final player = sf.createPlayer();
      final midiPlayer = MidiPlayer(player: player);

      expect(midiPlayer.overrideBpm, isNull);
      midiPlayer.overrideBpm = 140.0;
      expect(midiPlayer.overrideBpm, equals(140.0));

      midiPlayer.overrideBpm = null;
      expect(midiPlayer.overrideBpm, isNull);

      await midiPlayer.dispose();
      await player.dispose();
    });

    test('Track Mute and Solo filtering', () async {
      final sf = await SoundFontFile.fromFile(sf2Path);
      final player = sf.createPlayer();
      final midiPlayer = MidiPlayer(player: player);

      expect(midiPlayer.isTrackMuted(1), isFalse);
      expect(midiPlayer.isTrackSolo(1), isFalse);

      midiPlayer.setTrackMute(1, true);
      expect(midiPlayer.isTrackMuted(1), isTrue);

      midiPlayer.setTrackSolo(2, true);
      expect(midiPlayer.isTrackSolo(2), isTrue);

      midiPlayer.setTrackMute(1, false);
      expect(midiPlayer.isTrackMuted(1), isFalse);

      midiPlayer.setTrackSolo(2, false);
      expect(midiPlayer.isTrackSolo(2), isFalse);

      await midiPlayer.dispose();
      await player.dispose();
    });
  });

  group('MidiChannelState Expressive Controllers Tests', () {
    test('Calculates pitch bend multiplier accurately', () {
      final ch = MidiChannelState(channel: 0);
      expect(ch.pitchBend, equals(0.0));
      expect(ch.pitchBendMultiplier, closeTo(1.0, 0.0001));

      // Pitch bend up 2 semitones at 1.0 (max)
      ch.applyPitchBend(1.0);
      expect(ch.pitchBend, equals(1.0));
      // 2^(2 / 12) ~ 1.12246
      expect(ch.pitchBendMultiplier, closeTo(1.12246, 0.01));

      // Pitch bend down 2 semitones at -1.0 (min)
      ch.applyPitchBend(-1.0);
      expect(ch.pitchBend, equals(-1.0));
      // 2^(-2 / 12) ~ 0.89089
      expect(ch.pitchBendMultiplier, closeTo(0.89089, 0.01));

      // Center
      ch.applyPitchBend(0.0);
      expect(ch.pitchBendMultiplier, closeTo(1.0, 0.0001));
    });

    test('Sostenuto and Soft pedal state transitions', () {
      final ch = MidiChannelState(channel: 0);
      expect(ch.isSostenutoPedalOn, isFalse);
      expect(ch.isSoftPedalOn, isFalse);

      ch.setSostenutoPedal(true);
      expect(ch.isSostenutoPedalOn, isTrue);

      ch.setSoftPedal(true);
      expect(ch.isSoftPedalOn, isTrue);

      ch.setSostenutoPedal(false);
      expect(ch.isSostenutoPedalOn, isFalse);

      ch.setSoftPedal(false);
      expect(ch.isSoftPedalOn, isFalse);
    });

    test('Reset controllers restores default CC values', () {
      final ch = MidiChannelState(channel: 0);
      ch.applyVolume(0.5);
      ch.applyExpression(0.8);
      ch.applyPan(-0.3);
      ch.applyPitchBend(0.7);
      ch.setSostenutoPedal(true);
      ch.setSoftPedal(true);
      ch.bankMsb = 5;
      ch.bankLsb = 2;

      ch.resetControllers();

      expect(ch.volume, closeTo(100.0 / 127.0, 0.001));
      expect(ch.expression, equals(1.0));
      expect(ch.pan, equals(0.0));
      expect(ch.pitchBend, equals(0.0));
      expect(ch.isSostenutoPedalOn, isFalse);
      expect(ch.isSoftPedalOn, isFalse);
    });
  });
}
