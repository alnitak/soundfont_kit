# SoundFont Kit

A high-performance, pure Dart reader, synthesizer, and playback engine for SoundFont files (**SF2**, **SF3**, and **SFZ**) and Standard MIDI Files (**SMF 0 & 1**), powered by the [flutter_soloud](https://pub.dev/packages/flutter_soloud) low-latency audio engine.

---

## Features

- See [***web example***](https://marcobavagnoli.com/soundfont/)
- See [***piano 3D***](https://marcobavagnoli.com/piano_3d) web example which uses [flutter_scene](https://pub.dev/packages/flutter_scene)
- **Multi-Format Support**:
  - **SF2** (SoundFont 2.04) — Full RIFF/sfbk parser (presets, instruments, zones, 6-stage DAHDSR envelopes, resonant filter cutoffs/Q, LFOs, exclusive choke groups, and 16-bit PCM samples).
  - **SF3** (SoundFont 3.0) — OGG Vorbis compressed sample streams with sub-chunk header extraction.
  - **SFZ** (SFZ Instrument Definitions) — Parses opcode definitions (`ampeg_*`, `fileg_*`, `pitcheg_*`, `pitchlfo_*`, `cutoff`, `resonance`, `group`, `off_by`, etc.) and links to external `.wav`, `.flac`, or `.ogg` audio files.
  - **Compressed Archives** — Transparently loads compressed archives (`.zip`, `.gz`, `.bz2`, `.tar`, `.tgz`, `.tbz2`) containing SoundFonts and loose sample hierarchies.
- **Flexible Data Sources**:
  - Load from Flutter Assets (`SoundFontFile.fromAsset`).
  - Load from Local Disk (`SoundFontFile.fromFile`).
  - Load from In-Memory Byte Buffers (`SoundFontFile.fromBytes`).
  - Load from Remote HTTP URLs (`SoundFontFile.fromUrl`).
- **Dual Synthesis Engine (`SoundFontSynthMode`)**:
  - **`SoundFontSynthMode.soloudVoices` (Default)**: Plays each zone as a SoLoud `AudioSource` voice with sample-accurate `playScheduled` / `fadeScheduled` / `stopScheduled` retroactive playing-window splicing, full **6-stage DAHDSR** volume envelopes, **Exclusive Class (`exclusiveClass` / `off_by`)** voice choking, and per-voice Biquad resonant low-pass filtering.
  - **`SoundFontSynthMode.realtimeIsolateSynth`**: Synthesizes polyphonic voices inside a dedicated background worker isolate (`RealtimeSoundFontSynthesizer` via `SoLoudIsolate` + `RealtimeStreamFeeder`) with zero-GC native buffers, per-voice Cytomic TPT resonant State-Variable Filters (SVF), 6-stage Volume & Modulation DAHDSR envelopes, ModLFO, and VibLFO across all platforms (including Web).
  - **Stereo Channel Joining**: Automatically interleaves paired Left and Right 16-bit PCM channels into true 2-channel stereo streams with centered mixer balance.
  - **Dynamic Unified Sustain & Release Control**:
    - **Unified Sustain (`sustain`)**: Single master control (`0.0` to `10.0`, default `1.0`) that automatically scales authentic envelopes on SoundFonts that have them, and scales clean fallback release decay on ones that don't.
    - **Fallback Sustain Time (`sustainTime`)**: Configures base fallback release duration (e.g. `0.2s`) for instruments or samples lacking a native release envelope.
    - **Staccato Mode (`sustain: 0.0`)**: Cuts off sound immediately upon key release across all SoundFonts.
- **Sample Preloading**:
  - Preload all samples into memory upfront (`preloadAll`) for instant zero-latency playback, or stream them on-demand via `SampleStreamer`.
  - Granular preloading per preset (`preloadPreset`) or per instrument (`preloadInstrument`) with real-time progress callbacks.
- **Global & Per-Bus Audio DSP Filter Racks (`SoundFontFilterRack`)**:
  - Unified filter controller (`SoundFontFilterRack.global()` and `SoundFontFilterRack.forBus(Bus)`) supporting **Freeverb**, **Echo/Delay**, **Biquad Resonant Filter**, **Flanger**, **Bass Boost**, **Lo-Fi**, **Wave Shaper**, **Compressor**, **Limiter**, **Parametric EQ**, **Pitch Shift**, **Amplitude Modulator**, and **8 Custom C++/Web/VST3 Filter Slots (`customSlot0`..`customSlot7`)** with C++ parameter fades (`fadeParameter`) and LFO oscillation (`oscillateParameter`).
- **Multi-Channel MIDI Sequencer & Desktop VST3 Hosting (`MidiPlayer` & `SoundFontVst3Manager`)**:
  - Standard MIDI File (`SMF 0 & 1` and `RIFF/RMID`) parser and 16-channel sequencer with lazy per-channel SoLoud mixing `Bus` routing (`CC 1` Mod Wheel, `CC 91` Reverb Send, `CC 93` Chorus Send), real-time chord detection, and synchronized karaoke lyrics.
  - **Desktop VST3 Hosting (`macOS`, `Windows`, `Linux`)**: Scan `.vst3` plugin bundles, insert VST3 Audio Effects into global or per-channel custom filter slots (`0..7`), assign VST3 Virtual Instruments (`Vst3InstrumentPlugin`) to any MIDI channel alongside SoundFont channels, and open native OS plugin editor windows (`openEditorWindow`).

---

## Getting Started

Add `soundfont_kit` and `flutter_soloud` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  soundfont_kit: ^1.2.0
  flutter_soloud: ^4.0.0
```

Initialize the `flutter_soloud` audio engine prior to playback (e.g. in your `main()` function):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:soundfont_kit/soundfont_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the SoLoud audio engine with retroactive render-ahead splicing
  await SoLoud.instance.init(
    renderAheadFrames: 1024,
    devicePeriodFrames: 128,
  );
  SoLoud.instance.setMaxActiveVoiceCount(256);

  runApp(const MyApp());
}
```

---

## AI Agent Skills

`soundfont_kit` includes 9 bundled **Agent Skills** (`SKILL.md` instruction files) to help AI coding agents (Claude, Cursor, Gemini, GitHub Copilot, Cline, Codex, OpenCode, etc.) generate correct, high-performance code for all features of this package (`soundfont-kit-loading`, `soundfont-kit-playback`, `soundfont-kit-preloading`, `soundfont-kit-sustain`, `soundfont-kit-scheduling`, `soundfont-kit-filters`, `soundfont-kit-midi`, `soundfont-kit-vst3`, and `soundfont-kit-idioms`).

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

### 3. Playing Presets, Instruments & Choosing a Synthesis Mode

Create a `SoundFontPlayer` to play presets, instruments, or raw samples using either `SoundFontSynthMode.soloudVoices` (default) or `SoundFontSynthMode.realtimeIsolateSynth`:

```dart
// Create the player instance
final player = sf.createPlayer(
  options: const SoundFontPlayerOptions(
    synthMode: SoundFontSynthMode.soloudVoices, // or SoundFontSynthMode.realtimeIsolateSynth
    enablePerVoiceFilter: true,                 // Apply SF2/SFZ resonant filter per voice
    joinStereoChannels: true,                   // Join paired L/R mono samples to stereo
    cacheAudioSources: true,                    // Preserve audio buffers in RAM
    useScheduledPlayback: true,                 // Use sample-accurate engine clock
    sustain: 1.0,                               // 1.0x = authentic release for all SoundFonts
    sustainTime: 0.20,                          // 200ms fallback for items without release
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

// You can also switch synthesis modes dynamically at runtime:
player.synthMode = SoundFontSynthMode.realtimeIsolateSynth;
```

---

### 4. Unified Sustain Control

A single master `sustain` parameter adapts automatically across all SoundFonts:

```dart
// 1.0 = Authentic release (natural SoundFont envelope or clean 200ms fallback):
player.sustain = 1.0;

// > 1.0 = Extended sustain (simulates holding a piano damper/sustain pedal):
player.sustain = 2.5;

// 0.0 = Staccato (instant cutoff on key release):
player.sustain = 0.0;

// Optional: customize the base fallback release duration for non-envelope samples:
player.sustainTime = 0.5; // 500ms base decay (multiplied by player.sustain)
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

### 7. Global & Per-Bus Audio DSP Filters (`SoundFontFilterRack`)

Use `SoundFontFilterRack` (aliased as `SoundFontGlobalFilters`) to apply, fade, and oscillate audio effects on the master mix or on any mixing `Bus`:

```dart
// Master filter rack (or SoundFontFilterRack.forBus(bus) for a specific Bus):
const filters = SoundFontFilterRack.global();

// Activate Freeverb (Reverb) and Limiter:
filters.toggle(SoundFontFilterType.freeverb, true);
filters.toggle(SoundFontFilterType.limiter, true);

// Smoothly fade Biquad filter cutoff to 1200 Hz over 1 second on the audio thread:
filters.toggle(SoundFontFilterType.biquad, true);
filters.fadeParameter(
  SoundFontFilterType.biquad,
  'frequency',
  to: 1200.0,
  duration: const Duration(seconds: 1),
);

// Available built-in & custom filter types:
// - SoundFontFilterType.freeverb
// - SoundFontFilterType.echo
// - SoundFontFilterType.biquad
// - SoundFontFilterType.flanger
// - SoundFontFilterType.bassBoost
// - SoundFontFilterType.lofi
// - SoundFontFilterType.waveShaper
// - SoundFontFilterType.compressor
// - SoundFontFilterType.limiter
// - SoundFontFilterType.parametricEq
// - SoundFontFilterType.pitchShift
// - SoundFontFilterType.amplitudeModulator
// - SoundFontFilterType.customSlot0 .. customSlot7
```

---

### 8. MIDI File Playback, Per-Channel Buses & Desktop VST3 Hosting

`soundfont_kit` includes a built-in Standard MIDI File (**SMF format 0 and 1**) parser, 16-channel sequencer engine (`MidiPlayer`), and desktop VST3 plugin manager (`SoundFontVst3Manager`):

```dart
// 1. Load any SoundFont file (SF2, SF3, or SFZ)
final sf = await SoundFontFile.fromFile('assets/soundfonts/MySoundFont.sf2');
final sfPlayer = sf.createPlayer();

// 2. Parse a Standard MIDI File (.mid / .midi)
final midi = await MidiReader.fromFile(File('assets/music/song.mid'));

// 3. Create and load the MidiPlayer
final midiPlayer = MidiPlayer(player: sfPlayer);
await midiPlayer.load(midi, autoPreload: true);

// 4. Per-channel DSP filter rack (lazily creates a dedicated SoLoud Bus for Channel 0):
midiPlayer.channels[0].filterRack.toggle(SoundFontFilterType.echo, true);

// 5. Optional (Desktop: macOS, Windows, Linux): Assign a .vst3 Virtual Instrument to Channel 0
if (SoundFontVst3Manager.instance.isSupported) {
  final vst3Synth = SoundFontVst3Manager.instance.loadInstrument(
    bundlePath: '/Library/Audio/Plug-Ins/VST3/Surge XT.vst3',
    autoPlay: false,
  );
  if (vst3Synth != null) {
    midiPlayer.setChannelVst3Instrument(0, vst3Synth, name: 'Surge XT');
    vst3Synth.openEditorWindow(title: 'Ch 1 — Surge XT');
  }
}

// 6. Playback controls
await midiPlayer.play();
await midiPlayer.pause();
await midiPlayer.seek(const Duration(seconds: 45));
await midiPlayer.stop();
```

---

## Example App Capabilities

The included [`example/`](example) directory contains two full demonstration apps (`lib/main_full.dart` and `lib/main_midi.dart`) featuring:

1. **Interactive SoundFont Inspector (`main_full.dart`)**:
   - Tree inspector for Presets, Instruments, Generator Zones, and Raw Sample descriptors.
   - Embedded audio waveform visualization widget (`SampleWaveform`) with real-time playhead tracking and `loopStart`/`loopEnd` markers.
   - **Synth Mode Selector**: Switch live between `Voices DAHDSR` (`SoundFontSynthMode.soloudVoices`) and `Isolate SVF` (`SoundFontSynthMode.realtimeIsolateSynth`).
2. **Dynamic Docked Piano Keyboard & Expanded DSP / VST3 Rack**:
   - Chromatic multi-touch and computer QWERTY keyboard with velocity sensing.
   - Scrollable DSP filter rack covering all 12 built-in SoLoud filters (`Freeverb`, `Echo`, `Biquad`, `Flanger`, `Bass Boost`, `Lo-Fi`, `Wave Shaper`, `Compressor`, `Limiter`, `Parametric EQ`, `Pitch Shift`, `Amplitude Modulator`) plus **8 Custom DSP / Desktop VST3 Effect Slots** with `.vst3` bundle picker and `"Open VST3 GUI"` buttons.
3. **16-Channel MIDI DAW & Hybrid SoundFont / VST3 Sequencer (`main_midi.dart`)**:
   - Interactive 16-channel timeline, piano roll, chord detector, and synchronized karaoke lyrics banner.
   - Per-channel instrument picker (`ChannelInstrumentPickerDialog`) supporting multi-SoundFont assignment and desktop `.vst3` Virtual Instrument loading with native VST3 GUI editor windows.

To run the example apps:

```bash
cd example
flutter run -t lib/main_full.dart
# or for the 16-channel MIDI DAW:
flutter run -t lib/main_midi.dart
```

---

## License

This project is open source and available under the terms of the MIT License.
