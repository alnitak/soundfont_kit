/// MIDI data models representing headers, tracks, and events in Standard MIDI Files (SMF).
library;

/// Header information parsed from a MIDI file's `MThd` chunk.
class MidiHeader {
  /// The SMF format type:
  /// - 0: Single multi-channel track
  /// - 1: One or more simultaneous tracks (most common for multi-track songs)
  /// - 2: One or more sequentially independent single-track patterns
  final int format;

  /// The number of track chunks (`MTrk`) contained in the file.
  final int numTracks;

  /// The raw time division word.
  /// If positive (bit 15 is 0), it represents Pulses (ticks) Per Quarter note (PPQ).
  /// If negative (bit 15 is 1), it represents SMPTE timecode format.
  final int timeDivision;

  const MidiHeader({
    required this.format,
    required this.numTracks,
    required this.timeDivision,
  });

  /// Pulses (ticks) per quarter note. Returns [timeDivision] if PPQ format, or 480 as fallback.
  int get ticksPerQuarterNote {
    if ((timeDivision & 0x8000) == 0) {
      return timeDivision;
    }
    return 480;
  }

  /// Whether this file uses SMPTE time division.
  bool get isSmpte => (timeDivision & 0x8000) != 0;

  @override
  String toString() =>
      'MidiHeader(format: $format, numTracks: $numTracks, PPQ: $ticksPerQuarterNote)';
}

/// Represents an entire parsed Standard MIDI File (SMF).
class MidiFile {
  /// The header chunk metadata.
  final MidiHeader header;

  /// The list of tracks contained in this MIDI file.
  final List<MidiTrack> tracks;

  const MidiFile({required this.header, required this.tracks});

  /// The format type (0, 1, or 2).
  int get format => header.format;

  /// Pulses (ticks) per quarter note.
  int get ticksPerQuarterNote => header.ticksPerQuarterNote;

  /// The highest absolute tick across all tracks.
  int get totalTicks {
    int maxTick = 0;
    for (final track in tracks) {
      if (track.events.isNotEmpty) {
        final lastTick = track.events.last.absoluteTick;
        if (lastTick > maxTick) maxTick = lastTick;
      }
    }
    return maxTick;
  }

  /// Retrieves the track name if defined in the first track or metadata.
  String? get songTitle {
    for (final track in tracks) {
      if (track.name != null && track.name!.isNotEmpty) {
        return track.name;
      }
    }
    return null;
  }

  /// The set of 0-based MIDI channels (0-15) actively used by note events in this file.
  Set<int> get usedChannels {
    final channels = <int>{};
    for (final track in tracks) {
      channels.addAll(track.usedChannels);
    }
    return channels;
  }

  @override
  String toString() =>
      'MidiFile(format: $format, tracks: ${tracks.length}, totalTicks: $totalTicks, PPQ: $ticksPerQuarterNote)';
}

/// Represents a single track (`MTrk`) containing a sequence of timed MIDI events.
class MidiTrack {
  /// The 0-based index of this track within the MIDI file.
  final int trackNumber;

  /// The sequence of MIDI events in chronological order for this track.
  final List<MidiEvent> events;

  /// Optional track name parsed from a [TrackNameEvent].
  final String? name;

  const MidiTrack({required this.trackNumber, required this.events, this.name});

  /// The set of 0-based MIDI channels (0-15) actively used by note events in this track.
  Set<int> get usedChannels {
    final result = <int>{};
    for (final event in events) {
      if (event is NoteOnEvent && !event.isNoteOff) {
        result.add(event.channel);
      }
    }
    return result;
  }

  @override
  String toString() =>
      'MidiTrack(track: $trackNumber, name: ${name != null ? '"$name"' : 'none'}, events: ${events.length})';
}

/// Base class for all MIDI events occurring at a specific point in time.
abstract class MidiEvent {
  /// Delta-time in ticks since the preceding event on the same track.
  final int deltaTime;

  /// Cumulative absolute tick position from the start of the track.
  final int absoluteTick;

  const MidiEvent({required this.deltaTime, required this.absoluteTick});
}

// ---------------------------------------------------------------------------
// Channel Voice Events
// ---------------------------------------------------------------------------

/// Base class for MIDI events targeted to a specific MIDI channel (0-15).
abstract class MidiChannelEvent extends MidiEvent {
  /// MIDI channel (0-15, where channel 9 / index 9 corresponds to MIDI Channel 10).
  final int channel;

  const MidiChannelEvent({
    required this.channel,
    required super.deltaTime,
    required super.absoluteTick,
  });
}

/// Triggers a note on a specific channel.
class NoteOnEvent extends MidiChannelEvent {
  /// MIDI key number (0-127). 60 is Middle C (C4).
  final int note;

