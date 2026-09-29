import 'midi_lyrics.dart';
import 'midi_models.dart';

/// Represents a single tempo change point in musical time.
class TempoChange {
  /// Absolute tick when this tempo starts.
  final int tick;

  /// Microseconds per quarter note.
  final int microsecondsPerQuarterNote;

  /// Elapsed microsecond timestamp from the start of the piece when this tempo begins.
  final int startMicroseconds;

  const TempoChange({
    required this.tick,
    required this.microsecondsPerQuarterNote,
    required this.startMicroseconds,
  });

  /// Tempo in Beats Per Minute (BPM).
  double get bpm => 60000000.0 / microsecondsPerQuarterNote;
}

/// Converts musical ticks to absolute real-world time (and vice versa) taking into
/// account initial tempo and all intermediate `SetTempoEvent` changes.
class TempoMap {
  final int ppq;
  final List<TempoChange> tempoChanges;

  TempoMap({
    required this.ppq,
    required this.tempoChanges,
  });

  /// Constructs a [TempoMap] from all tracks in a [MidiFile].
  factory TempoMap.fromMidiFile(MidiFile file) {
    final ppq = file.ticksPerQuarterNote;

    // Collect all SetTempoEvents across all tracks
    final tempoEvents = <SetTempoEvent>[];
    for (final track in file.tracks) {
      for (final event in track.events) {
        if (event is SetTempoEvent) {
          tempoEvents.add(event);
        }
      }
    }

    // Sort by absolute tick
    tempoEvents.sort((a, b) => a.absoluteTick.compareTo(b.absoluteTick));

    // Remove duplicates at the same tick (keep last)
    final uniqueEvents = <SetTempoEvent>[];
    for (final e in tempoEvents) {
      if (uniqueEvents.isNotEmpty &&
          uniqueEvents.last.absoluteTick == e.absoluteTick) {
        uniqueEvents.removeLast();
      }
      uniqueEvents.add(e);
    }

    final changes = <TempoChange>[];
    int currentTempo = 500000; // Default 120 BPM (500,000 us/quarter note)
    int lastTick = 0;
    int accumulatedUs = 0;

    if (uniqueEvents.isEmpty || uniqueEvents.first.absoluteTick > 0) {
      changes.add(
        TempoChange(
          tick: 0,
          microsecondsPerQuarterNote: currentTempo,
          startMicroseconds: 0,
        ),
      );
    }

    for (final e in uniqueEvents) {
      final deltaTicks = e.absoluteTick - lastTick;
      if (deltaTicks > 0) {
        accumulatedUs += ((deltaTicks * currentTempo) / ppq).round();
      }
      currentTempo = e.microsecondsPerQuarterNote;
      lastTick = e.absoluteTick;

      changes.add(
        TempoChange(
          tick: e.absoluteTick,
          microsecondsPerQuarterNote: currentTempo,
          startMicroseconds: accumulatedUs,
        ),
      );
    }

    return TempoMap(ppq: ppq, tempoChanges: changes);
  }

  /// Converts an absolute tick number to a real-time [Duration].
  Duration tickToDuration(int tick) {
    if (tick <= 0 || tempoChanges.isEmpty) return Duration.zero;

    // Find the active tempo change interval
    TempoChange activeChange = tempoChanges.first;
    for (int i = 0; i < tempoChanges.length; i++) {
      if (tempoChanges[i].tick <= tick) {
        activeChange = tempoChanges[i];
      } else {
        break;
      }
    }

    final deltaTicks = tick - activeChange.tick;
    final usFromActive =
        ((deltaTicks * activeChange.microsecondsPerQuarterNote) / ppq).round();
    return Duration(microseconds: activeChange.startMicroseconds + usFromActive);
  }

  /// Converts a real-time [Duration] to the corresponding absolute tick.
  int durationToTick(Duration duration) {
    final targetUs = duration.inMicroseconds;
    if (targetUs <= 0 || tempoChanges.isEmpty) return 0;

    TempoChange activeChange = tempoChanges.first;
    for (int i = 0; i < tempoChanges.length; i++) {
      if (tempoChanges[i].startMicroseconds <= targetUs) {
        activeChange = tempoChanges[i];
      } else {
        break;
      }
    }

    final deltaUs = targetUs - activeChange.startMicroseconds;
    final deltaTicks =
        ((deltaUs * ppq) / activeChange.microsecondsPerQuarterNote).round();
    return activeChange.tick + deltaTicks;
  }

  /// Returns the active tempo in BPM at the given [tick].
  double getBpmAtTick(int tick) {
    TempoChange activeChange = tempoChanges.first;
    for (int i = 0; i < tempoChanges.length; i++) {
      if (tempoChanges[i].tick <= tick) {
        activeChange = tempoChanges[i];
      } else {
        break;
      }
    }
    return activeChange.bpm;
  }
}

