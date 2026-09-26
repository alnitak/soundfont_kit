---
name: soundfont-kit-sustain
version: 1
description: Controlling sustain and release modes in soundfont_kit — the unified sustain parameter for both authentic SoundFont volume envelopes and fallback samples, piano damper pedal simulation, staccato release, and eliminating DC audio clicks. Use when the user asks about sustain pedals, note release envelopes, staccato playback, or fixing audio pops when releasing keys.
---

# soundfont_kit sustain & release

SoundFonts vary significantly in how release characteristics are defined. Some soundbanks include authentic multi-stage volume envelopes (`volEnvRelease`), while others rely on one-shot raw audio samples without release metadata.

`soundfont_kit` provides a single **unified `sustain`** parameter on `SoundFontPlayer` and `SoundFontPlayerOptions` that seamlessly adapts to both scenarios.

---

## 1. The Unified Sustain Parameter (`player.sustain`)

```dart
final player = sf.createPlayer(
  options: const SoundFontPlayerOptions(
    sustain: 1.0,      // Master sustain factor (works across ALL SoundFonts)
    sustainTime: 0.20, // Optional fallback duration in seconds for non-envelope samples
  ),
);
```

### How `sustain` Works:
- **For instruments WITH native release (`volEnvRelease > 0`)**:
  Scales the authentic SoundFont release envelope:
  $$\text{effectiveRelease} = \text{volEnvRelease} \times \text{sustain}$$
- **For instruments WITHOUT native release**:
  Scales the fallback decay duration (`sustainTime` or 150ms default):
  $$\text{effectiveRelease} = (\text{sustainTime} \ ?? \ 0.15\text{s}) \times \text{sustain}$$

### Key Values:
- **`1.0` (Default)**: Authentic release behavior (exact SoundFont envelope if available, clean ~150–200ms anti-click fade otherwise).
- **`0.0`**: Instant staccato key cutoff upon note release.
- **`2.0` – `4.0`**: Extended sustain (simulates a piano damper/sustain pedal ringing out).

*(Note: `player.sustainMultiplier` is retained as a fully compatible alias for `player.sustain`.)*

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
    // Scale release time up to 3.5x when pedal is depressed:
    player.sustain = isDown ? 3.5 : 1.0;
  }

  void onNoteOn(int key, int velocity) {
    player.noteOn(preset: preset, key: key, velocity: velocity);
  }

  void onNoteOff(int key) {
    // If sustain pedal is down, note rings out longer with the higher sustain value:
    player.noteOff(key);
  }
}
```

---

## 3. Staccato vs Legato

To toggle staccato playback at runtime:

```dart
// Staccato: sound cuts off immediately when the key is released
player.sustain = 0.0;

// Normal legato: authentic instrument release
player.sustain = 1.0;
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
