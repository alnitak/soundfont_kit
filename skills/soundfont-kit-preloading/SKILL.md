---
name: soundfont_kit-preloading
version: 1
description: Zero-latency sample preloading and memory optimization in soundfont_kit — preloadAll, preloadPreset, preloadInstrument, progress callbacks, and RAM vs streaming trade-offs. Use when the user asks how to eliminate audio latency, fix stutter on key presses, show a loading progress bar, or optimize RAM usage for large soundfonts.
---

# soundfont_kit preloading & memory

By default, `soundfont_kit` reads and decodes audio samples on-demand as notes are triggered. While this keeps initial startup instantaneous, reading disk buffers and decompressing OGG Vorbis streams during live `noteOn` can introduce latency or audio stutter on the first note strike.

For zero-latency real-time performance (e.g. piano keyboards or live MIDI playback), preload samples into memory upfront.

---

## 1. Preloading All Samples (`preloadAll`)

Ideal for dedicated instrument soundfonts (pianos, organs, brass, drums) under ~50MB:

```dart
// Preload all samples with live progress callback (0.0 to 1.0)
await player.preloadAll(
  onProgress: (progress, loaded, total) {
    final pct = (progress * 100).toStringAsFixed(1);
    print('Loading soundfont: $pct% ($loaded / $total samples)');
  },
);
```

You can also enable eager preloading during player instantiation:
```dart
final player = sf.createPlayer(
  options: const SoundFontPlayerOptions(
    preloadAllSamples: true, // Automatically calls preloadAll() on creation
  ),
);
```

---

## 2. Granular Preloading per Preset (`preloadPreset`)

For large General MIDI soundbanks (100MB+ with hundreds of presets), loading all samples into RAM can exhaust mobile memory. Instead, preload only the active preset when the user selects a patch:

```dart
// When user chooses an instrument patch (e.g. from a dropdown):
Future<void> switchPatch(Preset newPreset) async {
  showLoadingDialog();

  // Only decodes the specific samples referenced by this preset's zones:
  await player.preloadPreset(
    newPreset,
    onProgress: (progress, loaded, total) {
      updateProgressBar(progress);
    },
  );

  hideLoadingDialog();
}
```

Similarly, you can preload an individual instrument or sample:
```dart
await player.preloadInstrument(instrument);
await player.preloadSample(sample);
```

---

## 3. Audio Source RAM Caching

`SoundFontPlayerOptions.cacheAudioSources` defaults to `true`.

Once a sample is decoded into a SoLoud `AudioSource` (either via preloading or first play), it stays in memory:
- Subsequent note-on events for the same sample trigger immediately with zero memory allocation or decoding overhead.
- When `player.dispose()` is called, all cached audio sources are properly freed from native memory.

---

## Memory vs Latency Trade-Offs

| Approach | Latency | RAM Usage | Best Used For |
|---|---|---|---|
| **On-Demand Streaming** | Small initial delay on first note strike | Minimum | Background auditioning, browsing vast soundbanks. |
| **Preset Preloading** | Zero latency for active instrument | Moderate (~5–20MB) | General MIDI players with switchable presets. |
| **Preload All** | Zero latency across entire soundbank | Higher (full bank size) | Virtual pianos, dedicated synth apps, games with fixed soundfonts. |

---

## Traps & Common Gotchas

- **Memory Pressure**: Preloading a 200MB SoundFont will allocate significant RAM for decoded PCM data. On mobile or web targets, use `preloadPreset()` selectively rather than `preloadAll()`.
- **UI Freezes**: Preloading involves decoding audio bytes. Always show a progress indicator or run preloading before opening an interactive performance view.

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
