import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:soundfont_kit/soundfont_kit.dart';

void main() {
  final assetDir = p.join(Directory.current.path, 'example', 'assets');
  final midiPath = p.join(assetDir, 'Piano Sonata n14 op27 - Moonlight.mid');
  final sf2Path = p.join(assetDir, 'RatAttack.sf2');

  group('MidiTimeline Tests', () {
    test('Builds timeline from Moonlight Sonata and computes tempo map', () async {
      final midi = await MidiReader.fromFile(File(midiPath));
      final timeline = MidiTimeline.fromMidiFile(midi);

      expect(timeline.events, isNotEmpty);
      expect(timeline.duration.inSeconds, greaterThan(30),
          reason: 'Moonlight Sonata movement should be at least several minutes long');

      // Test state chasing
      final (snapshots, nextIndex) = timeline.getSnapshotAt(const Duration(seconds: 10));
      expect(snapshots.length, equals(16));
      expect(nextIndex, greaterThan(0));
    });
    test('Calculates nextEventIndex accurately at exact timestamp boundary', () async {
      final midi = await MidiReader.fromFile(File(midiPath));
      final timeline = MidiTimeline.fromMidiFile(midi);

      expect(timeline.events, isNotEmpty);
      final sampleEvent = timeline.events[timeline.events.length ~/ 2];
      final targetTimestamp = sampleEvent.timestamp;

      final (snapshots, nextIndex) = timeline.getSnapshotAt(targetTimestamp);
      expect(snapshots.length, equals(16));
      expect(nextIndex, lessThanOrEqualTo(timeline.events.length));
      if (nextIndex < timeline.events.length) {
        expect(timeline.events[nextIndex].timestamp, greaterThanOrEqualTo(targetTimestamp));
      }
    });

    test('Calculates clean timeline duration by ignoring trailing orphan NoteOffs and empty padding', () async {
      final fcFile = File('/Volumes/NVME/workspace/tmp/midiArchive/Metal_Rock_rock.freemidis.net_MIDIRip/midi/e/europe/Final_Countdown.mid');
      if (fcFile.existsSync()) {
        final midi = await MidiReader.fromFile(fcFile);
        final timeline = MidiTimeline.fromMidiFile(midi);
        // Notes finish at ~3m20s-3m24s rather than corrupted 14m40s
        expect(timeline.duration, equals(const Duration(minutes: 3, seconds: 24)));
        expect(timeline.events.last.timestamp, lessThanOrEqualTo(timeline.duration));
      }
    });
  });

  group('MidiPlayer Load & Preload Tests', () {
    test('Loads MIDI and SoundFont and verifies channel snapshot', () async {
      final sf = await SoundFontFile.fromFile(sf2Path);
      final player = sf.createPlayer();
      final midiPlayer = MidiPlayer(player: player);

      final midi = await MidiReader.fromFile(File(midiPath));
      await midiPlayer.load(midi, autoPreload: false);

      expect(midiPlayer.midiFile, isNotNull);
      expect(midiPlayer.duration, greaterThan(Duration.zero));
      expect(midiPlayer.position, equals(Duration.zero));
      expect(midiPlayer.isPlaying, isFalse);

      await midiPlayer.dispose();
    });

    test('Emits seek event and updates position when seeking', () async {
      final sf = await SoundFontFile.fromFile(sf2Path);
      final player = sf.createPlayer();
      final midiPlayer = MidiPlayer(player: player);

      final midi = await MidiReader.fromFile(File(midiPath));
      await midiPlayer.load(midi, autoPreload: false);

      final events = <MidiPlaybackEvent>[];
      final sub = midiPlayer.eventStream.listen(events.add);

      const target = Duration(seconds: 15);
      await midiPlayer.seek(target);
      await Future<void>.delayed(Duration.zero);

      expect(midiPlayer.position, equals(target));
      expect(events.any((e) => e.type == MidiPlaybackEventType.seek && e.timestamp == target), isTrue);

      await sub.cancel();
      await midiPlayer.dispose();
      await player.dispose();
    });

    test('Smoothly updates speedMultiplier without timeline jumps', () async {
      final sf = await SoundFontFile.fromFile(sf2Path);
      final player = sf.createPlayer();
      final midiPlayer = MidiPlayer(player: player);

      final midi = await MidiReader.fromFile(File(midiPath));
      await midiPlayer.load(midi, autoPreload: false);

      await midiPlayer.play();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final posBefore = midiPlayer.position;
      expect(posBefore, greaterThan(Duration.zero));

      // Increase speed to 2.0x
      midiPlayer.speedMultiplier = 2.0;
      final posAfter = midiPlayer.position;

      // Position should be virtually unchanged immediately after setting speedMultiplier
      expect((posAfter.inMilliseconds - posBefore.inMilliseconds).abs(), lessThan(50));

      await midiPlayer.stop();
      await midiPlayer.dispose();
      await player.dispose();
    });

    test('Allows custom SoundFont player and preset routing per channel', () async {
      final defaultSf = await SoundFontFile.fromFile(sf2Path);
      final defaultPlayer = defaultSf.createPlayer();
      final midiPlayer = MidiPlayer(player: defaultPlayer);

      final customSfPath = p.join(assetDir, 'Celesta_minimal.sf3');
      final customSf = await SoundFontFile.fromFile(customSfPath);
      final customPlayer = customSf.createPlayer();

      expect(customSf.presets, isNotEmpty);
      final customPreset = customSf.presets.first;

      // Assign custom SoundFont & preset to channel 1 (index 0)
      midiPlayer.setChannelSoundFont(
        0,
        customPlayer: customPlayer,
        preset: customPreset,
      );

      final ch0 = midiPlayer.channels[0];
      expect(ch0.customPlayer, equals(customPlayer));
      expect(ch0.presetOverride, equals(customPreset));
      expect(midiPlayer.getSuggestedInstrumentName(0), equals(customPreset.name));
      expect(midiPlayer.getSuggestedFamilyName(0), contains(customSf.name ?? ''));

      // Clear override
      midiPlayer.clearChannelOverride(0);
      expect(ch0.customPlayer, isNull);
      expect(ch0.presetOverride, isNull);

      await defaultPlayer.dispose();
      await customPlayer.dispose();
      await midiPlayer.dispose();
    });
  });
}