/// Represents a MIDI event positioned at an exact absolute real-world timestamp.
class TimedMidiEvent {
  /// The underlying parsed MIDI event.
  final MidiEvent event;

  /// Index of the track this event originated from.
  final int trackIndex;

  /// Absolute musical tick position from the start of the sequence.
  final int absoluteTick;

  /// Real-world timestamp calculated from the [TempoMap].
  final Duration timestamp;

  const TimedMidiEvent({
    required this.event,
    required this.trackIndex,
    required this.absoluteTick,
    required this.timestamp,
  });

  @override
  String toString() =>
      'TimedMidiEvent(t: ${timestamp.inMilliseconds}ms, tick: $absoluteTick, event: $event)';
}

/// Represents a sounding note spanning from [start] to [start] + [duration] on a MIDI [channel].
class MidiTimelineNote {
  /// The 0-based MIDI channel (0-15).
  final int channel;

  /// The MIDI note number (0-127).
  final int note;

  /// Note-on velocity (1-127).
  final int velocity;

  /// Real-world start timestamp.
  final Duration start;

  /// Duration the note sounds before NoteOff.
  final Duration duration;

  /// Real-world end timestamp.
  Duration get end => start + duration;

  const MidiTimelineNote({
    required this.channel,
    required this.note,
    required this.velocity,
    required this.start,
    required this.duration,
  });

  @override
  String toString() =>
      'MidiTimelineNote(ch: $channel, note: $note, vel: $velocity, start: ${start.inMilliseconds}ms, dur: ${duration.inMilliseconds}ms)';
}

/// Snapshot of the synthesizer state across all 16 MIDI channels at a specific point in time.
class MidiChannelSnapshot {
  final int channel;
  int bank;
  int program;
  int volume;
  int pan;
  int expression;
  int pitchBend;
  bool isSustainPedalOn;

  MidiChannelSnapshot({
    required this.channel,
    this.bank = 0,
    this.program = 0,
    this.volume = 100,
    this.pan = 64, // Center
    this.expression = 127,
    this.pitchBend = 8192, // Center / 0 bend
    this.isSustainPedalOn = false,
  });

  MidiChannelSnapshot clone() => MidiChannelSnapshot(
    channel: channel,
    bank: bank,
    program: program,
    volume: volume,
    pan: pan,
    expression: expression,
    pitchBend: pitchBend,
    isSustainPedalOn: isSustainPedalOn,
  );
}

/// Unified timeline merging all tracks of a [MidiFile] into a sorted chronological sequence.
class MidiTimeline {
  /// The original MIDI file.
  final MidiFile file;

  /// The tempo mapping engine.
  final TempoMap tempoMap;

  /// Chronologically ordered list of all timed events across all tracks.
  final List<TimedMidiEvent> events;

  /// Total duration of the MIDI sequence.
  final Duration duration;

  /// Chronologically ordered list of all timed lyrics and text markers.
  final List<MidiLyricSpan> lyrics;

  /// Precomputed notes partitioned by 0-based MIDI channel (0-15).
  final Map<int, List<MidiTimelineNote>> channelNotes;

  const MidiTimeline({
    required this.file,
    required this.tempoMap,
    required this.events,
    required this.duration,
    this.lyrics = const [],
    this.channelNotes = const {},
  });

  /// Whether this timeline contains synchronized song lyrics.
  bool get hasLyrics => lyrics.any((l) => l.type == MidiLyricType.lyric);

  /// Complete text of all lyric syllables joined sequentially.
  String get fullLyricsText => lyrics
      .where((l) => l.type == MidiLyricType.lyric)
      .map((l) => l.text)
      .join();

  /// The set of 0-based MIDI channels (0-15) used in the underlying MIDI file.
  Set<int> get usedChannels => file.usedChannels;

  /// Returns all paired notes (with start and duration) for the given [channel] (0-15).
  List<MidiTimelineNote> getNotesForChannel(int channel) =>
      channelNotes[channel] ?? const [];

