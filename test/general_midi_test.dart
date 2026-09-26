import 'package:flutter_test/flutter_test.dart';
import 'package:soundfont_kit/soundfont_kit.dart';

void main() {
  group('GeneralMidi Tests', () {
    test('Correctly maps program numbers to standard GM instrument names', () {
      expect(GeneralMidi.getProgramName(0), equals('Acoustic Grand Piano'));
      expect(GeneralMidi.getProgramName(24), equals('Acoustic Guitar (nylon)'));
      expect(GeneralMidi.getProgramName(40), equals('Violin'));
      expect(GeneralMidi.getProgramName(56), equals('Trumpet'));
      expect(GeneralMidi.getProgramName(73), equals('Flute'));
      expect(GeneralMidi.getProgramName(127), equals('Gunshot'));
      expect(GeneralMidi.instrumentNames.length, equals(128));
    });

    test('Correctly maps program numbers to instrument families', () {
      expect(GeneralMidi.getFamilyName(0), equals('Piano'));
      expect(GeneralMidi.getFamilyName(24), equals('Guitar'));
      expect(GeneralMidi.getFamilyName(32), equals('Bass'));
      expect(GeneralMidi.getFamilyName(40), equals('Strings'));
      expect(GeneralMidi.getFamilyName(56), equals('Brass'));
      expect(GeneralMidi.getFamilyName(80), equals('Synth Lead'));
    });

    test('Correctly maps drum notes to drum names', () {
      expect(GeneralMidi.getDrumName(35), equals('Acoustic Bass Drum'));
      expect(GeneralMidi.getDrumName(38), equals('Acoustic Snare'));
      expect(GeneralMidi.getDrumName(42), equals('Closed Hi-Hat'));
    });

    test('MidiChannelState returns suggested instrument names', () {
      final ch0 = MidiChannelState(channel: 0, program: 0);
      expect(ch0.getSuggestedInstrumentName(), equals('Acoustic Grand Piano'));
      expect(ch0.getSuggestedFamilyName(), equals('Piano'));

      final ch9 = MidiChannelState(channel: 9);
      expect(ch9.getSuggestedInstrumentName(), equals('Standard Drum Kit'));
      expect(ch9.getSuggestedFamilyName(), equals('Drums / Percussion'));

      final ch1 = MidiChannelState(channel: 1, program: 40);
      expect(ch1.getSuggestedInstrumentName(), equals('Violin'));
      expect(ch1.getSuggestedFamilyName(), equals('Strings'));
    });
  });
}
