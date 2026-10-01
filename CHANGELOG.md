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
