---
name: soundfont_kit-filters
version: 1
description: Configuring and modulating global DSP audio filters in soundfont_kit — Freeverb reverb, Echo delay, Biquad resonant filter, Flanger, Bass Boost, Lo-Fi, and Wave Shaper. Use when the user asks how to add audio effects, add reverb or echo, create an effects rack, or modulate filter parameters for soundfont playback.
---

# soundfont_kit audio filters

`soundfont_kit` includes [`SoundFontGlobalFilters`](file:///Volumes/NVME/workspace/libs/soundfont_kit/lib/src/player/filters/soundfont_filter.dart), a built-in controller for applying and modulating master audio DSP effects via `flutter_soloud`.

Because these apply at the global mixer output, they are 100% compatible with all platforms including **Flutter Web** (which does not support per-sound filters).

---

## 1. Using `SoundFontGlobalFilters`

Instantiate the controller:

```dart
import 'package:soundfont_kit/soundfont_kit.dart';

const filters = SoundFontGlobalFilters();
```

### Toggling Effects
```dart
// Check if an effect is active:
final isReverbOn = filters.isActive(SoundFontFilterType.freeverb);

// Turn on Reverb (Freeverb):
filters.toggle(SoundFontFilterType.freeverb, true);

// Turn off Echo:
filters.toggle(SoundFontFilterType.echo, false);

// Deactivate all active filters:
filters.deactivateAll();
```

---

## 2. Supported Filter Types & Parameters

Each filter provides a list of [`FilterParameterInfo`](file:///Volumes/NVME/workspace/libs/soundfont_kit/lib/src/player/filters/soundfont_filter.dart) descriptors containing metadata (`id`, `name`, `unit`, `min`, `max`, `defaultValue`) and get/set callbacks:

### 1. `SoundFontFilterType.freeverb` (Concert Hall Reverb)
- `room_size`: Room acoustic size (0.0 to 1.0, unit: `%`)
- `damp`: High-frequency dampening (0.0 to 1.0, unit: `%`)
- `width`: Stereo spread width (0.0 to 1.0, unit: `%`)
- `wet`: Wet effect mix level (0.0 to 1.0, unit: `%`)

### 2. `SoundFontFilterType.echo` (Delay & Repeat)
- `delay`: Echo delay time in seconds (0.001 to 3.0, unit: `s`)
- `decay`: Feedback decay factor (0.0 to 1.0, unit: `%`)
- `filter`: Lowpass tone damping (0.0 to 1.0, unit: `%`)
- `wet`: Wet effect mix level (0.0 to 1.0, unit: `%`)

### 3. `SoundFontFilterType.biquad` (Resonant Filter)
- `frequency`: Cutoff frequency (10 to 22000, unit: `Hz`)
- `resonance`: Resonance peak sharpness (0.1 to 20.0, unit: `Q`)
- `wet`: Wet mix level (0.0 to 1.0, unit: `%`)

### 4. `SoundFontFilterType.flanger` (Chorus / Shimmer)
- `delay`: Base delay (0.001 to 0.1, unit: `s`)
- `freq`: LFO modulation speed (0.01 to 100.0, unit: `Hz`)
- `wet`: Wet mix level (0.0 to 1.0, unit: `%`)

### 5. `SoundFontFilterType.bassBoost` (Low-End Punch)
- `boost`: Bass gain multiplier (0.0 to 10.0, unit: `x`)
- `wet`: Wet mix level (0.0 to 1.0, unit: `%`)

### 6. `SoundFontFilterType.lofi` (Vintage Bit-Crusher)
- `samplerate`: Sample rate reduction (1000 to 44100, unit: `Hz`)
- `bitdepth`: Bit depth decimation (1 to 16, unit: `bits`)
- `wet`: Wet mix level (0.0 to 1.0, unit: `%`)

### 7. `SoundFontFilterType.waveShaper` (Warm Saturation & Distortion)
- `amount`: Drive amount / clipping curve (0.0 to 1.0)
- `wet`: Wet mix level (0.0 to 1.0, unit: `%`)

---

## 3. Reading & Modulating Parameters

To adjust parameters programmatically:

```dart
// Activate Freeverb
filters.toggle(SoundFontFilterType.freeverb, true);

// Retrieve parameter list:
final params = filters.getParameters(SoundFontFilterType.freeverb);
for (final p in params) {
  print('${p.name} current: ${p.currentValue} ${p.unit} (range: ${p.min}..${p.max})');

  if (p.id == 'room_size') {
    p.setValue(0.8); // 80% room size
  } else if (p.id == 'wet') {
    p.setValue(0.35); // 35% wet reverb
  }
}
```

---

## 4. Building an Effects Rack Widget

You can bind `FilterParameterInfo` directly to Flutter `Slider` widgets:

```dart
Widget buildFilterControls(SoundFontFilterType type) {
  final params = filters.getParameters(type);

  return Column(
    children: [
      SwitchListTile(
        title: Text(type.label),
        subtitle: Text(type.description),
        value: filters.isActive(type),
        onChanged: (active) => setState(() => filters.toggle(type, active)),
      ),
      if (filters.isActive(type))
        for (final p in params)
          Row(
            children: [
              Text(p.name),
              Expanded(
                child: Slider(
                  value: p.currentValue,
                  min: p.min,
                  max: p.max,
                  onChanged: (val) => setState(() => p.setValue(val)),
                ),
              ),
              Text('${p.currentValue.toStringAsFixed(2)} ${p.unit}'),
            ],
          ),
    ],
  );
}
```

---

## Traps & Common Gotchas

- **Calling filters before `SoLoud.instance.init()`**: Toggling or querying filters before engine initialization is safely ignored (returns `false` or empty list). Always await `init()` first.
- **Web Safety**: Global filters are executed in the main WebAudio/WASM audio graph, making them safe across all browsers. Do not attempt to attach per-sound native filters on Web.

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
