---
name: soundfont-kit-playback
version: 2
description: Polyphonic playback, synthesis modes (SoLoud Voices vs. Worker-Isolate Realtime Synthesizer), 6-stage DAHDSR envelopes, Exclusive Class voice choking, per-voice resonant filter, and interactive keyboard note-on/note-off with soundfont_kit. Use when the user asks how to play notes, choose a synthesis mode, configure hi-hat choking, implement a piano keyboard, or play chords.
---

# soundfont_kit playback, synthesis modes & polyphony

`soundfont_kit` pairs parsed SoundFont (`.sf2`, `.sf3`, `.sfz`) assets with `flutter_soloud` to provide polyphonic playback with two selectable synthesis modes, full 6-stage DAHDSR volume envelopes, Exclusive Class voice choking, and automatic stereo channel joining.

---

## 1. Creating a `SoundFontPlayer` & Choosing a Synthesis Mode

`SoundFontPlayerOptions` offers two synthesis modes via `SoundFontSynthMode`:

1. **`SoundFontSynthMode.soloudVoices`** *(Default)*: Plays each zone as an individual SoLoud `AudioSource` voice with scheduled 6-stage DAHDSR volume fades (`Delay -> Attack -> Hold -> Decay -> Sustain -> Release`), Exclusive Class (`exclusiveClass` / `off_by`) voice choking, and optional per-voice Biquad resonant low-pass filtering (`enablePerVoiceFilter: true`).
2. **`SoundFontSynthMode.realtimeIsolateSynth`**: Synthesizes all polyphonic voices inside a dedicated high-priority Dart worker isolate (`RealtimeSoundFontSynthesizer` via `SoLoudIsolate` + `RealtimeStreamFeeder`) and pushes mixed stereo `Float32` blocks into a single zero-latency SoLoud `RealtimeStreamHandle`. Includes per-sample 6-stage Volume & Modulation DAHDSR envelopes, Cytomic TPT resonant State-Variable Filter (SVF) with dynamic envelope/LFO cutoff modulation, ModLFO, VibLFO, and zero voice-stealing limits.

```dart
final player = sf.createPlayer(
  options: const SoundFontPlayerOptions(
    synthMode: SoundFontSynthMode.soloudVoices, // or SoundFontSynthMode.realtimeIsolateSynth
    enablePerVoiceFilter: true,                 // Apply SF2/SFZ resonant filter per voice
    enableMixingBus: false,                     // Set true to route player through its own Bus
    joinStereoChannels: true,                   // Join paired L/R mono samples to stereo
    cacheAudioSources: true,                    // Preserve audio buffers in RAM for zero lag
    defaultReleaseDuration: Duration(milliseconds: 150),
    masterVolume: 1.0,
    sustain: 1.0,
  ),
);
```

You can also switch modes dynamically at runtime:
```dart
player.synthMode = SoundFontSynthMode.realtimeIsolateSynth;
```

---

## 2. Interactive Note-On / Note-Off

For virtual piano keyboards, touch interfaces, or MIDI controller events, use `noteOn` and `noteOff`:

```dart
// Note ON: MIDI key 60 (Middle C), velocity 100 (1..127)
final voice = await player.noteOn(
  preset: preset,
  key: 60,
  velocity: 100,
);

// Note OFF: fades out the active voice using the release envelope
await player.noteOff(60);

// Stop all sounding notes at once (e.g., panic/clear button)
await player.allNotesOff();
```

### Exclusive Class / Hi-Hat Choking (`exclusiveClass` / `off_by`)
Both `soloudVoices` and `realtimeIsolateSynth` automatically honor SF2 Generator 57 (`exclusiveClass`) and SFZ `group` / `off_by` opcodes. Triggering a closed hi-hat immediately chokes any open hi-hat in the same exclusive group with a fast 5 ms click-free fade.

---

## 3. Playing Chords & Polyphony

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

---

## 4. Controlling Active Voices (`SoundFontVoice`)

Each note trigger returns a `SoundFontVoice` controlling that specific playing instance:

```dart
// Smooth release fade (using envelope duration or custom override):
await voice.release(customRelease: const Duration(milliseconds: 300));

// Immediate abrupt stop:
await voice.stop();

// Real-time modulation on sounding voices:
voice.applyPitchBend(1.059463); // +1 semitone
voice.applyVolumeMultiplier(0.8);
voice.applyPan(-0.5);
```

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
