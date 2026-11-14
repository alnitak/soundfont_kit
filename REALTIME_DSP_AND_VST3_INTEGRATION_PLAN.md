# `soundfont_kit`: Real-Time Mixer, Isolate Synth, Custom DSP & VST3 Integration Plan

## 1. Executive Summary

Now that **`flutter_soloud`** implements the features from `REALTIME_AUDIO_MIXER_AND_DSP_PLAN.md` and `VST3_PLUGIN_HOSTING_PLAN.md` — specifically:
1. **Retroactive Render-Ahead Ring Re-Mixing (`mRenderRing`)** with sample-accurate `playScheduled`, `fadeScheduled`, `stopScheduled`, and `RealtimeStreamHandle` playing-window splicing,
2. **Lock-Free SPSC `RealtimeStreamHandle` & `RealtimeStreamFeeder` (`SoLoudIsolate` + `RealtimeNativeBuffer`)** with `NEON`/`SSE2` SIMD de-interleaving and 64-sample cosine micro-fades,
3. **8-Slot Custom Native/Wasm/JS Filter Racks (`CustomFilterSlot` `0..7`) & `CustomAudioSource`**, plus new built-in DSP filters (`compressorFilter`, `limiterFilter`, `parametricEqFilter`, `pitchShiftFilter`, `amplitudeModulatorFilter`), and
4. **Desktop VST3 Plugin Hosting (`Vst3Host`, `Vst3EffectPlugin`, `Vst3InstrumentPlugin`)** on macOS, Windows, and Linux,

**`soundfont_kit` can benefit tremendously** — both by fixing architectural bottlenecks in its current playback and MIDI engines, and by unlocking pro-grade SF2/SFZ synthesis and hybrid SoundFont + VST3 studio workflows.

### Why `soundfont_kit` Should Be Upgraded / Refactored

| Current `soundfont_kit` Subsystem | Current Limitation / Issue | How New `flutter_soloud` Features Solve It |
|---|---|---|
| **1. `SampleStreamer` & Engine Init** (`lib/src/player/sample_streamer.dart`, `example/lib/main_*.dart`) | Uses `setBufferStream` (`BufferStream`) for uncached PCM streaming (mutex-locked, no retroactive splicing). Examples initialize SoLoud with `renderAheadFrames: 0` to minimize latency, risking audio underruns under 512-voice polyphony. | Enable **`renderAheadFrames: 1024`** (`devicePeriodFrames: 128`). Because `playScheduled` and `RealtimeStreamHandle` now splice retroactively into the already-rendered playing window, live note-ons achieve **~2.6 ms hardware period latency** while enjoying a **21 ms render-ahead safety cushion**! Upgrade uncompressed PCM streaming in `SampleStreamer` to **`setRealtimeStream` (`RealtimeStreamHandle`)** with SIMD `pushInt16` / `pushFloat32`. |
| **2. `MidiPlayer` Channel FX & `CC 1` Bug** (`lib/src/midi/midi_player.dart` lines 651–664) | Sending `CC 1` (Modulation Wheel) on *any* MIDI channel activates `SoLoud.instance.filters.amplitudeModulatorFilter` **globally on the master output**, modulating all 16 channels (including drums!). `CC 91` (Reverb Send), `CC 93` (Chorus Send), and SF2 generators `91`/`92` are ignored. | Route each of the 16 MIDI channels (`0..15`) through a dedicated SoLoud **`Bus`** (`createMixingBus`). Apply `CC 1` (`amplitudeModulatorFilter` / `vibLfo`), `CC 91` (`freeverbFilter`), `CC 93` (`flangerFilter`), per-channel EQ/Compression, and **per-channel Custom DSP / VST3 Effects** independently per channel bus (`bus.filters.*`) without bleeding across channels! |
| **3. `SoundFontGlobalFilters`** (`lib/src/player/filters/soundfont_filter.dart`) | Only wraps 6 legacy global filters (`biquadResonant`, `echo`, `lofi`, `flanger`, `bassboost`, `freeverb`). Cannot target a mixing `Bus`, and lacks the new `flutter_soloud` filters and custom filter slots. | Refactor into **`SoundFontFilterRack`** targeting either **Global (`FiltersGlobal`)** or **any Mixing `Bus` (`FiltersSingle`)**. Add **`compressor`**, **`limiter`**, **`parametricEq`**, **`pitchShift`**, **`amplitudeModulator`**, and all **8 `CustomFilterSlot`s (`customFilters[0..7]`)** with C++ parameter faders (`fadeFilterParameter`) and LFOs (`oscillateFilterParameter`). |
| **4. SF2 / SFZ Synthesis Fidelity & `MidiPlayer` Timer Jitter** (`lib/src/player/soundfont_player.dart`, `lib/src/models/zone.dart`) | `Sf2Parser` / `SfzParser` already parse `volEnvHold`, `volEnvDecay`, `volEnvSustain`, `modEnv*`, `initialFilterCutoff` (gen 8), and `initialFilterQ` (gen 9), **but `SoundFontPlayer` ignores them**, only applying `volEnvAttack` and `volEnvRelease`! Per-voice filters fail on Web (`SoLoudFilterForSingleSoundOnWebDartException`), and `MidiPlayer` relies on a main-isolate `Timer.periodic(15ms)` subject to UI frame jitter. | **Dual Synthesis Engine**:<br>• **Engine Mode A (Enhanced Voice Handles)**: Full 6-stage DAHDSR scheduled volume fades (`delay` -> `attack` -> `hold` -> `decay` to `sustain` -> `release`), Exclusive Class (`exclusiveClass` gen 57 / SFZ `group`+`off_by` hi-hat choking), and per-channel `Bus` routing.<br>• **Engine Mode B (Worker-Isolate Real-Time Synthesizer via `RealtimeStreamFeeder` & `SoLoudIsolate`)**: Runs polyphonic SF2/SFZ voice rendering + **sample-accurate MIDI sequencer clock** inside a dedicated background Dart `Isolate` using zero-GC `RealtimeNativeBuffer`, computing **per-voice resonant State-Variable Filters (SVF)** (`initialFilterCutoff` + `initialFilterQ` + `modEnvToFilterFc`), **ModEnv -> Pitch**, **ModLFO / VibLFO**, and **instantaneous playing-window splicing** across all 6 platforms (including Web!). |
| **5. Desktop VST3 Effects & Virtual Instruments** (New capability via `Vst3Host`) | `MidiPlayer` and `SoundFontPlayer` can only play SF2/SFZ samples and built-in SoLoud filters. | Integrate **`Vst3Host`**:<br>• **VST3 Insert Effects (`Vst3EffectPlugin`)**: Attach up to 8 VST3 effects to the Master Bus or any MIDI Channel `Bus` (`customFilters[0..7]`), open native plugin GUIs (`openEditorWindow`), automate parameters via SoLoud's C++ faders/LFOs (`mapToSlotParameter`), and save/restore `.vstpreset` chunks.<br>• **Hybrid SoundFont + VST3 Instrument Channels (`Vst3InstrumentPlugin`)**: Assign any MIDI channel (`0..15`) in `MidiPlayer` to a VST3 Virtual Instrument (e.g. Surge XT, Dexed, OB-Xd) playing side-by-side with SoundFont channels, with automatic tempo/transport sync (`setTransport`) and sample-accurate `noteOn`/`noteOff` dispatch! |

