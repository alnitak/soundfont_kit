### 1.2.0
- **Dual Synthesis Engine (`SoundFontSynthMode`)**:
  - `soloudVoices` (default): added full 6-stage DAHDSR volume envelopes, exclusive class voice choking (e.g., hi-hats), and optional per-voice low-pass filtering (`enablePerVoiceFilter`).
  - `realtimeIsolateSynth` (new): sample-accurate background isolate synthesizer with Volume & Modulation envelopes, resonant State-Variable Filters (SVF), and LFOs across all platforms (including Web).
- **Global & Per-Bus Filter Rack (`SoundFontFilterRack`)**:
  - Support for both global master (`SoundFontFilterRack.global()`) and per-bus (`SoundFontFilterRack.forBus()`) effect chains.
  - Added `compressor`, `limiter`, `parametricEq`, `pitchShift`, `amplitudeModulator`, and 8 custom DSP/VST3 slots (`customSlot0`..`customSlot7`), plus parameter automation (`fadeParameter`, `oscillateParameter`).
- **Per-Channel Mixing Buses in `MidiPlayer`**:
  - Each MIDI channel now routes through its own `Bus` with an independent `filterRack`, isolated `CC 1` (Modulation Wheel), `CC 91` (Reverb Send), and `CC 93` (Chorus Send).
- **Desktop VST3 Plugin Hosting (`SoundFontVst3Manager`)**:
  - Scan and load `.vst3` audio effects and virtual instruments on macOS, Windows, and Linux, with native plugin GUI editor support and hybrid SoundFont + VST3 playback in `MidiPlayer`.
- **Low-Latency `SampleStreamer`**:
  - Added `openRealtimeSampleStream` and `openRealtimeStereoPcmStream` for low-latency real-time PCM streaming.
- **Fixes & Skills**:
  - Fixed SF3 loop offset calculation during seek and playback.
  - Added `soundfont-kit-vst3` agent skill and updated existing skills.

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
