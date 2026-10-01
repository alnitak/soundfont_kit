/// Lightweight musical chord detection from active MIDI note collections.
library;

/// Helper utility that detects musical chord names from sounding MIDI note numbers.
class ChordDetector {
  static const List<String> _noteNames = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  /// Detects the musical chord name for a collection of [midiNotes] (0-127).
  ///
  /// Returns null if [midiNotes] is empty. Handles chord inversions with slash
  /// notation (e.g. "C/E") when the lowest sounding note differs from the chord root.
  static String? detectChord(Iterable<int> midiNotes) {
    final notes = midiNotes.toSet().toList();
    if (notes.isEmpty) return null;

    notes.sort();
    final bassNote = notes.first % 12;
    final pitchClasses = notes.map((n) => n % 12).toSet();

    if (pitchClasses.length == 1) {
      return _noteNames[pitchClasses.first];
    }

    // Known chord interval templates: key is interval set, value is chord suffix
    const chordSignatures = <String, String>{
      '0,4,7': '', // Major
      '0,3,7': 'm', // Minor
      '0,4,7,10': '7', // Dominant 7th
      '0,4,7,11': 'maj7', // Major 7th
      '0,3,7,10': 'm7', // Minor 7th
      '0,3,7,11': 'm(maj7)', // Minor Major 7th
      '0,3,6': 'dim', // Diminished triad
      '0,3,6,9': 'dim7', // Diminished 7th
      '0,3,6,10': 'm7b5', // Half-diminished
      '0,4,8': 'aug', // Augmented triad
      '0,5,7': 'sus4', // Suspended 4th
      '0,2,7': 'sus2', // Suspended 2nd
      '0,2,4,7': 'add9', // Add 9
      '0,4,7,9': '6', // Major 6th
      '0,3,7,9': 'm6', // Minor 6th
      '0,7': '5', // Power chord
    };

    // First try the bass note as root, then check other pitch classes
    final candidates = [bassNote, ...pitchClasses.where((p) => p != bassNote)];

    for (final root in candidates) {
      final intervals =
          pitchClasses.map((p) => (p - root + 12) % 12).toList()..sort();
      final key = intervals.join(',');

      final suffix = chordSignatures[key];
      if (suffix != null) {
        final rootName = _noteNames[root];
        if (bassNote != root) {
          return '$rootName$suffix/${_noteNames[bassNote]}';
        }
        return '$rootName$suffix';
      }
    }

    // Fallback: If 3 or more notes without exact template match, try matching
    // core triad (root + 3rd + 5th) ignoring extensions
    for (final root in candidates) {
      final intervals = pitchClasses.map((p) => (p - root + 12) % 12).toSet();
      if (intervals.contains(4) && intervals.contains(7)) {
        final rootName = _noteNames[root];
        final bass =
            bassNote != root ? '/${_noteNames[bassNote]}' : '';
        return '$rootName$bass';
      }
      if (intervals.contains(3) && intervals.contains(7)) {
        final rootName = _noteNames[root];
        final bass =
            bassNote != root ? '/${_noteNames[bassNote]}' : '';
        return '${rootName}m$bass';
      }
    }

    return null;
  }
}