  /// Constructs a flattened [MidiTimeline] from [file].
  factory MidiTimeline.fromMidiFile(MidiFile file) {
    final tempoMap = TempoMap.fromMidiFile(file);
    final allTimedEvents = <TimedMidiEvent>[];
    final allLyrics = <MidiLyricSpan>[];

    for (int tIdx = 0; tIdx < file.tracks.length; tIdx++) {
      final track = file.tracks[tIdx];
      for (final event in track.events) {
        final time = tempoMap.tickToDuration(event.absoluteTick);
        allTimedEvents.add(
          TimedMidiEvent(
            event: event,
            trackIndex: tIdx,
            absoluteTick: event.absoluteTick,
            timestamp: time,
          ),
        );

        if (event is LyricEvent) {
          allLyrics.add(
            MidiLyricSpan(
              timestamp: time,
              text: event.text,
              type: MidiLyricType.lyric,
              trackIndex: tIdx,
              absoluteTick: event.absoluteTick,
            ),
          );
        } else if (event is TextEvent) {
          allLyrics.add(
            MidiLyricSpan(
              timestamp: time,
              text: event.text,
              type: MidiLyricType.text,
              trackIndex: tIdx,
              absoluteTick: event.absoluteTick,
            ),
          );
        } else if (event is MarkerEvent) {
          allLyrics.add(
            MidiLyricSpan(
              timestamp: time,
              text: event.text,
              type: MidiLyricType.marker,
              trackIndex: tIdx,
              absoluteTick: event.absoluteTick,
            ),
          );
        } else if (event is CuePointEvent) {
          allLyrics.add(
            MidiLyricSpan(
              timestamp: time,
              text: event.text,
              type: MidiLyricType.cuePoint,
              trackIndex: tIdx,
              absoluteTick: event.absoluteTick,
            ),
          );
        }
      }
    }

    allLyrics.sort((a, b) {
      final cmp = a.timestamp.compareTo(b.timestamp);
      if (cmp != 0) return cmp;
      return a.absoluteTick.compareTo(b.absoluteTick);
    });

    // Sort chronologically by timestamp, maintaining event priority at simultaneous timestamps
    // Priority order: SetTempo / Meta -> ProgramChange / CC -> NoteOff -> NoteOn
    allTimedEvents.sort((a, b) {
      final cmp = a.timestamp.compareTo(b.timestamp);
      if (cmp != 0) return cmp;

      // Secondary sort: tick
      final tickCmp = a.absoluteTick.compareTo(b.absoluteTick);
      if (tickCmp != 0) return tickCmp;

      // Event type priority for simultaneous events
      return _eventPriority(a.event).compareTo(_eventPriority(b.event));
    });

    // Track active sounding notes across channels to identify musical end and prune orphan NoteOffs.
    final activeNotes = <int, Set<int>>{};
    final activeNoteStarts = <int, Map<int, (Duration start, int velocity)>>{};
    final channelNotes = <int, List<MidiTimelineNote>>{};
    for (int ch = 0; ch < 16; ch++) {
      activeNotes[ch] = <int>{};
      activeNoteStarts[ch] = <int, (Duration, int)>{};
      channelNotes[ch] = <MidiTimelineNote>[];
    }

    Duration lastActiveNoteEnd = Duration.zero;
    bool hasNotes = false;
    final cleanEvents = <TimedMidiEvent>[];

    for (final te in allTimedEvents) {
      final ev = te.event;
      if (ev is NoteOnEvent) {
        if (ev.velocity > 0) {
          hasNotes = true;
          activeNotes[ev.channel]!.add(ev.note);
          activeNoteStarts[ev.channel]![ev.note] = (te.timestamp, ev.velocity);
          if (te.timestamp > lastActiveNoteEnd) {
            lastActiveNoteEnd = te.timestamp;
          }
          cleanEvents.add(te);
        } else {
          // Note off via NoteOn with vel 0
          if (activeNotes[ev.channel]!.remove(ev.note)) {
            final startInfo = activeNoteStarts[ev.channel]!.remove(ev.note);
            if (startInfo != null) {
              var dur = te.timestamp - startInfo.$1;
              if (dur <= Duration.zero) dur = const Duration(milliseconds: 20);
              channelNotes[ev.channel]!.add(MidiTimelineNote(
                channel: ev.channel,
                note: ev.note,
                velocity: startInfo.$2,
                start: startInfo.$1,
                duration: dur,
              ));
            }
            if (te.timestamp > lastActiveNoteEnd) {
              lastActiveNoteEnd = te.timestamp;
            }
            cleanEvents.add(te);
          }
          // Note: orphan NoteOff (note not currently sounding) is dropped
        }
      } else if (ev is NoteOffEvent) {
        if (activeNotes[ev.channel]!.remove(ev.note)) {
          final startInfo = activeNoteStarts[ev.channel]!.remove(ev.note);
          if (startInfo != null) {
            var dur = te.timestamp - startInfo.$1;
            if (dur <= Duration.zero) dur = const Duration(milliseconds: 20);
            channelNotes[ev.channel]!.add(MidiTimelineNote(
              channel: ev.channel,
              note: ev.note,
              velocity: startInfo.$2,
              start: startInfo.$1,
              duration: dur,
            ));
          }
          if (te.timestamp > lastActiveNoteEnd) {
            lastActiveNoteEnd = te.timestamp;
          }
          cleanEvents.add(te);
        }
        // Note: orphan NoteOff is dropped
      } else {
        cleanEvents.add(te);
      }
    }

    Duration totalDuration;
    if (!hasNotes) {
      totalDuration =
          cleanEvents.isNotEmpty ? cleanEvents.last.timestamp : Duration.zero;
    } else {
      // Allow a reasonable grace window (up to 4 seconds) after the last active note off
      // for CC releases (e.g. sustain pedal), final lyrics, or EndOfTrack markers.
      const maxGrace = Duration(seconds: 4);
      totalDuration = lastActiveNoteEnd;

      for (final te in cleanEvents) {
        if (te.timestamp <= lastActiveNoteEnd) continue;
        if (te.timestamp > lastActiveNoteEnd + maxGrace) break;

        final ev = te.event;
        if (ev is ControlChangeEvent ||
            ev is PitchBendEvent ||
            ev is EndOfTrackEvent ||
            ev is LyricEvent ||
            ev is MarkerEvent) {
          if (te.timestamp > totalDuration) {
            totalDuration = te.timestamp;
          }
        }
      }
    }

    // Close any notes that were left sounding at the end of the timeline
    for (int ch = 0; ch < 16; ch++) {
      for (final entry in activeNoteStarts[ch]!.entries) {
        var dur = totalDuration - entry.value.$1;
        if (dur <= Duration.zero) dur = const Duration(milliseconds: 20);
        channelNotes[ch]!.add(MidiTimelineNote(
          channel: ch,
          note: entry.key,
          velocity: entry.value.$2,
          start: entry.value.$1,
          duration: dur,
        ));
      }
      channelNotes[ch]!.sort((a, b) => a.start.compareTo(b.start));
    }

    // Retain only events up to totalDuration, pruning runaway trailing silence/padding
    final finalEvents = hasNotes
        ? cleanEvents.where((e) => e.timestamp <= totalDuration).toList()
        : cleanEvents;

    return MidiTimeline(
      file: file,
      tempoMap: tempoMap,
      events: finalEvents,
      duration: totalDuration,
      lyrics: allLyrics,
      channelNotes: channelNotes,
    );
  }

