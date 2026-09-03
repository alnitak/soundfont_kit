---
name: soundfont_kit-idioms
version: 1
description: Core mental model and architecture of soundfont_kit — the SoundFontFile vs SoundFontPlayer separation, SoLoud.instance lifecycle, voice limits (setMaxActiveVoiceCount), minimal working example, and common traps. Use when the user asks how soundfont_kit works, how to get started, how to set up the audio engine, or to debug voice stealing and initialization issues.
---

# soundfont_kit idioms

`soundfont_kit` is a high-performance pure Dart reader and playback engine for SoundFont files (**SF2**, **SF3**, and **SFZ**), powered by the [`flutter_soloud`](https://pub.dev/packages/flutter_soloud) low-latency C++ audio engine.

Read this before writing any `soundfont_kit` code — it explains the separation between format parsing and voice synthesis, engine setup requirements, polyphony management, and lifecycle.

---

## Minimal Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:soundfont_kit/soundfont_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize the SoLoud audio engine.
  // ALWAYS raise the active voice count above the default 16 for polyphonic instruments!
  await SoLoud.instance.init();
  SoLoud.instance.setMaxActiveVoiceCount(128);

  // 2. Load a SoundFont from assets, disk, network, or compressed archives.
  final sf = await SoundFontFile.fromAsset('assets/soundfonts/GeneralUser.sf2');

  // 3. Create a player instance.
  final player = sf.createPlayer(
    options: const SoundFontPlayerOptions(
      joinStereoChannels: true,   // Combine paired L/R mono samples to true stereo
      cacheAudioSources: true,    // Preserve decoded RAM sources for instant retrigger
      sustainMultiplier: 1.0,     // 1.0x authentic SoundFont envelope
    ),
  );

  // 4. Play notes: Note ON (Middle C = MIDI key 60, velocity 100)
  final preset = sf.presets.first;
  final voice = await player.noteOn(
    preset: preset,
    key: 60,
    velocity: 100,
  );

  // 5. Note OFF after 1 second (triggers smooth release envelope fade)
  await Future.delayed(const Duration(seconds: 1));
  await player.noteOff(60);

  // Teardown when done:
  // player.dispose();
  // await SoLoud.instance.deinit();
}
```

---

## The Architecture: `SoundFontFile` vs `SoundFontPlayer`

1. **`SoundFontFile`** (Format Reader & Metadata):
   - Represents the parsed SoundFont structure: presets, instruments, zones, generators, modulators, and audio sample byte offsets.
   - Format-agnostic: provides a unified interface across SF2, SF3, SFZ, and archive containers.
   - Does NOT produce audio or manage output devices.
   - Safe to inspect, query, or share across multiple player instances.

2. **`SoundFontPlayer`** (Playback Engine):
   - Connects a `SoundFontFile` to `flutter_soloud`.
   - Manages polyphony, dynamic pitch ratio scaling, velocity sensitivity, volume attenuation, stereo panning, looping, and release envelopes.
   - Handles the lifecycle of active voices and prevents stuck notes when `noteOff` fires before async voice initialization completes.

3. **`SoundFontVoice`** (Playing Note Instance):
   - Encapsulates one or more playing `SoundHandle` and `AudioSource` instances triggered for a note (e.g., layered instrument zones or stereo pairs).
   - Exposes note-off `release()`, immediate `stop()`, or sample-accurate engine clock operations (`stopScheduled`, `fadeScheduled`).

---

## Audio Engine Initialization & Voice Limits

`soundfont_kit` relies on `flutter_soloud` for low-latency native audio output. Before playing any sound:

```dart
// Ensure Flutter engine binding is initialized
WidgetsFlutterBinding.ensureInitialized();

// Initialize the engine
await SoLoud.instance.init();

// CRITICAL: SoLoud defaults to 16 maximum active voices.
// Polyphonic piano playing, chords, and long release tails will quickly exceed 16 voices,
// causing SoLoud to steal or drop notes silently. Set this to 64, 128, or 256.
SoLoud.instance.setMaxActiveVoiceCount(128);
```

### Web Platform Setup
For Flutter Web, add the SoLoud JavaScript glue into `web/index.html`:
```html
<script src="assets/packages/flutter_soloud/web/init_soloud.js" defer></script>
```

---

## Lifecycle & Cleanup

Always dispose player instances when navigating away from a screen or unloading instruments:

```dart
@override
void dispose() {
  // Disposes active voices, clears byte caches, and frees SoLoud AudioSource handles
  player.dispose();
  super.dispose();
}

// On full app shutdown:
// await SoLoud.instance.deinit();
```

---

## Traps & Common Gotchas

- **Calling playback before `SoLoud.instance.init()` completes**: Throws `SoLoudNotInitializedException`. Always await initialization in your app startup.
- **Keeping the default 16 voice cap**: Playing chords with a sustain pedal will silently steal older notes. Always call `SoLoud.instance.setMaxActiveVoiceCount(128)`.
- **Calling `SoundFontFile.fromFile` on Web**: The web platform has no direct filesystem access. Use `fromAsset`, `fromBytes`, or `fromUrl` on Web.
- **Forgetting `player.dispose()`**: Holding active players indefinitely retains cached decoded sample buffers in RAM. Call `dispose()` when switching soundbanks or tearing down widgets.
- **Mismatched `noteOn` and `noteOff` keys**: `noteOff(key)` matches the exact integer MIDI key number (0..127) used in `noteOn(..., key: key)`. If keys do not match, the voice continues playing until natural loop completion.

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
