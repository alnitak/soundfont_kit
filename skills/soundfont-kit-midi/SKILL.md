---
name: soundfont-kit-midi
version: 1
description: Standard MIDI File (SMF format 0 & 1) parsing, multi-track timeline analysis, and multi-channel playback with MidiReader and MidiPlayer in soundfont_kit. Use when the user asks how to read MIDI files, play .mid/.midi songs, analyze MIDI events or tempo maps, inspect note spans, mute/solo channels, change playback speed, seek, loop, or render piano rolls and MIDI visualizers.
---

# soundfont_kit MIDI playback & analysis

`soundfont_kit` includes a built-in Standard MIDI File (**SMF format 0 and 1**) parser, timeline analyzer, and multi-channel sequencer engine that drives polyphonic audio playback via `SoundFontPlayer` and `flutter_soloud`.

---

## 1. Core Architecture

The MIDI subsystem is organized into three distinct layers:

1. **`MidiReader`**: Decodes raw binary `.mid` / `.midi` data into structured tracks, delta-tick events, and meta-messages.
2. **`MidiTimeline`**: Analyzes all tracks, computes the dynamic tempo map (BPM changes), translates tick offsets into absolute microsecond timestamps, and precalculates note durations (`MidiNoteSpan`).
3. **`MidiPlayer`**: High-level transport and sequencer engine managing 16 independent channel states, sample-accurate event scheduling, loop points, seeking, speed adjustments, and channel mixing (volume, pan, mute, solo).

---

## 2. Parsing a MIDI File (`MidiReader`)

Load and parse a Standard MIDI File from a file or byte array:

```dart
import 'dart:io';
import 'package:soundfont_kit/soundfont_kit.dart';

// From a file on disk:
final midiFile = await MidiReader.fromFile(File('path/to/song.mid'));

// Or from raw bytes (e.g. Flutter asset or network download):
final midiFile = MidiReader.fromBytes(byteData);

print('Format: ${midiFile.formatName}'); // SMF 0 or SMF 1
print('Tracks: ${midiFile.numTracks}');
print('Time Division: ${midiFile.division} ticks/quarter-note');
```

---

## 3. Analyzing the Timeline & Note Spans (`MidiTimeline`)

`MidiTimeline` unifies multi-track delta-ticks into an absolute-time timeline with microsecond precision:

```dart
final timeline = MidiTimeline.fromFile(midiFile);

print('Duration: ${timeline.duration.inSeconds}s');
print('Total Notes: ${timeline.totalNotes}');
print('Initial BPM: ${timeline.initialTempoBpm}');
print('Used Channels: ${timeline.usedChannels}'); // e.g. [0, 1, 9]

// Inspect note spans for building a piano roll or visualizer:
for (final span in timeline.noteSpans) {
  print('Ch ${span.channel}: note ${span.noteNumber} (vel ${span.velocity}) '
        'from ${span.startOffset.inMilliseconds}ms to ${span.endOffset.inMilliseconds}ms');
}

// Or inspect per channel:
final pianoNotes = timeline.noteSpansByChannel[0] ?? [];
```

Each `MidiNoteSpan` contains:
- `channel`: 0-indexed MIDI channel (0..15).
- `noteNumber`: MIDI key number (0..127, where 60 is Middle C).
- `velocity`: Note-on velocity (1..127).
- `startOffset` & `endOffset`: Absolute `Duration` from timeline origin.
- `duration`: Calculated note length (`endOffset - startOffset`).

---

## 4. Setting Up Playback (`MidiPlayer`)

Pair a `SoundFontPlayer` with `MidiPlayer` to synthesize multi-track MIDI playback:

```dart
// 1. Initialize SoundFont and synthesis player
final sf = await SoundFontFile.fromFile('assets/soundfonts/GeneralUser.sf2');
final sfPlayer = sf.createPlayer();

// 2. Create the MidiPlayer
final midiPlayer = MidiPlayer(player: sfPlayer);

// 3. Load the parsed MIDI file (autoPreload caches required presets in RAM)
await midiPlayer.load(midiFile, autoPreload: true);

// 4. Start playback
await midiPlayer.play();
```

---

## 5. Transport Controls: Play, Pause, Seek, Speed, and Loop

Control playback state and timing dynamically:

```dart
// Pause playback (silences active voices while retaining current position)
await midiPlayer.pause();

// Resume playback
await midiPlayer.play();

// Seek to a specific position
await midiPlayer.seek(const Duration(seconds: 45));

// Stop and reset playback head to zero
await midiPlayer.stop();

// Toggle automatic looping from start upon reaching the end
midiPlayer.looping = true;

// A-B region looping (loops seamlessly between specified start and end timestamps)
midiPlayer.setLoopRange(const Duration(seconds: 10), const Duration(seconds: 25));
// To clear the A-B loop:
midiPlayer.clearLoopRange();

// Adjust playback speed (0.1x to 10.0x, seamless wall-clock re-anchoring)
midiPlayer.speedMultiplier = 1.25; // 25% faster

// Override tempo to a fixed BPM regardless of internal MIDI tempo changes:
midiPlayer.overrideBpm = 120.0; // Set to null to restore original tempo map

// Global pitch transposition (in semitones, e.g. +2 = whole step up).
// Drum channel (Channel 10 / index 9) is automatically preserved without pitch shifting!
midiPlayer.transpose = 2;
```

---

## 6. Multi-Channel Mixing & Track Control

`MidiPlayer` exposes 16 independent channel states (`channels[0..15]`) and per-track isolation:

