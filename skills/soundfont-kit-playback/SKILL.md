---
name: soundfont-kit-playback
version: 1
description: Polyphonic playback, interactive keyboard note-on/note-off, chords, velocity sensitivity, and voice lifecycle management with soundfont_kit and flutter_soloud. Use when the user asks how to play notes, implement a piano keyboard, handle MIDI input, play chords, or stop sounding voices.
---

# soundfont_kit playback & polyphony

`soundfont_kit` pairs parsed SoundFont assets with `flutter_soloud` to provide polyphonic playback with velocity scaling, automatic stereo channel joining, and voice lifecycle management.

---

## 1. Creating a `SoundFontPlayer`

Create a player from an existing `SoundFontFile`:

```dart
final player = sf.createPlayer(
  options: const SoundFontPlayerOptions(
    joinStereoChannels: true,       // Join paired L/R mono samples to stereo
    cacheAudioSources: true,        // Preserve audio buffers in RAM for zero lag
    defaultReleaseDuration: Duration(milliseconds: 150), // Fallback release
    masterVolume: 1.0,              // Master volume scale
    sustainMultiplier: 1.0,         // Authentic SoundFont release envelope
  ),
);
```

---

## 2. Interactive Note-On / Note-Off

For virtual piano keyboards, touch interfaces, or MIDI controller events, use `noteOn` and `noteOff`:

```dart
// Note ON: MIDI key 60 (Middle C), velocity 100 (1..127)
final voice = await player.noteOn(
  preset: preset, // or pass instrument: myInstrument
  key: 60,
  velocity: 100,
);

// Note OFF: fades out the active voice using the release envelope
await player.noteOff(60);

// Stop all sounding notes at once (e.g., panic/clear button)
await player.allNotesOff();
```

### Held-Key Safety
`SoundFontPlayer` tracks held keys internally: if a user taps a key and releases it so quickly that `noteOff` fires *before* the asynchronous `noteOn` sample loading finishes, `SoundFontPlayer` recognizes that the key was already released and immediately fades out the voice without leaving an orphaned ringing note.

---

## 3. Playing Chords & Polyphony

To play chords or polyphonic phrases, trigger multiple `noteOn` calls concurrently:

```dart
// Play a C Major Triad (C4, E4, G4)
final chordKeys = [60, 64, 67];
for (final key in chordKeys) {
  await player.noteOn(preset: preset, key: key, velocity: 90);
}

// Release chord after 1.5 seconds
await Future.delayed(const Duration(milliseconds: 1500));
for (final key in chordKeys) {
  await player.noteOff(key);
}
```

> [!IMPORTANT]
> Always ensure `SoLoud.instance.setMaxActiveVoiceCount(128)` was configured during audio initialization. Playing polyphonic chords with long release tails will quickly exceed the default 16 voices, causing SoLoud to steal or drop notes.

---

## 4. One-Shot Auditioning & Direct Playback

To play a note without tracking it for manual `noteOff` (e.g. for auditioning or sound effects):

```dart
// 1. Play a Preset:
final voice = await player.playPreset(preset, key: 60, velocity: 100);

// 2. Play an Instrument directly:
final voice = await player.playInstrument(sf.instruments.first, key: 60);

// 3. Play a specific raw SampleInfo directly:
final voice = await player.playSample(sf.samples.first, key: 60);

// Release after custom delay:
await Future.delayed(const Duration(seconds: 1));
await voice.release();
```

---

## 5. Controlling Active Voices (`SoundFontVoice`)

Each note trigger returns a `SoundFontVoice` controlling that specific playing instance:

```dart
// Smooth release fade (using envelope duration or custom override):
await voice.release(customRelease: const Duration(milliseconds: 300));

// Immediate abrupt stop:
await voice.stop();

// Inspect voice properties:
print('Key: ${voice.key}, Velocity: ${voice.velocity}');
print('Is released: ${voice.isReleased}');
```

---

## 6. Automatic Stereo Channel Joining

SoundFonts often store stereo instruments as two separate mono samples (one tagged `Left`, one tagged `Right`).

With `joinStereoChannels: true` (default):
- `StereoJoiner` matches linked left and right samples via `sampleLink` or channel naming (`Piano_L` <-> `Piano_R`).
- 16-bit PCM samples are interleaved into a true 2-channel stereo audio stream.
- The voice plays through a single `flutter_soloud` handle with centered balance, halving engine voice consumption and eliminating stereo phase drift.

---

## Traps & Common Gotchas

- **Mismatched Note-Off Key**: `player.noteOff(key)` must match the exact integer MIDI key number passed to `noteOn(..., key: key)`.
- **Preload for Real-Time Performance**: For zero-latency keyboard responses without audio hiccups, call `await player.preloadPreset(preset)` or `await player.preloadAll()` before starting performance.

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