  /// Note strike velocity (0-127). A velocity of 0 is treated as a NoteOff.
  final int velocity;

  const NoteOnEvent({
    required super.channel,
    required this.note,
    required this.velocity,
    required super.deltaTime,
    required super.absoluteTick,
  });

  /// Whether this event is functionally a NoteOff (due to velocity == 0).
  bool get isNoteOff => velocity == 0;

  @override
  String toString() =>
      'NoteOnEvent(ch: $channel, note: $note, vel: $velocity, tick: $absoluteTick)';
}

/// Releases a sounding note on a specific channel.
class NoteOffEvent extends MidiChannelEvent {
  /// MIDI key number (0-127).
  final int note;

  /// Release velocity (0-127).
  final int velocity;

  const NoteOffEvent({
    required super.channel,
    required this.note,
    this.velocity = 64,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() =>
      'NoteOffEvent(ch: $channel, note: $note, vel: $velocity, tick: $absoluteTick)';
}

/// Polyphonic key pressure (aftertouch) applied to an individual held note.
class PolyphonicKeyPressureEvent extends MidiChannelEvent {
  final int note;
  final int pressure;

  const PolyphonicKeyPressureEvent({
    required super.channel,
    required this.note,
    required this.pressure,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() =>
      'PolyphonicKeyPressureEvent(ch: $channel, note: $note, pressure: $pressure, tick: $absoluteTick)';
}

/// Control Change (CC) message modifying channel parameters like volume, pan, or sustain pedal.
class ControlChangeEvent extends MidiChannelEvent {
  /// Controller number (0-127).
  /// Key standard controllers:
  /// - 0: Bank Select MSB
  /// - 1: Modulation Wheel
  /// - 7: Channel Volume
  /// - 10: Pan
  /// - 11: Expression
  /// - 32: Bank Select LSB
  /// - 64: Sustain / Damper Pedal
  /// - 120: All Sound Off
  /// - 121: Reset All Controllers
  /// - 123: All Notes Off
  final int controller;

  /// Controller value (0-127).
  final int value;

  const ControlChangeEvent({
    required super.channel,
    required this.controller,
    required this.value,
    required super.deltaTime,
    required super.absoluteTick,
  });

  /// Whether this is a Sustain / Damper Pedal event (CC 64).
  bool get isSustainPedal => controller == 64;

  /// When [isSustainPedal] is true, indicates whether the pedal is pressed down (value >= 64).
  bool get isSustainOn => isSustainPedal && value >= 64;

  /// Whether this is an All Notes Off event (CC 123 or CC 120).
  bool get isAllNotesOff => controller == 123 || controller == 120;

  @override
  String toString() =>
      'ControlChangeEvent(ch: $channel, cc: $controller, val: $value, tick: $absoluteTick)';
}

/// Program (Patch / Instrument) change event selecting a new instrument for a channel.
class ProgramChangeEvent extends MidiChannelEvent {
  /// Program number (0-127) corresponding to General MIDI preset number.
  final int program;

  const ProgramChangeEvent({
    required super.channel,
    required this.program,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() =>
      'ProgramChangeEvent(ch: $channel, program: $program, tick: $absoluteTick)';
}

/// Channel Pressure (Monophonic Aftertouch) affecting all notes sounding on a channel.
class ChannelPressureEvent extends MidiChannelEvent {
  final int pressure;

  const ChannelPressureEvent({
    required super.channel,
    required this.pressure,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() =>
      'ChannelPressureEvent(ch: $channel, pressure: $pressure, tick: $absoluteTick)';
}

/// Pitch Bend message modifying pitch on a channel.
class PitchBendEvent extends MidiChannelEvent {
  /// Raw 14-bit unsigned pitch bend value (0 to 16383, where 8192 is center / no pitch bend).
  final int value;

  const PitchBendEvent({
    required super.channel,
    required this.value,
    required super.deltaTime,
    required super.absoluteTick,
  });

  /// Signed pitch bend offset (-8192 to +8191, where 0 is center).
  int get signedValue => value - 8192;

  /// Normalized pitch bend ratio from -1.0 (lowest) to +1.0 (highest), with 0.0 at center.
  double get normalized => signedValue / 8192.0;

  @override
  String toString() =>
      'PitchBendEvent(ch: $channel, value: $value ($signedValue), tick: $absoluteTick)';
}

// ---------------------------------------------------------------------------
// Meta Events
// ---------------------------------------------------------------------------

/// Base class for all non-channel MIDI Meta Events (`0xFF`).
abstract class MetaEvent extends MidiEvent {
  const MetaEvent({required super.deltaTime, required super.absoluteTick});
}

/// Sets the tempo in microseconds per quarter note.
class SetTempoEvent extends MetaEvent {
  /// Microseconds per quarter note (e.g. 500,000 corresponds to 120.0 BPM).
  final int microsecondsPerQuarterNote;

  const SetTempoEvent({
    required this.microsecondsPerQuarterNote,
    required super.deltaTime,
    required super.absoluteTick,
  });

  /// Beats per minute (BPM) represented by this tempo.
  double get bpm => 60000000.0 / microsecondsPerQuarterNote;

  @override
  String toString() =>
      'SetTempoEvent(tempo: ${microsecondsPerQuarterNote}us, BPM: ${bpm.toStringAsFixed(1)}, tick: $absoluteTick)';
}

/// Time Signature meta event (e.g. 4/4, 3/4, 6/8).
class TimeSignatureEvent extends MetaEvent {
  final int numerator;
  final int denominator;
  final int clocksPerClick;
  final int thirtySecondsPer24Clocks;

  const TimeSignatureEvent({
    required this.numerator,
    required this.denominator,
    required this.clocksPerClick,
    required this.thirtySecondsPer24Clocks,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() =>
      'TimeSignatureEvent($numerator/$denominator, tick: $absoluteTick)';
}

/// Key Signature meta event (number of sharps/flats and major/minor).
class KeySignatureEvent extends MetaEvent {
  /// Number of sharps (>0) or flats (<0).
  final int sf;

  /// 0 = major, 1 = minor.
  final int mi;

  const KeySignatureEvent({
    required this.sf,
    required this.mi,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() =>
      'KeySignatureEvent(sf: $sf, mode: ${mi == 0 ? "major" : "minor"}, tick: $absoluteTick)';
}

/// Name of the track or sequence.
class TrackNameEvent extends MetaEvent {
  final String text;

  const TrackNameEvent({
    required this.text,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() => 'TrackNameEvent("$text", tick: $absoluteTick)';
}

/// Generic text event.
class TextEvent extends MetaEvent {
  final String text;

  const TextEvent({
    required this.text,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() => 'TextEvent("$text", tick: $absoluteTick)';
}

/// Copyright notice event.
class CopyrightEvent extends MetaEvent {
  final String text;

  const CopyrightEvent({
    required this.text,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() => 'CopyrightEvent("$text", tick: $absoluteTick)';
}

/// Instrument name text event.
class InstrumentNameEvent extends MetaEvent {
  final String text;

  const InstrumentNameEvent({
    required this.text,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() => 'InstrumentNameEvent("$text", tick: $absoluteTick)';
}

/// Lyric text event for karaoke or vocal tracks.
class LyricEvent extends MetaEvent {
  final String text;

  const LyricEvent({
    required this.text,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() => 'LyricEvent("$text", tick: $absoluteTick)';
}

/// Marker event (e.g. "Verse 1", "Chorus").
class MarkerEvent extends MetaEvent {
  final String text;

  const MarkerEvent({
    required this.text,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() => 'MarkerEvent("$text", tick: $absoluteTick)';
}

/// Cue point event.
class CuePointEvent extends MetaEvent {
  final String text;

  const CuePointEvent({
    required this.text,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() => 'CuePointEvent("$text", tick: $absoluteTick)';
}

/// Channel prefix event assigning subsequent meta events to a specific channel.
class ChannelPrefixEvent extends MetaEvent {
  final int channel;

  const ChannelPrefixEvent({
    required this.channel,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() => 'ChannelPrefixEvent(ch: $channel, tick: $absoluteTick)';
}

/// End of track meta event (`0xFF 0x2F 0x00`).
class EndOfTrackEvent extends MetaEvent {
  const EndOfTrackEvent({
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() => 'EndOfTrackEvent(tick: $absoluteTick)';
}

/// Sequencer-specific proprietary meta event.
class SequencerSpecificEvent extends MetaEvent {
  final List<int> data;

  const SequencerSpecificEvent({
    required this.data,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() =>
      'SequencerSpecificEvent(bytes: ${data.length}, tick: $absoluteTick)';
}

/// Unhandled or custom meta event.
class UnknownMetaEvent extends MetaEvent {
  final int metaType;
  final List<int> data;

  const UnknownMetaEvent({
    required this.metaType,
    required this.data,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() =>
      'UnknownMetaEvent(type: 0x${metaType.toRadixString(16)}, bytes: ${data.length}, tick: $absoluteTick)';
}

// ---------------------------------------------------------------------------
// System Exclusive (SysEx) Events
// ---------------------------------------------------------------------------

/// System Exclusive (SysEx) event.
class SysExEvent extends MidiEvent {
  final List<int> data;

  const SysExEvent({
    required this.data,
    required super.deltaTime,
    required super.absoluteTick,
  });

  @override
  String toString() => 'SysExEvent(bytes: ${data.length}, tick: $absoluteTick)';
}
