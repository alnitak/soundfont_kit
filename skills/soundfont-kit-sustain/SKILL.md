---
name: soundfont-kit-sustain
version: 1
description: Controlling sustain and release modes in soundfont_kit — the sustainMultiplier for authentic SoundFont volume envelopes vs sustainTime fallback for non-envelope samples, piano damper pedal simulation, staccato release, and eliminating DC audio clicks. Use when the user asks about sustain pedals, note release envelopes, staccato playback, or fixing audio pops when releasing keys.
---

# soundfont_kit sustain & release

SoundFonts vary significantly in how release characteristics are defined. Some soundbanks include authentic multi-stage volume envelopes (`volEnvRelease`), while others rely on one-shot raw audio samples without release metadata.

`soundfont_kit` provides two complementary controls on `SoundFontPlayer` to address both scenarios cleanly.

---

## 1. The Two Complementary Modes

```dart
final player = sf.createPlayer(
  options: const SoundFontPlayerOptions(
    sustainMultiplier: 1.0, // Multiplier for instruments WITH native release
    sustainTime: 0.20,      // Fallback fade (200ms) for instruments WITHOUT native release
  ),
);
```

### Mode A: Multiplier Mode (`player.sustainMultiplier`)
- **Applies to**: Instruments and generator zones that define an authentic SoundFont volume release envelope (`volEnvRelease > 0`).
- **Behavior**: Scales the SoundFont author's release duration:
  - `1.0`: Exact SoundFont envelope (authentic acoustic decay).
  - `2.0` - `4.0`: Extended sustain (simulates holding a piano damper/sustain pedal).
  - `0.0`: Immediate staccato cutoff upon key release.

### Mode B: Time Mode (`player.sustainTime`)
- **Applies to**: Instruments, zones, or raw samples that do **NOT** define a native release envelope (`volEnvRelease == null || 0`).
- **Behavior**: Sets an explicit volume fade-out duration in seconds (e.g. `0.15` to `0.5` seconds).
- **Purpose**: Prevents abrupt DC offset cutoffs, eliminating harsh audio clicks or pops when keys are released.

---

## 2. Implementing a Piano Sustain / Damper Pedal

To implement a realistic piano sustain pedal (MIDI CC 64):

```dart
class PianoController {
  final SoundFontPlayer player;
  bool _sustainPedalDown = false;

  PianoController(this.player);

  void onSustainPedalChanged(bool isDown) {
    _sustainPedalDown = isDown;
    // Scale authentic release time up to 3.5x when pedal is depressed:
    player.sustainMultiplier = isDown ? 3.5 : 1.0;
  }

  void onNoteOn(int key, int velocity) {
    player.noteOn(preset: preset, key: key, velocity: velocity);
  }

  void onNoteOff(int key) {
    // If sustain pedal is down, note rings out longer with the higher multiplier:
    player.noteOff(key);
  }
}
```

---

## 3. Staccato vs Legato

To toggle staccato playback at runtime:

```dart
// Staccato: sound cuts off immediately when the key is released
player.sustainMultiplier = 0.0;
player.sustainTime = 0.01; // Tiny 10ms micro-fade to avoid popping

// Normal legato: authentic instrument release
player.sustainMultiplier = 1.0;
player.sustainTime = 0.20;
```

---

## 4. Custom Release Overrides per Note

You can also override the release duration on an individual `SoundFontVoice`:

```dart
final voice = await player.playPreset(preset, key: 60);

// Release with an explicit 800ms fadeout regardless of player settings:
await voice.release(customRelease: const Duration(milliseconds: 800));
```

---

## Traps & Common Gotchas

- **Audio Clicks/Pops on Note Off**:
  If notes pop or click upon release, the active instrument lacks a `volEnvRelease` envelope and `sustainTime` is null or zero. Set `player.sustainTime = 0.15;` (150ms) to ensure smooth anti-click fades.
- **Notes Ringing Forever**:
  If notes never stop playing after `noteOff`, verify that the key integer matches between `noteOn(key: k)` and `noteOff(k)`. If you are manually triggering loops with `LoopMode.continuous`, ensure `voice.release()` or `player.noteOff()` is called.

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
