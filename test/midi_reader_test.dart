import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:soundfont_kit/src/midi/midi_models.dart';
import 'package:soundfont_kit/src/midi/midi_reader.dart';

void main() {
  group('MidiReader Synthetic Binary Tests', () {
    test('Parses minimal synthetic Format 0 MIDI file with running status', () {
      final builder = BytesBuilder();

      // MThd Header
      builder.add([0x4D, 0x54, 0x68, 0x64]); // 'MThd'
      builder.add([0x00, 0x00, 0x00, 0x06]); // length 6
      builder.add([0x00, 0x00]); // format 0
      builder.add([0x00, 0x01]); // 1 track
      builder.add([0x01, 0xE0]); // 480 PPQ (0x01E0)

      // MTrk Track
      final trackData = BytesBuilder();
      // Delta 0, Set Tempo 500,000 us (120 BPM): FF 51 03 07 A1 20
      trackData.add([0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]);
      // Delta 0, Track Name: FF 03 04 'Test'
      trackData.add([0x00, 0xFF, 0x03, 0x04, 0x54, 0x65, 0x73, 0x74]);
      // Delta 0, Program Change ch 0, prog 0 (Piano): C0 00
      trackData.add([0x00, 0xC0, 0x00]);
      // Delta 0, Note On ch 0, note 60 (C4), vel 100: 90 3C 64
      trackData.add([0x00, 0x90, 0x3C, 0x64]);
      // Delta 480 (0x83 0x60 in VLQ), Note On with vel 0 (Note Off) running status: 3C 00
      trackData.add([0x83, 0x60, 0x3C, 0x00]);
      // Delta 0, Control Change ch 0, CC 64 (Sustain), val 127: B0 40 7F
      trackData.add([0x00, 0xB0, 0x40, 0x7F]);
      // Delta 0, End of Track: FF 2F 00
      trackData.add([0x00, 0xFF, 0x2F, 0x00]);

      final trackBytes = trackData.toBytes();
      builder.add([0x4D, 0x54, 0x72, 0x6B]); // 'MTrk'
      final len = trackBytes.length;
      builder.add([
        (len >> 24) & 0xFF,
        (len >> 16) & 0xFF,
        (len >> 8) & 0xFF,
        len & 0xFF,
      ]);
      builder.add(trackBytes);

      final midi = MidiReader.fromBytes(builder.toBytes());

      expect(midi.format, equals(0));
      expect(midi.header.numTracks, equals(1));
      expect(midi.ticksPerQuarterNote, equals(480));
      expect(midi.tracks.length, equals(1));

      final track = midi.tracks.first;
      expect(track.name, equals('Test'));

      // Check events
      final events = track.events;
      expect(events.any((e) => e is SetTempoEvent && e.bpm == 120.0), isTrue);
      expect(events.any((e) => e is ProgramChangeEvent && e.program == 0), isTrue);

      final noteOns = events.whereType<NoteOnEvent>().toList();
      expect(noteOns.length, equals(2));
      expect(noteOns[0].note, equals(60));
      expect(noteOns[0].velocity, equals(100));
      expect(noteOns[0].isNoteOff, isFalse);

      expect(noteOns[1].note, equals(60));
      expect(noteOns[1].velocity, equals(0));
      expect(noteOns[1].isNoteOff, isTrue);

      final ccEvents = events.whereType<ControlChangeEvent>().toList();
      expect(ccEvents.length, equals(1));
      expect(ccEvents[0].isSustainPedal, isTrue);
      expect(ccEvents[0].isSustainOn, isTrue);

      expect(events.last, isA<EndOfTrackEvent>());
    });

    test('Parses RIFF RMID encapsulated MIDI file', () {
      final smfBuilder = BytesBuilder();
      // MThd Header
      smfBuilder.add([0x4D, 0x54, 0x68, 0x64]); // 'MThd'
      smfBuilder.add([0x00, 0x00, 0x00, 0x06]); // length 6
      smfBuilder.add([0x00, 0x00]); // format 0
      smfBuilder.add([0x00, 0x01]); // 1 track
      smfBuilder.add([0x01, 0xE0]); // 480 PPQ

      // MTrk Track
      final trackData = BytesBuilder();
      trackData.add([0x00, 0xFF, 0x2F, 0x00]); // End of Track
      final trackBytes = trackData.toBytes();
      smfBuilder.add([0x4D, 0x54, 0x72, 0x6B]); // 'MTrk'
      final len = trackBytes.length;
      smfBuilder.add([
        (len >> 24) & 0xFF,
        (len >> 16) & 0xFF,
        (len >> 8) & 0xFF,
        len & 0xFF,
      ]);
      smfBuilder.add(trackBytes);
      final smfBytes = smfBuilder.toBytes();

      // Wrap in RIFF RMID container
      final riffBuilder = BytesBuilder();
      riffBuilder.add([0x52, 0x49, 0x46, 0x46]); // 'RIFF'
      final riffLen = 4 + 8 + smfBytes.length;
      riffBuilder.add([
        riffLen & 0xFF,
        (riffLen >> 8) & 0xFF,
        (riffLen >> 16) & 0xFF,
        (riffLen >> 24) & 0xFF,
      ]);
      riffBuilder.add([0x52, 0x4D, 0x49, 0x44]); // 'RMID'
      riffBuilder.add([0x64, 0x61, 0x74, 0x61]); // 'data'
      final dataLen = smfBytes.length;
      riffBuilder.add([
        dataLen & 0xFF,
        (dataLen >> 8) & 0xFF,
        (dataLen >> 16) & 0xFF,
        (dataLen >> 24) & 0xFF,
      ]);
      riffBuilder.add(smfBytes);

      final rmidMidi = MidiReader.fromBytes(riffBuilder.toBytes());
      expect(rmidMidi.format, equals(0));
      expect(rmidMidi.tracks.length, equals(1));
    });
  });

  group('MidiReader Real Asset Tests', () {
    test('Successfully parses Moonlight Sonata MIDI file', () async {
      final assetDir = p.join(Directory.current.path, 'example', 'assets');
      final midiPath = p.join(assetDir, 'Piano Sonata n14 op27 - Moonlight.mid');
      final midiFile = File(midiPath);

      expect(midiFile.existsSync(), isTrue, reason: 'Moonlight Sonata MIDI file must exist');

      final midi = await MidiReader.fromFile(midiFile);

      expect(midi.tracks, isNotEmpty);
      expect(midi.ticksPerQuarterNote, greaterThan(0));
      expect(midi.totalTicks, greaterThan(0));

      // Check that there are NoteOn events across tracks
      int totalNoteOns = 0;
      int totalSustainEvents = 0;
      int tempoChanges = 0;

      for (final track in midi.tracks) {
        for (final event in track.events) {
          if (event is NoteOnEvent && !event.isNoteOff) {
            totalNoteOns++;
          } else if (event is ControlChangeEvent && event.isSustainPedal) {
            totalSustainEvents++;
          } else if (event is SetTempoEvent) {
            tempoChanges++;
          }
        }
      }

      expect(totalNoteOns, greaterThan(100), reason: 'Moonlight Sonata should have hundreds of notes');
      expect(totalSustainEvents, greaterThanOrEqualTo(0));
      expect(tempoChanges, greaterThan(0), reason: 'Should have at least initial tempo');

      // Check usedChannels (Moonlight Sonata uses Channels 1, 2, 4)
      expect(midi.usedChannels, equals({1, 2, 4}));
    });
  });
}
