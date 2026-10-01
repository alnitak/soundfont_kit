/// Models representing synchronized lyrics, text markers, and cue points in a MIDI timeline.
library;

/// The semantic classification of a synchronized text marker in a MIDI timeline.
enum MidiLyricType {
  /// Song lyrics (`MetaEvent 0x05`).
  lyric,

  /// General descriptive or cue text (`MetaEvent 0x01`).
  text,

  /// Rehearsal or timeline marker (`MetaEvent 0x06`).
  marker,

  /// Stage action or cue point (`MetaEvent 0x07`).
  cuePoint,
}

/// Represents an individual timed lyric syllable or text marker positioned along the MIDI timeline.
class MidiLyricSpan {
  /// The absolute timestamp from the beginning of playback.
  final Duration timestamp;

  /// The lyric syllable or marker string text.
  final String text;

  /// The type of text event.
  final MidiLyricType type;

  /// The 0-based track index where this event appeared.
  final int trackIndex;

  /// The musical tick position.
  final int absoluteTick;

  const MidiLyricSpan({
    required this.timestamp,
    required this.text,
    required this.type,
    required this.trackIndex,
    required this.absoluteTick,
  });

  @override
  String toString() =>
      'MidiLyricSpan($type, t: ${timestamp.inMilliseconds}ms, "$text")';
}