  /// Calculates the channel controller and program snapshot at [timestamp] (State Chasing).
  ///
  /// Also returns the index of the first event occurring strictly at or after [timestamp].
  (Map<int, MidiChannelSnapshot>, int) getSnapshotAt(Duration timestamp) {
    final snapshots = <int, MidiChannelSnapshot>{};
    for (int ch = 0; ch < 16; ch++) {
      snapshots[ch] = MidiChannelSnapshot(
        channel: ch,
        bank: ch == 9 ? 128 : 0, // Channel 10 (index 9) defaults to percussion bank
      );
    }

    int nextEventIndex = events.length;
    for (int i = 0; i < events.length; i++) {
      if (events[i].timestamp >= timestamp) {
        nextEventIndex = i;
        break;
      }
    }

    for (int i = 0; i < events.length; i++) {
      final timed = events[i];
      if (timed.timestamp > timestamp) {
        break;
      }

      final event = timed.event;
      if (event is ProgramChangeEvent) {
        snapshots[event.channel]?.program = event.program;
      } else if (event is ControlChangeEvent) {
        final state = snapshots[event.channel];
        if (state != null) {
          switch (event.controller) {
            case 0: // Bank Select MSB
              state.bank = event.value;
              break;
            case 7: // Channel Volume
              state.volume = event.value;
              break;
            case 10: // Pan
              state.pan = event.value;
              break;
            case 11: // Expression
              state.expression = event.value;
              break;
            case 64: // Sustain Pedal
              state.isSustainPedalOn = event.value >= 64;
              break;
            case 121: // Reset All Controllers
              state.expression = 127;
              state.pitchBend = 8192;
              state.isSustainPedalOn = false;
              break;
          }
        }
      } else if (event is PitchBendEvent) {
        snapshots[event.channel]?.pitchBend = event.value;
      }
    }

    return (snapshots, nextEventIndex);
  }

  static int _eventPriority(MidiEvent e) {
    if (e is SetTempoEvent) return 0;
    if (e is MetaEvent) return 1;
    if (e is ControlChangeEvent && (e.controller == 0 || e.controller == 32)) return 2; // Bank Select
    if (e is ProgramChangeEvent) return 3;
    if (e is ControlChangeEvent) return 4;
    if (e is NoteOffEvent || (e is NoteOnEvent && e.isNoteOff)) return 5;
    if (e is NoteOnEvent) return 6;
    return 7;
  }
}
