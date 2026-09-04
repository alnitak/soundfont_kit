---
name: soundfont_kit-loading
version: 1
description: Loading SoundFont files (SF2, SF3, SFZ, compressed archives) from assets, files, bytes, and URLs using soundfont_kit, and inspecting metadata (presets, instruments, zones, samples). Use when the user asks how to load a SoundFont, parse SF2/SF3/SFZ formats, load zipped soundbanks, query presets, or inspect audio samples.
---

# soundfont_kit loading & formats

`soundfont_kit` includes a pure Dart multi-format reader capable of parsing and querying SoundFonts and compressed archives across all platforms.

---

## Supported Formats

| Format | Extension | Description |
|---|---|---|
| **SF2** | `.sf2` | SoundFont 2.04 RIFF/`sfbk` parser. Decodes presets, instruments, generator zones, modulators, and 16-bit PCM samples. |
| **SF3** | `.sf3` | SoundFont 3.0 RIFF/`sfbk` container with OGG Vorbis compressed sample streams and sub-chunk header extraction. |
| **SFZ** | `.sfz` | SFZ instrument definition files (`<group>`, `<region>`, `sample=...`, `key=...`). Links to external `.wav`, `.flac`, or `.ogg` audio files. |
| **Archives** | `.zip`, `.tar`, `.gz`, `.bz2`, `.tgz`, `.tbz2` | Transparently decompressed in memory. Nested directory structures and sample references inside archives are automatically resolved. |

---

## Loading SoundFonts (`SoundFontFile`)

Use the factory constructors on `SoundFontFile`. Format detection (`sf2`, `sf3`, `sfz`, or archive) is automatic:

```dart
import 'package:soundfont_kit/soundfont_kit.dart';

// 1. From Flutter Asset (bundle in pubspec.yaml assets list):
final sf = await SoundFontFile.fromAsset('assets/soundfonts/GeneralUser.sf2');

// 2. From Local Disk File (desktop/mobile IO):
final sf = await SoundFontFile.fromFile('/path/to/instrument.sf3');

// 3. From In-Memory Bytes (e.g. from FilePicker, WebSocket, or custom download):
final sf = await SoundFontFile.fromBytes(
  bytes,
  basePath: 'my_soundfont.sf2', // Optional filename hint
);

// 4. From Remote HTTP URL:
final sf = await SoundFontFile.fromUrl(
  'https://example.com/soundfonts/acoustic_piano.sf2',
);

// 5. From Zipped SFZ Archive containing .sfz and audio sample folders:
final sf = await SoundFontFile.fromFile('/path/to/celesta_sfz.zip');
```

---

## Working with Compressed SFZ Archives

SFZ instruments typically consist of an `.sfz` text file alongside loose audio samples in subdirectories (e.g. `Samples/c4.wav`).

`soundfont_kit` handles this seamlessly when packaged as a `.zip` or `.tar.gz`:
1. Compress the entire SFZ directory into a `.zip` archive.
2. Load the `.zip` directly via `SoundFontFile.fromFile()`, `fromAsset()`, or `fromBytes()`.
3. `ZipSource` normalizes relative paths, handles backslash vs slash paths, and case insensitivity so sample references like `sample=Samples/C4.wav` resolve correctly.

---

## Inspecting SoundFont Structure & Metadata

`SoundFontFile` gives full access to parsed SoundFont components:

```dart
print('SoundFont Name: ${sf.name}');
print('Format: ${sf.format.name}'); // SoundFontFormat.sf2, sf3, or sfz
print('Comment: ${sf.comment}');
print('Total Presets: ${sf.presets.length}');
print('Total Instruments: ${sf.instruments.length}');
print('Total Samples: ${sf.samples.length}');

// 1. Lookup a specific Preset by General MIDI bank and program number:
// (Bank 0, Program 0 = Acoustic Grand Piano)
final grandPiano = sf.findPreset(bank: 0, program: 0);

// 2. Iterate Presets:
for (final preset in sf.presets) {
  print('Preset [${preset.bank}:${preset.program}] "${preset.name}"');
  for (final zone in preset.zones) {
    // Check if zone matches a specific note and velocity:
    if (zone.matches(60, 100)) {
      print('  Zone matches MIDI key 60 at velocity 100');
    }
  }
}

// 3. Iterate Instruments:
for (final instrument in sf.instruments) {
  print('Instrument "${instrument.name}" (ID: ${instrument.id})');
}

// 4. Inspect Sample Metadata:
for (final sample in sf.samples) {
  print('Sample "${sample.name}":');
  print('  Rate: ${sample.sampleRate} Hz');
  print('  Channels: ${sample.channels}');
  print('  Original Pitch: ${sample.originalPitch} (correction: ${sample.pitchCorrection})');
  print('  Loop: ${sample.loopStart}..${sample.loopEnd}');
  print('  Compression: ${sample.compression.name}');
  print('  Stereo Flags: mono=${sample.isMono}, L=${sample.isLeft}, R=${sample.isRight}');
}
```

---

## Traps & Platform Notes

- **Web Filesystem**: `SoundFontFile.fromFile` throws on Flutter Web because the browser sandbox does not allow direct file path access. Always use `fromAsset`, `fromBytes`, or `fromUrl` on Web.
- **SFZ External Sample Paths**: When loading loose SFZ files from disk via `fromFile`, ensure sample audio files reside in the relative path specified by the opcode (relative to the `.sfz` file location).
- **Format Hinting**: If bytes come without a file extension (e.g., custom byte stream), provide `formatHint: SoundFontFormat.sf2` in `SoundFontFile.fromBytes`.

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