```dart
// Per-channel mute and solo:
midiPlayer.setChannelMute(0, true);
midiPlayer.setChannelSolo(9, true);

// Per-track mute and solo (SMF Format 1 multi-track files):
midiPlayer.setTrackMute(2, true);
midiPlayer.setTrackSolo(3, true);

// Adjust channel volume (0.0 to 1.0)
midiPlayer.setChannelVolume(0, 0.75);

// Adjust channel pan (-1.0 left to +1.0 right)
midiPlayer.setChannelPan(0, -0.5);

// Channel-specific transposition:
midiPlayer.channels[0].transpose = -12; // 1 octave down for bass channel

// Reassign a channel to play using a different SoundFont preset:
midiPlayer.setChannelPreset(0, myCustomPreset);

// Global override: force ALL channels to play using one preset (e.g. Solo Piano):
midiPlayer.forcedPresetOverride = sf.presets.first;
```

---

## 7. Expressive MIDI Controllers & Modulation

`MidiPlayer` processes expressive MIDI messages and automates active voices in real time:

- **Pitch Bend**: Smoothly modulates active voice playback speed on sounding voices with dynamic 14-bit pitch wheel curves.
- **CC 1 Modulation Wheel**: Dynamically binds to `flutter_soloud`'s `amplitudeModulatorFilter` (LFO tremolo/vibrato depth) when active.
- **CC 7 Volume, CC 10 Pan & CC 11 Expression**: Continuously scales gain and stereo placement of active and upcoming voices.
- **CC 64 Sustain & CC 66 Sostenuto**: Sustains all sounding notes (CC 64) or selectively locks notes held at the pedal-down moment (CC 66).
- **CC 67 Soft Pedal (Una Corda)**: Applies dynamic volume reduction for gentle, muted passages.
- **CC 0 & CC 32 Bank Select**: Selects instrument sound banks (MSB & LSB).
- **CC 120 All Sound Off & CC 121 Reset All Controllers**: Immediately silences ringing voices or restores default controller states.

---

## 8. Synchronized Lyrics & Chord Detection

`MidiPlayer` and `MidiTimeline` provide out-of-the-box support for karaoke, sing-along, and music learning apps:

### Synchronized Lyrics Stream
```dart
// Check if the loaded file contains lyrics or markers
if (midiPlayer.timeline?.hasLyrics ?? false) {
  print('Full lyrics:\n${midiPlayer.timeline?.fullLyricsText}');
}

// Subscribe to lyrics and markers as playback progresses
final lyricSub = midiPlayer.lyricStream.listen((MidiLyricSpan span) {
  print('[${span.type.name}] ${span.text} at ${span.timestamp.inMilliseconds}ms');
});
```

### Real-Time Chord Detection
Detect active harmonies automatically using `ChordDetector`:

```dart
// Listen to chord changes in real-time during playback
final chordSub = midiPlayer.chordStream.listen((String? chordName) {
  if (chordName != null) {
    print('Current Chord: $chordName'); // e.g. "C", "Am7", "G/B"
  }
});

// Or detect chords manually from any set of MIDI note numbers:
final chord = ChordDetector.detectChord([60, 64, 67]); // "C"
final inversion = ChordDetector.detectChord([64, 67, 72]); // "C/E"
```

---

## 9. Subscribing to Playback Streams

Keep UI elements, timeline playheads, and keyboard key lights synchronized:

```dart
// Stream current playback position:
final posSub = midiPlayer.positionStream.listen((Duration position) {
  print('Position: ${position.inMilliseconds}ms / ${midiPlayer.duration.inMilliseconds}ms');
});

// Stream real-time playback events (noteOn, noteOff, programChange, etc.):
final eventSub = midiPlayer.eventStream.listen((MidiPlaybackEvent event) {
  if (event.type == MidiPlaybackEventType.noteOn) {
    print('Note ON: Ch ${event.channel} Key ${event.note} Vel ${event.velocity}');
  } else if (event.type == MidiPlaybackEventType.noteOff) {
    print('Note OFF: Ch ${event.channel} Key ${event.note}');
  }
});
```

Remember to cancel subscriptions and call `midiPlayer.dispose()` when finished.

---

## 10. General MIDI (GM) Helpers

Use the `GeneralMidi` utility to resolve standard instrument names and categories:

```dart
// Resolve GM program number (0..127) to instrument name and category:
final name = GeneralMidi.nameOf(0);         // "Acoustic Grand Piano"
final category = GeneralMidi.categoryOf(0); // "Piano"

// Resolve GM percussion note number for Channel 10:
final drum = GeneralMidi.percussionNameOf(36); // "Bass Drum 1"
```

---

## Traps & Common Gotchas

- **0-Indexed vs 1-Indexed Channels**: Standard MIDI specifications describe channels as 1–16, but `MidiPlayer` uses standard 0-indexed indices `0..15`. Standard Drum Channel 10 is index `9`.
- **Set Max Voice Count**: Always ensure `SoLoud.instance.setMaxActiveVoiceCount(128)` was configured during audio initialization. Complex multi-track MIDI arrangements easily exceed the default 16 voices.
- **Always Preload Samples**: Pass `autoPreload: true` in `midiPlayer.load()` to avoid latency and audio hiccups when new instruments are first triggered during playback.
- **Accurate Durations**: `MidiTimeline` automatically calculates musical duration based on actual note events, avoiding misleadingly long song lengths caused by trailing non-note metadata or dummy control changes.

---

## Keeping this skill current

Check whether installed skills are up to date:
```bash
dart run soundfont_kit:skills --check
```
Install or update skills:
```bash
dart run soundfont_kit:skills
```
