---
name: soundfont-kit-vst3
version: 1
description: Hosting desktop VST3 Effect and Virtual Instrument plugins (.vst3) in soundfont_kit via SoundFontVst3Manager. Use when the user asks how to scan .vst3 bundles, insert VST3 effects into global or per-channel custom filter slots (0..7), assign a VST3 synth to a MidiPlayer channel, or open native VST3 GUI editor windows.
---

# soundfont_kit desktop VST3 plugin hosting (`SoundFontVst3Manager`)

On desktop platforms (`macOS`, `Windows`, `Linux`), `soundfont_kit` provides [`SoundFontVst3Manager`](file:///Volumes/NVME/workspace/libs/soundfont_kit/lib/src/player/vst3/soundfont_vst3_manager.dart) to scan `.vst3` plugin bundles, insert VST3 Audio Effects into `SoundFontFilterRack` custom slots (`0..7`), and route `MidiPlayer` channels to VST3 Virtual Instruments.

---

## 1. Checking Platform Support & Scanning `.vst3` Bundles

Always check `SoundFontVst3Manager.instance.isSupported` before showing VST3 controls (returns `false` on Web, iOS, and Android):

```dart
import 'package:soundfont_kit/soundfont_kit.dart';

final vst3 = SoundFontVst3Manager.instance;
if (vst3.isSupported) {
  // Scan default OS VST3 directories (/Library/Audio/Plug-Ins/VST3, etc.):
  final discovered = vst3.scanStandardDirectories();
  for (final plugin in discovered) {
    print('${plugin.name} by ${plugin.vendor} — Instrument: ${plugin.isInstrument}, Effect: ${plugin.isEffect}');
  }
}
```

---

## 2. Loading a VST3 Effect into a `SoundFontFilterRack` Slot (`0..7`)

Every `SoundFontFilterRack` (both `SoundFontFilterRack.global()` and `SoundFontFilterRack.forBus(bus)`) exposes 8 custom filter slots (`0..7`):

```dart
final rack = const SoundFontFilterRack.global();

// Load a .vst3 effect into Custom Slot 0:
final effect = vst3.loadEffectIntoSlot(
  bundlePath: '/Library/Audio/Plug-Ins/VST3/OTT.vst3',
  rack: rack,
  slotIndex: 0,
);

if (effect != null) {
  // Open the native floating macOS/Windows/Linux VST3 GUI editor window:
  effect.openEditorWindow(title: 'Master Slot 0 — OTT');

  // Inspect or automate VST3 parameters from Dart:
  for (final param in effect.parameters) {
    print('[${param.paramId}] ${param.title}: ${effect.getParameterDisplay(param.paramId)}');
  }
}

// Unload when done:
vst3.unloadEffectFromSlot(rack: rack, slotIndex: 0);
```

---

## 3. Assigning a VST3 Virtual Instrument to a `MidiPlayer` Channel

Any of the 16 MIDI channels in `MidiPlayer` can be driven by a `.vst3` Virtual Instrument (`Vst3InstrumentPlugin`):

```dart
final inst = vst3.loadInstrument(
  bundlePath: '/Library/Audio/Plug-Ins/VST3/Dexed.vst3',
  autoPlay: false,
);

if (inst != null) {
  // Assign to MIDI Channel 0 (routes NoteOn, NoteOff, Sustain CC 64, and syncs BPM/transport):
  midiPlayer.setChannelVst3Instrument(0, inst, name: 'Dexed FM Synth');

  // Open native VST3 GUI editor:
  inst.openEditorWindow(title: 'Ch 1 — Dexed');
}
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
