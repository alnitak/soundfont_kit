### 1.2.0
- **Dual Synthesis Engine (`SoundFontSynthMode`)**:
  - Enhanced default `SoundFontSynthMode.soloudVoices` mode with full 6-stage scheduled **DAHDSR** volume envelopes (`Delay -> Attack -> Hold -> Decay -> Sustain -> Release`), **Exclusive Class (`exclusiveClass` / `off_by`)** voice choking (e.g., closed hi-hat choking open hi-hat), and per-voice resonant low-pass filtering (`enablePerVoiceFilter`).
  - Added opt-in `SoundFontSynthMode.realtimeIsolateSynth` (`RealtimeSoundFontSynthesizer`) powered by `flutter_soloud`'s `RealtimeStreamHandle` and `RealtimeStreamFeeder` (`SoLoudIsolate`), computing sample-accurate 6-stage Volume & Modulation DAHDSR envelopes, Cytomic TPT resonant State-Variable Filters (SVF) with dynamic envelope/LFO modulation, ModLFO, and VibLFO in a background worker isolate across all platforms (including Web).
- **Expanded SF2 & SFZ Generator/Opcode Parsing**:
  - Extracted `volEnvDelay`, `modEnvDelay`, `modEnvToPitch`, `modEnvToFilterFc`, `modLfoDelay`, `modLfoFreq`, `modLfoToPitch`, `modLfoToFilterFc`, `modLfoToVolume`, `vibLfoDelay`, `vibLfoFreq`, `vibLfoToPitch`, `exclusiveClass`, `offByGroup`, `reverbSend`, and `chorusSend` in `Sf2Parser`, `SfzParser`, `Zone`, and `VoiceCalculator`.
- **Global & Per-Bus DSP Filter Rack (`SoundFontFilterRack`)**:
  - Upgraded `SoundFontGlobalFilters` (aliased as `SoundFontFilterRack`) to target either the global master output (`SoundFontFilterRack.global()`) or any mixing `Bus` (`SoundFontFilterRack.forBus(Bus)`).
  - Added 5 new built-in DSP filters (`compressor`, `limiter`, `parametricEq`, `pitchShift`, `amplitudeModulator`) and 8 user-programmable custom C++/Web/VST3 filter slots (`customSlot0`..`customSlot7`).
  - Added audio-thread parameter automation (`fadeParameter`, `oscillateParameter`, `FilterParameterInfo.fadeTo`, `FilterParameterInfo.oscillate`).
- **Per-Channel Mixing Buses in `MidiPlayer`**:
  - Added lazy per-channel SoLoud `Bus` routing (`MidiChannelState.ensureBus()`, `MidiChannelState.filterRack`).
  - Fixed global `CC 1` (Modulation Wheel) bleed by scoping `CC 1` strictly to the target MIDI channel's `Bus`.
  - Added `CC 91` (Reverb Send) and `CC 93` (Chorus Send) support per MIDI channel `Bus`.
- **Desktop VST3 Plugin Hosting (`SoundFontVst3Manager`)**:
  - Added `SoundFontVst3Manager` for scanning `.vst3` bundles on macOS, Windows, and Linux, loading VST3 Audio Effects (`Vst3EffectPlugin`) into Master or Per-Channel custom filter slots (`0..7`), loading VST3 Virtual Instruments (`Vst3InstrumentPlugin`), and opening native OS plugin editor windows (`openEditorWindow`).
  - Added hybrid SoundFont + VST3 Virtual Instrument playback in `MidiPlayer` (`setChannelVst3Instrument`) with automatic BPM and transport synchronization.
- **Low-Latency `SampleStreamer` Upgrade**:
  - Added `SampleStreamer.openRealtimeSampleStream` and `SampleStreamer.openRealtimeStereoPcmStream` backed by `SoLoud.instance.setRealtimeStream` (`RealtimeStreamHandle`) with SIMD (`NEON`/`SSE2`) de-interleaving.
- **Fixes & Improvements**:
  - Fixed negative loop boundary offset calculation in SF3 soundfonts (`isOgg`) causing `Invalid argument (loopingStartOffsetAt)` during seek and playback.
  - Added `soundfont-kit-vst3` agent skill and updated `soundfont-kit-filters`, `soundfont-kit-playback`, and `soundfont-kit-midi` skills to version 2.

### 1.1.1
- fix web: now it compiles and runs on web
- fix web: add support to drag&drop files also in web

### 1.1.0
- Added Standard MIDI File (`MidiReader` and `MidiPlayer`) support with sample-accurate playback, multi-track parsing, and looping.
- Added RIFF / RMID MIDI container format support.
- Added real-time chord detection (`ChordDetector`), lyric extraction, and tempo map tracking.
- Added channel-level MIDI controls: volume, pan, pitch bend, program change, expression, and mute/solo.
- Unified sustain configuration into a single master `sustain` parameter with natural release envelope fallback.
- Added `baseVolume` parameter to player methods to preserve velocity dynamics independently of channel volume scaling.
- Fixed premature note-off execution and double volume attenuation during MIDI playback.
- Updated default fallback release duration to 250ms for natural acoustic decay.
- Added `soundfont-kit-midi` agent skill.
- Added comprehensive MIDI DAW-style example application with interactive piano roll, real-time FFT visualizer, and channel strips.

### 1.0.2
- removed ".github" for the possible location to install skills

### 1.0.1
- Rename agent skills to hyphenated names for Zed compatibility
- WASM compatibility

### 1.0.0
- First release.
