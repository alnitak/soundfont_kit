# SoundFont Kit

A high-performance, pure Dart reader and playback engine for SoundFont files (**SF2**, **SF3**, and **SFZ**), powered by the [flutter_soloud](https://pub.dev/packages/flutter_soloud) low-latency audio engine.

---

## Features

- See [***web example***](https://marcobavagnoli.com/soundfont/)
- See [***piano 3D***](https://marcobavagnoli.com/piano_3d) web example which uses [flutter_scene](https://pub.dev/packages/flutter_scene)
- **Multi-Format Support**:
  - **SF2** (SoundFont 2.04) — Full RIFF/sfbk parser (presets, instruments, zones, generators, modulators, and 16-bit PCM samples).
  - **SF3** (SoundFont 3.0) — OGG Vorbis compressed sample streams with sub-chunk header extraction.
  - **SFZ** (SFZ Instrument Definitions) — Parses opcode definitions and links to external `.wav`, `.flac`, or `.ogg` audio files.
  - **Compressed Archives** — Transparently loads compressed archives (`.zip`, `.gz`, `.bz2`, `.tar`, `.tgz`, `.tbz2`) containing SoundFonts and loose sample hierarchies.
- **Flexible Data Sources**:
  - Load from Flutter Assets (`SoundFontFile.fromAsset`).
  - Load from Local Disk (`SoundFontFile.fromFile`).
  - Load from In-Memory Byte Buffers (`SoundFontFile.fromBytes`).
  - Load from Remote HTTP URLs (`SoundFontFile.fromUrl`).
- **High-Performance Audio Playback with `flutter_soloud`**:
  - **Sample-Accurate Scheduling** using `playScheduled`, `fadeScheduled`, and `stopScheduled` on the native engine clock.
  - **Real-Time Synthesis**: Pitch calculation, root key tracking, key-to-pitch scaling, MIDI velocity sensitivity, attenuation, panning, and loop points.
  - **Stereo Channel Joining**: Automatically interleaves paired Left and Right 16-bit PCM channels into true 2-channel stereo streams with centered mixer balance.
  - **Dynamic Sustain & Release Control**:
    - **Native Sustain Multiplier (`sustainMultiplier`)**: Scales the instrument's authentic SoundFont envelope (`0.0x` to `10.0x`, with `1.0x` = exact SoundFont value).
    - **Fallback Sustain Time (`sustainTime`)**: Configures manual release fade-out duration (e.g. `0.05s` to `5.0s`) for instruments or samples lacking a native release envelope.
    - **Instant Release (`0.0x`)**: Cut off sound immediately upon key release.
  - **Polyphonic Voice Lifecycle**: Manage note-on/note-off, chords, and polyphonic voice pools.
- **Sample Preloading**:
  - Preload all samples into memory upfront (`preloadAll`) for instant zero-latency playback, or stream them on-demand.
  - Granular preloading per preset (`preloadPreset`) or per instrument (`preloadInstrument`) with real-time progress callbacks.
- **Global Audio DSP Filters**:
  - Built-in manager (`SoundFontGlobalFilters`) for `flutter_soloud` effects: **Freeverb**, **Echo/Delay**, **Biquad Resonant Filter**, **Flanger**, **Bass Boost**, **Lo-Fi**, and **Wave Shaper**.

---

## Getting Started

Add `soundfont_kit` and `flutter_soloud` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  soundfont_kit: ^1.0.0
  flutter_soloud: ^3.0.0
```

Initialize the `flutter_soloud` audio engine prior to playback (e.g. in your `main()` function):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:soundfont_kit/soundfont_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the SoLoud audio engine
  await SoLoud.instance.init();
  SoLoud.instance.setMaxActiveVoiceCount(128);

  runApp(const MyApp());
}
```

---

## AI Agent Skills

`soundfont_kit` includes bundled **Agent Skills** (`SKILL.md` instruction files) to help AI coding agents (Claude, Cursor, Gemini, GitHub Copilot, Cline, Codex, OpenCode, etc.) generate correct, high-performance code for all features and functionalities of this package.

Install or update the skills in your project by running:

```bash
dart run soundfont_kit:skills
```

To check whether installed skills are up to date without modifying any files:

```bash
dart run soundfont_kit:skills --check
```

---

## Usage Guide

### 1. Loading a SoundFont File

You can load a SoundFont from various sources. The format (`sf2`, `sf3`, `sfz`, or compressed archive) is automatically detected:

```dart
// From Flutter assets:
final sf = await SoundFontFile.fromAsset('assets/soundfonts/GeneralUser.sf2');

// From local file on disk:
final sf = await SoundFontFile.fromFile('/path/to/piano.sf3');

// From a zipped SFZ archive containing samples:
final sf = await SoundFontFile.fromFile('/path/to/celesta_sfz.zip');

// From in-memory bytes (e.g. from file picker or network):
final sf = await SoundFontFile.fromBytes(bytes, basePath: 'my_font.sf2');

// From remote HTTP URL:
final sf = await SoundFontFile.fromUrl('https://example.com/soundfonts/instrument.sf2');
```

---

### 2. Inspecting SoundFont Metadata

Access all parsed presets, instruments, zones, and audio samples:

```dart
print('SoundFont Name: ${sf.name}');
print('Format: ${sf.format.name}');
print('Total Presets: ${sf.presets.length}');
print('Total Instruments: ${sf.instruments.length}');
print('Total Samples: ${sf.samples.length}');

// Iterate over presets
for (final preset in sf.presets) {
  print('Preset [${preset.bank}:${preset.program}] ${preset.name}');
}
```

---

### 3. Playing Presets and Instruments

Create a `SoundFontPlayer` to play presets, instruments, or raw samples:

```dart
// Create the player instance
final player = sf.createPlayer(
  options: const SoundFontPlayerOptions(
    joinStereoChannels: true,       // Join paired L/R mono samples to stereo
    cacheAudioSources: true,        // Preserve audio buffers in RAM
    useScheduledPlayback: true,     // Use sample-accurate engine clock
    sustainMultiplier: 1.0,         // 1.0x = authentic SoundFont envelope
    sustainTime: 0.20,              // 200ms fallback for items without release
  ),
);

// Play a preset by note number (MIDI Key: 60 = Middle C) and velocity (1..127)
final preset = sf.presets.first;
final voice = await player.playPreset(
  preset,
  key: 60,
  velocity: 100,
);

// Release the note after 1.5 seconds (triggers release envelope)
await Future.delayed(const Duration(milliseconds: 1500));
await voice.release();
```

---

### 4. Sustain and Release Modes

The player provides two complementary modes for controlling sustain/release:

```dart
// 1. Multiplier Mode (for instruments WITH native release envelopes)
// Scale the instrument's authentic SoundFont release time up or down:
player.sustainMultiplier = 1.0;  // 100% native SoundFont release
player.sustainMultiplier = 2.5;  // Extended sustain (like a sustain pedal)
player.sustainMultiplier = 0.0;  // Staccato (instant cutoff on key release)

// 2. Time Mode (for instruments/samples WITHOUT native release)
// Sets explicit fade-out duration in seconds:
player.sustainTime = 0.5;        // 500ms fade-out upon note release
```

---

### 5. Interactive Keyboard & Polyphony

Manage polyphonic notes and chords with `noteOn` and `noteOff`:

```dart
// Note ON: triggers preset playback and tracks active voices
final voice = await player.noteOn(
  preset: preset,
  key: 64, // E4
  velocity: 110,
);

// Note OFF: fades out smoothly using the voice's release envelope
await player.noteOff(64);

// Or stop all playing notes at once:
await player.allNotesOff();
```

---

### 6. Sample Preloading

To eliminate I/O and streaming overhead during real-time performance, you can preload samples into memory:

```dart
// Preload all samples in the soundfont with a live progress callback:
await player.preloadAll(
  onProgress: (progress, loaded, total) {
    print('Preloading: ${(progress * 100).toStringAsFixed(0)}% ($loaded/$total)');
  },
);

// Or preload only the samples needed for a specific preset:
await player.preloadPreset(preset);
```

---

### 7. Applying Global Audio DSP Filters

Use `SoundFontGlobalFilters` to apply and modulate audio effects on the master mix:

```dart
const filters = SoundFontGlobalFilters();

// Activate Freeverb (Reverb)
filters.toggle(SoundFontFilterType.freeverb, true);

// Adjust parameters:
final params = filters.getParameters(SoundFontFilterType.freeverb);
for (final p in params) {
  if (p.id == 'room_size') {
    p.setValue(0.8); // 80% room size
  }
}

// Available global filters:
// - SoundFontFilterType.freeverb
// - SoundFontFilterType.echo
// - SoundFontFilterType.biquad (Low-pass / resonant)
// - SoundFontFilterType.flanger
// - SoundFontFilterType.bassBoost
// - SoundFontFilterType.lofi
// - SoundFontFilterType.waveShaper (Drive / distortion)
```

---

## Example App Capabilities

The included [`example/`](example) directory contains a complete Flutter desktop, mobile, and web demonstration app featuring:

1. **Interactive SoundFont Inspector**:
   - Tree inspector for Presets, Instruments, Generator Zones, and Raw Sample descriptors.
   - Raw binary header inspection (RIFF magic, OGG headers, FLAC metadata).
   - Embedded audio waveform visualization widget (`SampleWaveform`) with:
     - Real-time animated playhead tracking (red vertical line) driven by `SoLoud.instance.getPosition()`.
     - Yellow vertical markers indicating `loopStart` and `loopEnd` boundary positions.
2. **Dynamic Docked Piano Keyboard**:
   - Resizable docked bottom panel.
   - Chromatic multi-touch keyboard with vertical touch-velocity sensing (pressing higher on a key plays softer; pressing lower plays louder).
   - Visual MIDI key numbers and keybinding badges on both white and black keys.
   - Red indicator dots highlighting the root key and mapped ranges of the currently selected zone/sample.
   - Full computer keyboard control and navigation:
     - <kbd>Space</kbd>: Audition currently selected preset, instrument, or sample.
     - <kbd>▲</kbd> / <kbd>▼</kbd> (Up / Down): Select previous / next item in the active tab list.
     - <kbd>◄</kbd> / <kbd>►</kbd> (Left / Right): Shift keyboard octave down / up.
     - <kbd>Canc</kbd> / <kbd>Delete</kbd>: Emergency stop for all playing voices.
     - <kbd>A</kbd>..<kbd>K</kbd>: 1-octave chromatic QWERTY keyboard mapping.
     - Top-right App Bar Info button with a built-in keyboard shortcuts guide dialog.
3. **Rotary Knobs Parameter Rack**:
   - **`Vol`**: Master volume control.
   - **`Sus x` (Sustain Multiplier)**: Active when the selected target has native sustain (`0.0x` to `10.0x`).
   - **`Sus` (Sustain Time)**: Active when the selected target has no native sustain (`0.05s` to `5.0s`).
4. **Global Audio DSP Filters Rack**:
   - Dedicated **Filters** button with an active filter counter badge.
   - Interactive configuration sheet to toggle and adjust multiple global effects in real time:
     - **Freeverb** (Room Size, Damp, Wet/Dry, Width)
     - **Echo** (Delay Time, Decay, Filter)
     - **Biquad Resonant Filter** (Low-pass / Band-pass frequency and resonance)
     - **Flanger** (Delay, Frequency, Depth)
     - **Bass Boost** (Boost dB)
     - **Lo-Fi** (Sample rate reduction & bit depth decimation)
     - **Wave Shaper** (Drive saturation & distortion)
5. **File & Folder Pickers**:
   - Open individual SoundFont files (`.sf2`, `.sf3`, `.sfz`, `.zip`, `.tar.gz`, etc.).
   - Open entire uncompressed SFZ directory hierarchies with automatic nested sample resolution.
   - Optional preloading prompt with real-time percentage progress bar.

To run the example app:

```bash
cd example
flutter run
```

---

## License

This project is open source and available under the terms of the MIT License.