---

## 2. Target Architecture Overview

```
                                   ┌──────────────────────────────────────────────────────────┐
                                   │                    MidiPlayer / User App                 │
                                   │  • 16 MIDI Channels (SF2/SFZ Presets OR VST3 Synths)     │
                                   │  • Sample-accurate Isolate Clock OR High-Res Scheduler   │
                                   └────────────┬────────────────────────────────┬────────────┘
                                                │                                │
                      ┌─────────────────────────▼──────────────────────┐         │
                      │       SoundFont Synthesis Engine (Ch 0..15)    │         │  VST3 Instrument Channels
                      │                                                │         │  (Desktop: macOS/Win/Linux)
                      │  ┌──────────────────────────────────────────┐  │         │
                      │  │ Mode A: Enhanced SoLoud Voice Mode       │  │         ▼
                      │  │ • playScheduled (Retroactive Ring Splice)│  │  ┌──────────────────────────────┐
                      │  │ • Full 6-stage DAHDSR Scheduled Fades    │  │  │ Vst3InstrumentPlugin         │
                      │  │ • Exclusive Class (Gen 57) Voice Choking │  │  │ • CustomAudioSource          │
                      │  └────────────────────┬─────────────────────┘  │  │ • Lock-free MIDI Event Ring  │
                      │                       │ OR                     │  │ • Tempo/Transport Sync       │
                      │  ┌────────────────────▼─────────────────────┐  │  └──────────────┬───────────────┘
                      │  │ Mode B: RealtimeSoundFontSynthesizer     │  │                 │
                      │  │ • SoLoudIsolate + RealtimeStreamFeeder   │  │                 │
                      │  │ • Zero-GC RealtimeNativeBuffer (Float32) │  │                 │
                      │  │ • Per-Voice Resonant SVF (Cutoff + Q)    │  │                 │
                      │  │ • Full DAHDSR VolEnv + ModEnv + 2x LFOs  │  │                 │
                      │  │ • Works identically on Native & Web!     │  │                 │
                      │  └────────────────────┬─────────────────────┘  │                 │
                      └───────────────────────┼────────────────────────┘                 │
                                              │                                          │
                                              ▼                                          ▼
                      ┌──────────────────────────────────────────────────────────────────────────────────┐
                      │                   Per-Channel Mixing Buses (Bus 0 .. Bus 15)                     │
                      │  • Per-Channel Volume, Pan, Mute, Solo                                           │
                      │  • CC 1 Mod Wheel (Bus AmplitudeModulator / VibLFO — NO global bleed!)           │
                      │  • CC 91 Reverb Send (Bus Freeverb) & CC 93 Chorus Send (Bus Flanger)            │
                      │  • SoundFontFilterRack (Per-Bus Biquad, ParametricEQ, Compressor, Limiter)       │
                      │  • 8x CustomFilterSlot (Custom Native/Web DSP OR Vst3EffectPlugin Inserts)       │
                      └────────────────────────────────────────┬─────────────────────────────────────────┘
                                                               │
                                                               ▼
                      ┌──────────────────────────────────────────────────────────────────────────────────┐
                      │                     Master Engine Output (FiltersGlobal)                         │
                      │  • SoundFontFilterRack (Master EQ, Compressor, Limiter, Freeverb, etc.)          │
                      │  • 8x Master CustomFilterSlot (Master VST3 Effects Chain / Custom Mastering DSP) │
                      │  • Retroactive Render-Ahead Ring (mRenderRing) -> Audio Hardware Callback        │
                      └──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Phase 1: Engine Configuration, Render-Ahead Ring & `SampleStreamer` Upgrade

### 3.1 Dependency & Engine Initialization Updates
* **File**: `pubspec.yaml`
  * Update `flutter_soloud` dependency to use the new real-time mixer, isolate feeder, custom DSP, and VST3 APIs (using workspace path).
* **File**: `lib/src/player/player_options.dart`
  * Extend `SoundFontPlayerOptions` with synthesis and routing options:
    ```dart
    enum SoundFontSynthMode {
      /// Uses SoLoud AudioSource handles with scheduled 6-stage DAHDSR fades,
      /// retroactive render-ahead splicing, and Exclusive Class choking.
      soloudVoices,

      /// Uses a dedicated worker isolate (`SoLoudIsolate` + `RealtimeStreamFeeder`)
      /// with per-voice resonant State-Variable Filter (SVF), ModEnv, ModLFO/VibLFO,
      /// and sample-accurate modulation on all platforms (including Web).
      realtimeIsolateSynth,
    }
    ```
  * Add `SoundFontSynthMode synthMode = SoundFontSynthMode.soloudVoices` and `int? busId` (default `0` for master, or a dedicated `Bus.busId`) to `SoundFontPlayerOptions`.
* **Files**: `example/lib/main_full.dart` and `example/lib/main_midi.dart`
  * Replace `renderAheadFrames: 0` with `renderAheadFrames: 1024, devicePeriodFrames: 128`.
  * **Why**: In the new `flutter_soloud` mixer, `playScheduled`, `fadeScheduled`, `stopScheduled`, and `RealtimeStreamHandle` retroactively rewrite the already-rendered ahead frames inside `mRenderRing` with a 64-sample cosine micro-fade. Setting `renderAheadFrames: 1024` eliminates main-thread CPU starvation under 512-voice MIDI black-MIDI/orchestral load while keeping live keyboard latency at a single hardware period (~2.6 ms at 48 kHz).

### 3.2 Upgrading `SampleStreamer` with `setRealtimeStream`
* **File**: `lib/src/player/sample_streamer.dart`
* **Current Behavior**:
  * `streamSample` and `streamStereoPcm` use `SoLoud.instance.loadMem` for `pcm16` in-memory samples (which is fast and supports multi-voice seeking/looping), and fall back to `SoLoud.instance.setBufferStream` for `pcm8`, `pcmFloat32`, or uncached streaming.
* **Planned Upgrade**:
  * Add a new method `SampleStreamer.openRealtimeSampleStream(...)` returning a `RealtimeStreamHandle` via `SoLoud.instance.setRealtimeStream(...)`:
    * Uses `BufferType.s16le` for 16-bit PCM or `BufferType.f32le` for 32-bit float PCM.
    * Uses `handle.pushInt16(...)` / `handle.pushFloat32(...)` (backed by C++ `NEON`/`SSE2` SIMD de-interleaving and lock-free SPSC ring buffer) instead of `addAudioDataStream`.
    * Supports `preRollMs: 0.0` so on-demand uncached sample streams splice immediately into the active audio callback window.
  * Keep `loadMem` as the primary path for cached multi-voice `AudioSource` playback in `SoundFontSynthMode.soloudVoices`, and keep `setBufferStream` strictly for compressed `ogg`/`flac` SFZ streams where SoLoud's streaming decoder is needed.

---

## 4. Phase 2: Per-Channel Mixing Buses (`Bus`) & Expanded `SoundFontFilterRack`

### 4.1 Refactoring `SoundFontGlobalFilters` -> `SoundFontFilterRack` (Global & Per-Bus)
* **File**: `lib/src/player/filters/soundfont_filter.dart`
* **Expand `SoundFontFilterType`** to include all built-in SoLoud filters plus the 8 custom DSP / VST3 filter slots:
  ```dart
  enum SoundFontFilterType {
    // Existing filters
    biquadResonant,
    echo,
    lofi,
    flanger,
    bassboost,
    freeverb,
    // New built-in pro DSP filters from flutter_soloud
    compressor,
    limiter,
    parametricEq,
    pitchShift,
    amplitudeModulator,
    // 8 Custom DSP / VST3 Effect insert slots
    customSlot0,
    customSlot1,
    customSlot2,
    customSlot3,
    customSlot4,
    customSlot5,
    customSlot6,
    customSlot7,
  }
  ```
* **Support Both Master (`FiltersGlobal`) and Mixing Bus (`FiltersSingle`)**:
  * Introduce `SoundFontFilterRack`:
    * `SoundFontFilterRack.global()` wraps `SoLoud.instance.filters` (`FiltersGlobal`).
    * `SoundFontFilterRack.forBus(Bus bus)` wraps `bus.filters` (`FiltersSingle`, passing `busHandle: bus.soundHandle`).
    * Keep `typedef SoundFontGlobalFilters = SoundFontFilterRack;` and `player.filters` as a backward-compatible alias so existing user code continues to compile without breaking changes.
  * **Expose Parameter Automation & LFOs**:
    * Add `fadeParameter(SoundFontFilterType type, String paramName, {required double to, required Duration duration})` -> delegates to `param.fadeFilterParameter(to: to, time: duration)`.
    * Add `oscillateParameter(SoundFontFilterType type, String paramName, {required double from, required double to, required Duration period})` -> delegates to `param.oscillateFilterParameter(from: from, to: to, time: period)`.
  * **Expose `CustomFilterSlot` Access**:
    * Add `CustomFilterSlot customSlot(int index)` (`0..7`) on `SoundFontFilterRack` so users can attach custom native C/Wasm/JS DSP callbacks (`setNativeCallback` / `setWebCallback`) or desktop `Vst3EffectPlugin` instances directly to either the Master rack or a specific `SoundFontPlayer` / MIDI Channel `Bus`.

### 4.2 Dedicated Mixing `Bus` per `SoundFontPlayer` & per `MidiPlayer` Channel
* **File**: `lib/src/player/soundfont_player.dart`
  * Allow a `SoundFontPlayer` to optionally own or attach to a SoLoud `Bus` (`Bus? mixingBus`), with a `SoundFontFilterRack get busFilters` getter.
  * In `_playZone` (and `playPreset` / `playSample`), pass `busId: targetBusId ?? mixingBus?.busId ?? _options.busId ?? 0` to `SoLoud.instance.playScheduled(...)`.
* **Files**: `lib/src/midi/midi_channel_state.dart` and `lib/src/midi/midi_player.dart`
  * Each of the 16 `MidiChannelState` instances (`0..15`) lazily or eagerly creates a dedicated SoLoud `Bus` (`SoLoud.instance.createMixingBus(name: 'MIDI Ch ${ch + 1}')..playOnEngine()`).
  * Expose `SoundFontFilterRack get filterRack` and `Bus get bus` on `MidiChannelState`.
  * **Fix the Global `CC 1` Modulation Wheel Bug** (`lib/src/midi/midi_player.dart` lines 651–664):
    * Remove the global `SoLoud.instance.filters.amplitudeModulatorFilter` hack in `_handleControlChange(channel, 1, value)`.
    * Instead, apply `CC 1` **strictly to `channel`'s own voices/bus**:
      * In `soloudVoices` mode: modulate `channelState.bus.filters.amplitudeModulatorFilter` (or per-voice vibrato LFO / pitch), affecting *only* that MIDI channel!
      * In `realtimeIsolateSynth` mode: route `CC 1` directly to the SF2/SFZ VibLFO / ModLFO depth on that channel (per SF2 specification default modulator: CC 1 -> VibLFO to Pitch, 50 cents).
  * **Implement `CC 91` (Reverb Send) & `CC 93` (Chorus Send) + SF2 Generators `91` & `92`**:
    * On each channel `Bus` (or dedicated Aux Reverb/Chorus Buses):
      * `CC 91` (`0..127`) + zone `reverbEffectsSend` (`0..1000` tenths of a percent) controls the wet level (`0.0..1.0`) of `channelBus.filters.freeverbFilter` (activating on non-zero, setting `wet: 0` when zero).
      * `CC 93` (`0..127`) + zone `chorusEffectsSend` (`0..1000`) controls the wet level (`0.0..1.0`) of `channelBus.filters.flangerFilter`.

---

## 5. Phase 3: Full SF2 / SFZ Synthesis Fidelity & Worker-Isolate Real-Time Engine

### 5.1 Completing SF2 & SFZ Zone Parameter Extraction
* **File**: `lib/src/models/zone.dart`
  * `Zone` already stores `volEnvAttack`, `volEnvHold`, `volEnvDecay`, `volEnvSustain`, `volEnvRelease`, `modEnvAttack`, `modEnvHold`, `modEnvDecay`, `modEnvSustain`, `modEnvRelease`, `initialFilterCutoff`, and `initialFilterQ`.
  * Add the remaining essential SF2 generators / SFZ opcodes to `Zone`:
    * `double? volEnvDelay` (SF2 gen `33` `delayVolEnv`, SFZ `ampeg_delay`)
    * `double? modEnvDelay` (SF2 gen `25` `delayModEnv`, SFZ `fileg_delay` / `pitcheg_delay`)
    * `int? modEnvToPitch` (SF2 gen `7`, cents, `-12000..12000`, SFZ `pitcheg_depth`)
    * `int? modEnvToFilterFc` (SF2 gen `11`, cents, `-12000..12000`, SFZ `fileg_depth`)
    * `double? modLfoDelay` (SF2 gen `21` `delayModLFO`, seconds)
    * `double? modLfoFreq` (SF2 gen `22` `freqModLFO`, Hz, default `8.176 Hz`)
    * `int? modLfoToPitch` (SF2 gen `5`, cents)
    * `int? modLfoToFilterFc` (SF2 gen `10`, cents)
    * `double? modLfoToVolume` (SF2 gen `13`, centibels -> dB)
    * `double? vibLfoDelay` (SF2 gen `23` `delayVibLFO`, seconds)
    * `double? vibLfoFreq` (SF2 gen `24` `freqVibLFO`, Hz, default `8.176 Hz`)
    * `int? vibLfoToPitch` (SF2 gen `6`, cents, plus CC 1 Mod Wheel depth)
    * `int? exclusiveClass` (SF2 gen `57` `exclusiveClass`, SFZ `group` / `off_by` — critical for hi-hat choke groups!)
    * `double? reverbSend` (SF2 gen `91`, `0.0..1.0`, SFZ `effect1`)
    * `double? chorusSend` (SF2 gen `92`, `0.0..1.0`, SFZ `effect2`)
* **Files**: `lib/src/parsers/sf2_parser.dart`, `lib/src/parsers/sfz_parser.dart`, `lib/src/player/voice_calculator.dart`
  * Extract the above generators in `Sf2Parser._createZone` and `SfzParser._finalizeRegion`.
  * Update `VoiceCalculator.mergeZones` and `VoiceCalculator.calculateParameters` to merge instrument + preset zone offsets and apply velocity/key scaling (`keynumToVolEnvHold` gen `39`, `keynumToVolEnvDecay` gen `40`, `keynumToModEnvHold` gen `31`, `keynumToModEnvDecay` gen `32`).

### 5.2 Mode A Enhancements: Full Scheduled DAHDSR & Exclusive Class Choking (`SoundFontSynthMode.soloudVoices`)
* **File**: `lib/src/player/soundfont_player.dart`
  * **Exclusive Class Voice Choking (`exclusiveClass`)**:
    * When a zone with `exclusiveClass != null && exclusiveClass! > 0` is triggered on a channel/player, immediately locate any active `SoundFontVoice` with the same `exclusiveClass` (or matching `offBy` group in SFZ) and choke it with a fast 5 ms anti-click scheduled fade (`fadeScheduled` + `stopScheduled`). This makes GM Drum kits (Open Hi-Hat #46 choked by Closed Hi-Hat #42 or Pedal Hi-Hat #44) sound authentic immediately.
  * **Full Scheduled DAHDSR Volume Envelope**:
    * Currently, `_playZone` only schedules `volEnvAttack` (ramping from `0` to `peakGain`) and leaves the voice at `peakGain` indefinitely until `noteOff`, ignoring `volEnvHold`, `volEnvDecay`, and `volEnvSustain` (which makes plucked/percussive instruments like pianos, guitars, harps, and timpani sustain forever like an organ!).
    * Upgrade `SoundFontVoice` to schedule the complete DAHDSR trajectory:
      1. **Delay (`volEnvDelay`)**: Delay `playScheduled` start time by `delay`.
      2. **Attack (`volEnvAttack`)**: Ramp volume from `0.0` to `peakGain` over `attack`.
      3. **Hold (`volEnvHold`)**: Hold `peakGain` for `hold` duration.
      4. **Decay -> Sustain (`volEnvDecay`, `volEnvSustain`)**: Schedule a volume fade from `peakGain` down to `sustainGain = peakGain * pow(10, -volEnvSustainDb / 20)` over `decay` duration.
      5. **Release (`volEnvRelease`)**: On `noteOff`, fade from current gain to `0.0` over `release` and stop.

### 5.3 Mode B: Worker-Isolate Real-Time SoundFont Synthesizer (`RealtimeSoundFontSynthesizer`)
* **New File**: `lib/src/player/realtime_synthesizer.dart`
* **Why**:
  * While Mode A (`soloudVoices`) is great for lightweight playback, SoLoud's per-handle architecture cannot execute **per-voice resonant low-pass filters (`initialFilterCutoff` + `initialFilterQ`)** on Web, nor can it continuously modulate per-voice filter cutoff via **ModEnv (`modEnvToFilterFc`)** and **ModLFO (`modLfoToFilterFc`)** at audio rate without main-isolate timer overhead.
  * Using `flutter_soloud`'s new **`SoLoud.instance.setRealtimeStream(...)`** + **`RealtimeStreamHandle.startFloat32Feeder<SynthState>(...)`** (`SoLoudIsolate` + `RealtimeNativeBuffer`), `soundfont_kit` can run a **100% pure-Dart, zero-GC, sample-accurate polyphonic SF2/SFZ DSP synthesizer inside a background worker isolate** (or main chunked loop on Web)!
* **Architecture of `RealtimeSoundFontSynthesizer`**:
  1. **Zero-Copy / Shared Sample Pool**:
     * Decoded sample data (`Int16List` or `Float32List`) and zone tables are passed to the worker isolate (`TransferableTypedData` or shared state).
  2. **Per-Voice DSP Pipeline inside `_synthAudioChunk(SynthState state, RealtimeNativeBuffer out, int framesToWrite)`**:
     * **Cubic Hermite / 4-Point Pitch Interpolation**: Smooth fractional phase increment (`phase += playbackRate`) modulated at control rate (every 32/64 samples) by:
       $$\text{pitchCents} = \text{basePitchCents} + \text{pitchBendCents} + \text{modEnvLevel} \times \text{modEnvToPitch} + \text{modLfoVal} \times \text{modLfoToPitch} + \text{vibLfoVal} \times \text{vibLfoToPitch}$$
     * **6-Stage DAHDSR Volume Envelope & 6-Stage DAHDSR Modulation Envelope**:
       * Sample-accurate state machines (`delay` -> `attack` (convex/linear) -> `hold` -> `decay` (exponential) -> `sustain` -> `release` (exponential)).
     * **Per-Voice Chamberlin / Cytomic TPT State-Variable Filter (SVF)**:
       * 2-pole (12 dB/oct) resonant low-pass filter per voice.
       * Dynamic cutoff in cents:
         $$\text{fcCents} = \text{initialFilterCutoffCents} + \text{velToFilterFc} + \text{keyToFilterFc} + \text{modEnvLevel} \times \text{modEnvToFilterFc} + \text{modLfoVal} \times \text{modLfoToFilterFc}$$
       * Resonance $Q$ from `initialFilterQ` (`0..960` centibels = `0..96 dB`).
       * Bypassed automatically when `initialFilterCutoff >= 13500` cents (~20 kHz) and `initialFilterQ == 0` to save CPU.
     * **Constant-Power Stereo Panning & Per-Channel Bus / Reverb / Chorus Accumulation**:
       * Writes interleaved stereo `Float32` directly into `RealtimeNativeBuffer` (`out[i] = ...`) with **zero Dart heap allocations per audio block**.
  3. **Instantaneous Playing-Window Injection & Sample-Accurate MIDI Sequencer**:
     * Live `noteOn` / `noteOff` / `CC` events sent via `feeder.sendCommand(...)` (or scheduled inside the worker isolate) can call `pushNativeScheduledFloat32` / `pushNativeClockedFloat32` to splice into the active render-ahead ring (`mRenderRing`) with sub-millisecond latency.
     * **`MidiPlayer` Sample-Accurate Sequencer Mode**: When `MidiPlayer` uses `RealtimeSoundFontSynthesizer`, the MIDI event list can be transferred to the worker isolate and stepped by the **exact audio frame counter** (`currentFrame`) inside `_synthAudioChunk` (just like `isolate_drum_sequencer.dart`), achieving **0.00 ms sequencer jitter** even if the Flutter UI thread drops frames!

---

## 6. Phase 4: Desktop VST3 Plugin Hosting Integration (`Vst3Host`)

### 6.1 `SoundFontVst3Manager` (`lib/src/player/vst3/soundfont_vst3_manager.dart`)
* Create a dedicated manager class in `soundfont_kit` that wraps `flutter_soloud`'s `Vst3Host` (`package:flutter_soloud/flutter_soloud.dart`) and safely checks `Vst3Host.isSupported` (returning `true` on macOS, Windows, and Linux; gracefully no-op/unsupported on Web, iOS, and Android).
* **Capabilities**:
  1. **Plugin Discovery (`scanPlugins`)**:
     * Wraps `Vst3Host.instance.scanStandardLocations()` and `scanDirectory(customPath)` to list installed `.vst3` effects (`isEffect`) and instruments (`isInstrument`).
  2. **VST3 Insert Effects (`Vst3EffectPlugin`) on Master or Per-Channel Buses**:
     * `Future<Vst3EffectPlugin> loadMasterEffect({required int slotIndex, required String modulePath, String? classId})`:
       * Loads the `.vst3` effect into `SoLoud.instance.filters.customFilters[slotIndex]` (`0..7`).
     * `Future<Vst3EffectPlugin> loadChannelEffect({required int channel, required int slotIndex, required String modulePath, String? classId})`:
       * Loads the `.vst3` effect into `midiPlayer.channels[channel].bus.filters.customFilters[slotIndex]` (`0..7`).
     * Supports:
       * **Native Plugin GUI**: `plugin.hasEditor`, `plugin.openEditorWindow(title: ...)`, `plugin.closeEditorWindow()`.
       * **Bidirectional Parameter Sync & C++ Automation**:
         * `plugin.onGuiParameterChanged` stream to update Flutter sliders at 30 Hz when the user turns knobs in the native VST3 GUI.
         * `plugin.mapToSlotParameter(slotParamIndex: 0..3, vstParamId: id)` so SoLoud's C++ faders (`fadeFilterParameter`) and LFOs (`oscillateFilterParameter`) can automate any VST3 knob at audio rate!
       * **Preset State Persistence**: `plugin.saveState()` / `plugin.restoreState(Uint8List)` to save and load full DAW-style channel strip presets in `soundfont_kit`.

### 6.2 Hybrid SoundFont + VST3 Instrument Channels in `MidiPlayer`
* **Files**: `lib/src/midi/midi_channel_state.dart` and `lib/src/midi/midi_player.dart`
* **Extend `MidiChannelState`**:
  * Alongside `SoundFontPlayer? customPlayer` and `Preset? presetOverride`, add:
    ```dart
    /// Optional desktop VST3 virtual instrument assigned to this MIDI channel.
    /// When non-null, MIDI notes, pitch bend, and CCs on this channel are routed
    /// directly to the VST3 instrument instead of the SoundFont player!
    Vst3InstrumentPlugin? vst3Instrument;
    ```
* **Extend `MidiPlayer`**:
  * Add `void setChannelVst3Instrument(int channel, Vst3InstrumentPlugin? instrument, {Bus? targetBus})`:
    * Starts the `Vst3InstrumentPlugin` on the channel's mixing `Bus` (`instrument.play(busId: channelState.bus.busId)`) so per-channel volume, pan, and insert FX work identically for both SoundFont and VST3 channels!
  * **Route MIDI Events to `Vst3InstrumentPlugin`**:
    * In `_handleNoteOn`: If `channelState.vst3Instrument != null`, call `channelState.vst3Instrument!.noteOn(pitch: note, velocity: velocity / 127.0, channel: channel)` (lock-free SPSC MIDI ring buffer in C++!).
    * In `_handleNoteOff`: If `channelState.vst3Instrument != null`, call `channelState.vst3Instrument!.noteOff(pitch: note, channel: channel)`.
    * In `stop()` / `seek()` / `_stopAllChannelVoices()`: Send `noteOff` for active notes on `vst3Instrument`.
  * **Automatic Tempo & Transport Synchronization**:
    * Whenever `MidiPlayer` starts playback (`play()`), pauses (`pause()`), stops (`stop()`), seeks (`seek()`), or encounters a MIDI Tempo Meta Event (`0x51`) / Time Signature Meta Event (`0x58`), broadcast:
      ```dart
      plugin.setTransport(
        bpm: currentBpm,
        timeSigNumerator: numerator,
        timeSigDenominator: denominator,
        projectTimeSamples: currentSamplePos,
        projectTimeQuarters: currentQuarterNotePos,
        isPlaying: isPlaying,
      );
      ```
      to all active `Vst3InstrumentPlugin` and `Vst3EffectPlugin` instances! Tempo-synced VST3 arpeggiators, LFOs, and delay plugins will lock automatically to the MIDI file's tempo map.

---

## 7. Phase 5: Built-In Custom DSP Effects (`CustomFilterSlot`) for SoundFonts

Even on platforms without VST3 (Web, iOS, Android) — or on Desktop without external `.vst3` files installed — `soundfont_kit` can ship **ready-to-use SoundFont-specific custom DSP processors** built on `CustomFilterSlot`:
* **New File**: `lib/src/player/filters/soundfont_custom_dsp.dart`
  * Provides pre-configured custom effects that attach to any `CustomFilterSlot` (`0..7`) on Master or Per-Channel Buses:
    1. **Vintage Sampler DAC Emulator (12-bit / E-mu SP-1200 / S950 Grit)**:
       * Uses `CustomFilterSlot` parameters for Bit Depth (`4..16` bits), Sample-Rate Decimation (`1..32x`), and Warmth Saturation (`tanh` soft clipper) to give clean SF2/SFZ instruments classic 90s hardware sampler character.
    2. **True Stereo Dimension Chorus (Roland SDD-320 / SoundFont Chorus Upgrade)**:
       * Quadrature stereo modulated delay lines on `CustomFilterSlot` for rich stereo widening of mono SF2 samples.

---

## 8. Phase 6: Example Apps & Agent Skills Updates

### 8.1 Example Apps (`example/lib/main_full.dart` & `example/lib/main_midi.dart`)
1. **`example/lib/main_full.dart`**:
   * Update SoLoud init to `renderAheadFrames: 1024, devicePeriodFrames: 128`.
   * Add a **Synth Mode Toggle** (`SoLoud Voices (DAHDSR)` vs. `Realtime Isolate Synth (SVF + ModEnv + LFO)`).
   * Expand the **Filter Dialog (`_showFiltersDialog`)** to include the new `compressor`, `limiter`, `parametricEq`, `pitchShift`, `amplitudeModulator`, and a **VST3 Effect Slot Loader** (on Desktop, with `"Open VST3 GUI"` button).
2. **`example/lib/main_midi.dart`**:
   * Show per-channel **Reverb (`CC 91`)** and **Chorus (`CC 93`)** send indicators on each channel row.
   * In `ChannelInstrumentPickerDialog`, add a **"VST3 Instrument"** tab (on Desktop) allowing the user to assign any scanned `.vst3` synth (e.g., Surge XT, Dexed) to any of the 16 MIDI channels alongside SF2/SFZ channels, plus a button to open its native VST3 editor window and per-channel FX rack!

### 8.2 Agent Skills (`skills/`)
* Update `skills/soundfont-kit-filters/SKILL.md`:
  * Document `SoundFontFilterRack` (Global vs. Per-Bus), the new built-in filters (`compressor`, `limiter`, `parametricEq`, `pitchShift`, `amplitudeModulator`), parameter automation (`fadeParameter`, `oscillateParameter`), and `CustomFilterSlot` (`0..7`).
* Update `skills/soundfont-kit-midi/SKILL.md` and `skills/soundfont-kit-playback/SKILL.md`:
  * Document `SoundFontSynthMode.realtimeIsolateSynth`, per-channel `Bus` routing, Exclusive Class choking, and hybrid SoundFont + `Vst3InstrumentPlugin` MIDI channels.
* Create `skills/soundfont-kit-vst3/SKILL.md`:
  * Dedicated guide for scanning, loading, automating, and opening native editor windows for `Vst3EffectPlugin` and `Vst3InstrumentPlugin` in `soundfont_kit`.

---

## 9. Step-by-Step Implementation Checklist

- [x] **Phase 1: Engine & `SampleStreamer` Real-Time Upgrade**
  - [x] Update `pubspec.yaml` to reference the updated `flutter_soloud` package.
  - [x] Add `SoundFontSynthMode` and `busId` to `SoundFontPlayerOptions` (`lib/src/player/player_options.dart`).
  - [x] Add `openRealtimeSampleStream` using `SoLoud.instance.setRealtimeStream` (`RealtimeStreamHandle`) to `SampleStreamer` (`lib/src/player/sample_streamer.dart`).
  - [x] Update `example/lib/main_full.dart` and `example/lib/main_midi.dart` to use `renderAheadFrames: 1024, devicePeriodFrames: 128`.
- [x] **Phase 2: Per-Channel Mixing Buses (`Bus`) & `SoundFontFilterRack`**
  - [x] Upgrade `lib/src/player/filters/soundfont_filter.dart` (`SoundFontFilterRack` supporting both `FiltersGlobal` and `Bus` `FiltersSingle`, adding `compressor`, `limiter`, `parametricEq`, `pitchShift`, `amplitudeModulator`, `customSlot0..7`, `fadeParameter`, and `oscillateParameter`).
  - [x] Add optional `Bus` routing to `SoundFontPlayer` (`lib/src/player/soundfont_player.dart`).
  - [x] Give each `MidiChannelState` (`lib/src/midi/midi_channel_state.dart`) a dedicated `Bus` and `SoundFontFilterRack`, fix the global `CC 1` Modulation Wheel bug in `MidiPlayer` (`lib/src/midi/midi_player.dart`), and wire up `CC 91` (Reverb Send) & `CC 93` (Chorus Send).
- [x] **Phase 3: Complete SF2/SFZ Envelope/Filter/LFO Parsing, Exclusive Class & `RealtimeSoundFontSynthesizer`**
  - [x] Add `volEnvDelay`, `modEnvDelay`, `modEnvToPitch`, `modEnvToFilterFc`, `modLfo*`, `vibLfo*`, `exclusiveClass`, `reverbSend`, and `chorusSend` to `Zone` (`lib/src/models/zone.dart`), `Sf2Parser` (`lib/src/parsers/sf2_parser.dart`), `SfzParser` (`lib/src/parsers/sfz_parser.dart`), and `VoiceCalculator` (`lib/src/player/voice_calculator.dart`).
  - [x] Implement Exclusive Class (`exclusiveClass` / `off_by`) voice choking and full 6-stage scheduled DAHDSR envelopes in `SoundFontPlayer` (`lib/src/player/soundfont_player.dart`) and `SoundFontVoice` (`lib/src/player/soundfont_voice.dart`).
  - [x] Implement `RealtimeSoundFontSynthesizer` (`lib/src/player/realtime_synthesizer.dart`) using `RealtimeStreamHandle.startFloat32Feeder` (`SoLoudIsolate` + `RealtimeNativeBuffer`) with per-voice resonant State-Variable Filter (SVF), DAHDSR VolEnv & ModEnv, ModLFO & VibLFO, and sample-accurate MIDI sequencer clock.
- [x] **Phase 4: Desktop VST3 Plugin Hosting Integration (`SoundFontVst3Manager`)**
  - [x] Create `lib/src/player/vst3/soundfont_vst3_manager.dart` wrapping `Vst3Host`, `Vst3EffectPlugin`, and `Vst3InstrumentPlugin`.
  - [x] Add `vst3Instrument` support and automatic `setTransport` (BPM / time signature / play state) sync to `MidiChannelState` and `MidiPlayer`.
  - [x] Export new classes from `lib/soundfont_kit.dart`.
- [x] **Phase 5: Example UI & Skills**
  - [x] Update `example/lib/main_full.dart` and `example/lib/main_midi.dart` with the expanded Filter/VST3 rack, Synth Mode selector, and VST3 Instrument channel assignment.
  - [x] Update `skills/soundfont-kit-filters/SKILL.md`, `skills/soundfont-kit-midi/SKILL.md`, `skills/soundfont-kit-playback/SKILL.md`, and add `skills/soundfont-kit-vst3/SKILL.md`.
  - [x] Run `dart analyze` and unit/integration tests across `soundfont_kit`.

