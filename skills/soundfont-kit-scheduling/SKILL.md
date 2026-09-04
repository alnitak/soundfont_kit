---
name: soundfont_kit-scheduling
version: 1
description: Sample-accurate engine clock scheduling in soundfont_kit — playPresetScheduled, playInstrumentScheduled, playSampleScheduled, stopScheduled, and fadeScheduled. Use when the user asks how to build a MIDI player, metronome, step sequencer, or rhythm game with jitter-free audio timing using SoLoud engine time.
---

# soundfont_kit scheduling

In Flutter, standard Dart `Timer` or `Future.delayed` can drift or jitter by 10–30ms due to garbage collection, widget rendering, and frame drops. For musical applications like **MIDI file sequencers**, **rhythm games**, and **metronomes**, jitter destroys musical timing.

`soundfont_kit` integrates with `flutter_soloud`'s native C++ engine clock to achieve **sample-accurate** audio event scheduling.

---

## 1. The Native Engine Clock

Scheduling is based on `SoLoud.instance.getEngineTime()`, which represents monotonically increasing audio playback time:

```dart
final now = SoLoud.instance.getEngineTime();
final startInOneSec = now + const Duration(seconds: 1);
```

---

## 2. Scheduling Notes (`playPresetScheduled`)

Schedule notes to play at an exact future time on the audio timeline, with optional auto-stop duration:

```dart
// Schedule Middle C to play exactly 500ms in the future and auto-stop after 1.2s:
final startTime = SoLoud.instance.getEngineTime() + const Duration(milliseconds: 500);

final voice = await player.playPresetScheduled(
  preset,
  startTime,
  key: 60,
  velocity: 100,
  duration: const Duration(milliseconds: 1200), // Auto-stops at (startTime + 1.2s)
);
```

You can similarly schedule instruments or raw samples:
- `player.playInstrumentScheduled(instrument, startTime, ...)`
- `player.playSampleScheduled(sample, startTime, ...)`

---

## 3. Scheduled Fades and Stops on `SoundFontVoice`

A scheduled `SoundFontVoice` allows you to schedule subsequent fade-outs or hard stops with sample precision:

```dart
final voice = await player.playPresetScheduled(
  preset,
  startTime,
  key: 64,
  velocity: 90,
);

// Schedule a smooth 300ms fade-out starting 1 second after playback begins:
final fadeStartTime = startTime + const Duration(seconds: 1);
voice.fadeScheduled(
  fadeStartTime,
  to: 0.0,
  time: const Duration(milliseconds: 300),
  thenStop: true, // Automatically frees voice when fade finishes
);

// Or schedule an absolute hard stop:
// voice.stopScheduled(startTime + const Duration(seconds: 2));
```

---

## 4. Building a Jitter-Free Sequencer (Lookahead Pattern)

A robust sequencer uses a periodic Dart timer to schedule events slightly ahead of time (e.g. 200–500ms into the future):

```dart
class MidiTimelinePlayer {
  final SoundFontPlayer player;
  Timer? _timer;
  Duration _playbackCursor = Duration.zero;

  MidiTimelinePlayer(this.player);

  void start(List<MidiNoteEvent> events) {
    final startEngineTime = SoLoud.instance.getEngineTime();

    // Run a lookahead loop every 100ms:
    _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      final currentEngineTime = SoLoud.instance.getEngineTime();
      final elapsed = currentEngineTime - startEngineTime;
      final scheduleWindowEnd = elapsed + const Duration(milliseconds: 300);

      // Find events in the lookahead window:
      final upcoming = events.where((e) =>
        e.timestamp >= _playbackCursor && e.timestamp < scheduleWindowEnd,
      );

      for (final event in upcoming) {
        final noteStartTime = startEngineTime + event.timestamp;
        player.playPresetScheduled(
          event.preset,
          noteStartTime,
          key: event.key,
          velocity: event.velocity,
          duration: event.duration,
        );
      }

      _playbackCursor = scheduleWindowEnd;
    });
  }

  void stop() {
    _timer?.cancel();
    player.allNotesOff();
  }
}
```

---

## Traps & Common Gotchas

- **Scheduling in the Past**: If `startTime < SoLoud.instance.getEngineTime()`, SoLoud clamps or triggers the sound immediately. Always add a positive offset (e.g. 50–200ms) to the current engine time.
- **Clock Source**: Never use `DateTime.now()` or `Stopwatch` as the scheduling reference. Always anchor events to `SoLoud.instance.getEngineTime()`.
- **Enabling Option**: To make unlooped one-shot playback automatically scheduled by default, set `useScheduledPlayback: true` in `SoundFontPlayerOptions`.

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
