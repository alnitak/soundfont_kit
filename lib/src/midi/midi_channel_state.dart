// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_soloud/flutter_soloud.dart';
import '../models/preset.dart';
import '../player/filters/soundfont_filter.dart';
import '../player/soundfont_player.dart';
import '../player/soundfont_voice.dart';
import '../soundfont_file.dart';
import 'general_midi.dart';
import 'midi_models.dart';

/// Manages dynamic synthesis and controller state for an individual MIDI channel (0-15).
class MidiChannelState {
  /// MIDI channel number (0-15).
  final int channel;

  /// Current MIDI Bank number (default 0, channel 9 / MIDI ch 10 defaults to 128).
  int bank;

  /// Bank Select MSB (CC 0).
  int bankMsb = 0;

  /// Bank Select LSB (CC 32).
  int bankLsb = 0;

  /// Current Program / Patch number (0-127).
  int program;

  /// Channel volume multiplier (0.0 to 1.0), derived from CC 7 (default 100/127 ≈ 0.787).
  double volume;

  /// Expression multiplier (0.0 to 1.0), derived from CC 11 (default 1.0).
  double expression;

  /// Stereo pan position (-1.0 left, 0.0 center, 1.0 right), derived from CC 10 (default 0.0).
  double pan;

  /// Normalized pitch bend offset (-1.0 to +1.0, default 0.0).
  double pitchBend;

  /// Pitch bend sensitivity range in semitones (default 2.0).
  double pitchBendRangeSemitones;

  /// Modulation depth multiplier (0.0 to 1.0), derived from CC 1 (Modulation Wheel).
  double modulation;

  /// Reverb send level (0.0 to 1.0), derived from CC 91.
  double reverbSend;

  /// Chorus send level (0.0 to 1.0), derived from CC 93.
  double chorusSend;

  /// Whether the sustain (damper) pedal is currently engaged (CC 64 >= 64).
  bool isSustainPedalOn;

  /// Whether the sostenuto pedal is currently engaged (CC 66 >= 64).
  bool isSostenutoPedalOn;

  /// Whether the soft pedal (una corda) is engaged (CC 67 >= 64).
  bool isSoftPedalOn;

  /// Channel semitone transpose offset.
  int transpose;

  /// Whether this channel is muted.
  bool isMuted;

  /// Whether this channel is in solo mode.
  bool isSolo;

  /// Optional custom [SoundFontPlayer] for this channel.
  SoundFontPlayer? customPlayer;

  /// Optional preset override for this channel.
  Preset? presetOverride;

  /// Optional desktop VST3 Virtual Instrument assigned specifically to this MIDI channel.
  /// When non-null, MIDI notes on this channel are routed to the VST3 synth!
  Vst3InstrumentPlugin? vst3Instrument;

  /// Human-readable display name for the assigned [vst3Instrument].
  String? vst3InstrumentName;

  /// Optional shared multi-timbral VST3 Virtual Instrument serving all 16 MIDI channels
  /// (e.g., Steinberg HALion Sonic).
  Vst3InstrumentPlugin? sharedVst3Instrument;

  /// Human-readable display name for [sharedVst3Instrument].
  String? sharedVst3InstrumentName;

  /// Effective VST3 instrument for this channel (per-channel [vst3Instrument] if set,
  /// otherwise the multi-timbral [sharedVst3Instrument] unless a SoundFont [presetOverride] is set).
  Vst3InstrumentPlugin? get effectiveVst3Instrument {
    if (vst3Instrument != null && !vst3Instrument!.isDisposed) {
      return vst3Instrument;
    }
    if (presetOverride == null &&
        sharedVst3Instrument != null &&
        !sharedVst3Instrument!.isDisposed) {
      return sharedVst3Instrument;
    }
    return null;
  }

  /// Active SoLoud voice handle playing [vst3Instrument]'s custom audio source.
  SoundHandle? vst3PlayHandle;

  /// Active MIDI notes currently sounding on [vst3Instrument].
  final Set<int> activeVst3Notes = {};

  /// Notes on [vst3Instrument] deferred by the sustain pedal (CC 64).
  final Set<int> sustainedVst3Notes = {};

  Bus? _bus;

  /// Returns this channel's dedicated SoLoud mixing [Bus] if already created, or `null`.
  Bus? get bus => _bus;

  /// Lazily creates and starts a dedicated SoLoud mixing [Bus] for this MIDI channel (`0..15`).
  Bus ensureBus() {
    if (_bus != null) {
      if (!_bus!.isActive && SoLoud.instance.isInitialized) {
        _bus!.playOnEngine();
      }
      return _bus!;
    }
    final created = SoLoud.instance.createMixingBus(
      name: 'MIDI Ch ${channel + 1}',
    );
    if (SoLoud.instance.isInitialized) {
      created.playOnEngine();
    }
    _bus = created;
    return created;
  }

  /// Effective SoLoud `busId` for voices played on this channel (`0` if no bus created yet).
  int get effectiveBusId =>
      (_bus != null && _bus!.isActive) ? _bus!.busId : 0;

  /// Per-channel [SoundFontFilterRack] (lazily initializes this channel's mixing [Bus]).
  SoundFontFilterRack get filterRack => SoundFontFilterRack.forBus(ensureBus());

  /// Currently sounding voices keyed by MIDI note.
  final Map<int, List<SoundFontVoice>> activeVoices = {};

  /// Voices currently fading out during release keyed by MIDI note.
  final Map<int, List<SoundFontVoice>> releasingVoices = {};

  /// Voices whose NoteOff was received while sustain pedal was held down.
  final List<SoundFontVoice> sustainedVoices = [];

  /// Voices captured when sostenuto pedal was depressed.
  final Set<SoundFontVoice> sostenutoVoices = {};

  /// Set of MIDI keys currently held down on this channel.
  final Set<int> heldNotes = {};

  /// Scheduled engine time for a NoteOff that arrived while an async NoteOn was still spawning.
  final Map<int, Duration?> pendingNoteOffAt = {};

  /// Creates a [MidiChannelState] for the 0-based MIDI [channel] (`0..15`).
  MidiChannelState({
    required this.channel,
    int? bank,
    this.program = 0,
    this.volume = 100.0 / 127.0,
    this.expression = 1.0,
    this.pan = 0.0,
    this.pitchBend = 0.0,
    this.pitchBendRangeSemitones = 2.0,
    this.modulation = 0.0,
    this.reverbSend = 0.0,
    this.chorusSend = 0.0,
    this.isSustainPedalOn = false,
    this.isSostenutoPedalOn = false,
    this.isSoftPedalOn = false,
    this.transpose = 0,
    this.isMuted = false,
    this.isSolo = false,
    this.customPlayer,
    this.presetOverride,
    this.vst3Instrument,
    this.vst3InstrumentName,
  }) : bank = bank ?? (channel == 9 ? 128 : 0);

  /// Current relative pitch bend playback speed multiplier ($2^{\frac{\text{semitones} \times \text{bend}}{12}}$).
  double get pitchBendMultiplier {
    if (pitchBend == 0.0) return 1.0;
    return math
        .pow(2.0, (pitchBend * pitchBendRangeSemitones) / 12.0)
        .toDouble();
  }

  /// Computes the effective gain taking into account mute status, volume, expression, and soft pedal.
  double get effectiveVolume {
    if (isMuted) return 0.0;
    final base = volume * expression;
    return isSoftPedalOn ? base * 0.75 : base;
  }

  /// Marks a note as actively pressed on this channel.
  void markNoteOn(int key) {
    heldNotes.add(key);
    pendingNoteOffAt.remove(key);
  }

  /// Registers a newly triggered voice for [key], applying current channel controllers.
  void addVoice(int key, SoundFontVoice voice) {
    if (pitchBend != 0.0) {
      voice.applyPitchBend(pitchBendMultiplier);
    }

    // Dampen existing active, sustained, or releasing voices for the same key to avoid voice accumulation
    sustainedVoices.removeWhere((prev) {
      if (prev.key == key) {
        prev.release(customRelease: const Duration(milliseconds: 15));
        return true;
      }
      return false;
    });
    sostenutoVoices.removeWhere((prev) {
      if (prev.key == key) {
        prev.release(customRelease: const Duration(milliseconds: 15));
        return true;
      }
      return false;
    });
    final prevVoices = activeVoices[key];
    if (prevVoices != null && prevVoices.isNotEmpty) {
      for (final prev in prevVoices) {
        prev.release(customRelease: const Duration(milliseconds: 15));
      }
      prevVoices.clear();
    }
    final prevReleasing = releasingVoices.remove(key);
    if (prevReleasing != null && prevReleasing.isNotEmpty) {
      for (final prev in prevReleasing) {
        prev.release(customRelease: const Duration(milliseconds: 15));
      }
    }

    if (!heldNotes.contains(key)) {
      final offAt = pendingNoteOffAt.remove(key);
      if (isSustainPedalOn) {
        sustainedVoices.add(voice);
      } else {
        final releasingList = releasingVoices.putIfAbsent(key, () => []);
        releasingList.add(voice);
        final fade = voice.releaseDuration;
        Timer(fade + const Duration(milliseconds: 50), () {
          releasingVoices[key]?.remove(voice);
        });
        voice.release(atTime: offAt);
      }
      return;
    }
    activeVoices.putIfAbsent(key, () => []).add(voice);
  }

  /// Triggers a Note-On on the assigned per-channel or shared multi-timbral VST3 instrument if present.
  void triggerVst3NoteOn(int key, int velocity) {
    final inst = effectiveVst3Instrument;
    if (inst == null || inst.isDisposed) return;

    final isPerChannelInst = vst3Instrument != null && !vst3Instrument!.isDisposed;
    if (isPerChannelInst) {
      // Ensure the per-channel VST3 instrument's custom audio source is playing on the channel bus
      if (SoLoud.instance.isInitialized &&
          (vst3PlayHandle == null ||
              !SoLoud.instance.getIsValidVoiceHandle(vst3PlayHandle!))) {
        final b = ensureBus();
        vst3PlayHandle = SoLoud.instance.play(
          inst.audioSource,
          volume: effectiveVolume,
          pan: pan,
          busId: b.busId,
        );
      }
    }

    sustainedVst3Notes.remove(key);
    activeVst3Notes.add(key);
    final rawVel = (velocity / 127.0).clamp(0.0, 1.0);
    final scaledVel = isPerChannelInst
        ? rawVel
        : (rawVel * effectiveVolume).clamp(0.0, 1.0);
    try {
      inst.noteOn(
        pitch: key,
        velocity: scaledVel,
        channel: channel,
      );
    } catch (_) {}
  }

  /// Handles Note-Off for [key]. If sustain or sostenuto pedal is pressed, the voice is marked for delayed release.
  Future<void> handleNoteOff(
    int key, {
    Duration? releaseDuration,
    Duration? atTime,
  }) async {
    heldNotes.remove(key);
    final inst = effectiveVst3Instrument;
    if (inst != null && !inst.isDisposed) {
      if (isSustainPedalOn) {
        sustainedVst3Notes.add(key);
      } else if (activeVst3Notes.remove(key)) {
        try {
          inst.noteOff(pitch: key, channel: channel);
        } catch (_) {}
      }
    }
    final voices = activeVoices.remove(key);
    if (voices == null || voices.isEmpty) {
      pendingNoteOffAt[key] = atTime;
      return;
    }
    pendingNoteOffAt.remove(key);

    for (final voice in voices) {
      if (sostenutoVoices.contains(voice)) {
        // Voice is held by sostenuto pedal until pedal release
        continue;
      }
      if (isSustainPedalOn) {
        sustainedVoices.add(voice);
      } else {
        final releasingList = releasingVoices.putIfAbsent(key, () => []);
        releasingList.add(voice);
        final fade = releaseDuration ?? voice.releaseDuration;
        Timer(fade + const Duration(milliseconds: 50), () {
          releasingVoices[key]?.remove(voice);
        });
        await voice.release(customRelease: releaseDuration, atTime: atTime);
      }
    }
  }

  /// Updates the sustain pedal state (CC 64). When pedal is released, all deferred voices are faded out.
  Future<void> setSustainPedal(
    bool on, {
    Duration? releaseDuration,
    Duration? atTime,
  }) async {
    isSustainPedalOn = on;
    if (!on && sustainedVst3Notes.isNotEmpty) {
      final inst = effectiveVst3Instrument;
      for (final note in sustainedVst3Notes) {
        if (!heldNotes.contains(note)) {
          activeVst3Notes.remove(note);
          if (inst != null && !inst.isDisposed) {
            try {
              inst.noteOff(pitch: note, channel: channel);
            } catch (_) {}
          }
        }
      }
      sustainedVst3Notes.clear();
    }
    if (!on && sustainedVoices.isNotEmpty) {
      final toRelease = List<SoundFontVoice>.from(sustainedVoices);
      sustainedVoices.clear();
      for (final voice in toRelease) {
        if (!sostenutoVoices.contains(voice)) {
          await voice.release(customRelease: releaseDuration, atTime: atTime);
        }
      }
    }
  }

  /// Updates the sostenuto pedal state (CC 66).
  ///
  /// When depressed, locks in all currently sounding voices and keeps them sounding
  /// even through subsequent NoteOffs until the pedal is released.
  Future<void> setSostenutoPedal(
    bool on, {
    Duration? releaseDuration,
    Duration? atTime,
  }) async {
    isSostenutoPedalOn = on;
    if (on) {
      // Capture all currently active voices
      for (final vList in activeVoices.values) {
        sostenutoVoices.addAll(vList);
      }
    } else {
      // Release all captured voices that are no longer physically held
      final toRelease = sostenutoVoices
          .where((v) => !heldNotes.contains(v.key))
          .toList();
      sostenutoVoices.clear();
      for (final voice in toRelease) {
        if (isSustainPedalOn) {
          sustainedVoices.add(voice);
        } else {
          await voice.release(customRelease: releaseDuration, atTime: atTime);
        }
      }
    }
  }

  /// Updates the soft pedal (una corda) state (CC 67).
  void setSoftPedal(bool on, {Duration? atTime}) {
    isSoftPedalOn = on;
    _applyVolumeToAllVoices(atTime: atTime);
  }

  /// Dynamically updates pitch bend across all active, sustained, and sostenuto voices.
  void applyPitchBend(double normalizedBend) {
    pitchBend = normalizedBend;
    final mult = pitchBendMultiplier;
    for (final vList in activeVoices.values) {
      for (final voice in vList) {
        voice.applyPitchBend(mult);
      }
    }
    for (final voice in sustainedVoices) {
      voice.applyPitchBend(mult);
    }
    for (final voice in sostenutoVoices) {
      voice.applyPitchBend(mult);
    }
  }

  /// Dynamically updates volume across all active and sounding voices.
  void applyVolume(double vol, {Duration? atTime}) {
    volume = vol;
    _applyVolumeToAllVoices(atTime: atTime);
  }

  /// Dynamically updates expression across all active and sounding voices.
  void applyExpression(double expr, {Duration? atTime}) {
    expression = expr;
    _applyVolumeToAllVoices(atTime: atTime);
  }

  /// Dynamically updates stereo pan across all active and sounding voices.
  void applyPan(double p) {
    pan = p;
    if (vst3PlayHandle != null &&
        SoLoud.instance.isInitialized &&
        SoLoud.instance.getIsValidVoiceHandle(vst3PlayHandle!)) {
      try {
        SoLoud.instance.setPan(vst3PlayHandle!, pan.clamp(-1.0, 1.0));
      } catch (_) {}
    }
    for (final vList in activeVoices.values) {
      for (final voice in vList) {
        voice.applyPan(pan);
      }
    }
    for (final voice in sustainedVoices) {
      voice.applyPan(pan);
    }
    for (final voice in sostenutoVoices) {
      voice.applyPan(pan);
    }
  }

  /// Applies CC 1 (Modulation Wheel, `0.0..1.0`) scoped strictly to this channel's
  /// mixing [Bus] (and worker-isolate VibLFO if active), preventing global bleed!
  void applyModulation(double mod) {
    modulation = mod.clamp(0.0, 1.0);
    if (!SoLoud.instance.isInitialized) return;
    if (modulation > 0.01) {
      final b = ensureBus();
      try {
        final ampMod = b.filters.amplitudeModulatorFilter;
        if (!ampMod.isActive) ampMod.activate();
        ampMod.frequency().value = 5.5;
        ampMod.wet().value = (modulation * 0.65).clamp(0.0, 1.0);
      } catch (_) {}
    } else if (_bus != null && _bus!.isActive) {
      try {
        final ampMod = _bus!.filters.amplitudeModulatorFilter;
        if (ampMod.isActive) {
          ampMod.wet().value = 0.0;
          ampMod.deactivate();
        }
      } catch (_) {}
    }
  }

  /// Applies CC 91 (Reverb Send, `0.0..1.0`) to this channel's mixing [Bus] Freeverb filter.
  void applyReverbSend(double send) {
    reverbSend = send.clamp(0.0, 1.0);
    if (!SoLoud.instance.isInitialized) return;
    if (reverbSend > 0.01) {
      final b = ensureBus();
      try {
        final rev = b.filters.freeverbFilter;
        if (!rev.isActive) rev.activate();
        rev.wet().value = (reverbSend * 0.6).clamp(0.0, 1.0);
      } catch (_) {}
    } else if (_bus != null && _bus!.isActive) {
      try {
        final rev = _bus!.filters.freeverbFilter;
        if (rev.isActive) {
          rev.wet().value = 0.0;
          rev.deactivate();
        }
      } catch (_) {}
    }
  }

  /// Applies CC 93 (Chorus Send, `0.0..1.0`) to this channel's mixing [Bus] Flanger/Chorus filter.
  void applyChorusSend(double send) {
    chorusSend = send.clamp(0.0, 1.0);
    if (!SoLoud.instance.isInitialized) return;
    if (chorusSend > 0.01) {
      final b = ensureBus();
      try {
        final flanger = b.filters.flangerFilter;
        if (!flanger.isActive) flanger.activate();
        flanger.delay().value = 0.008;
        flanger.freq().value = 1.2;
        flanger.wet().value = (chorusSend * 0.5).clamp(0.0, 1.0);
      } catch (_) {}
    } else if (_bus != null && _bus!.isActive) {
      try {
        final flanger = _bus!.filters.flangerFilter;
        if (flanger.isActive) {
          flanger.wet().value = 0.0;
          flanger.deactivate();
        }
      } catch (_) {}
    }
  }

  void _applyVolumeToAllVoices({Duration? atTime}) {
    final eff = effectiveVolume;
    if (vst3PlayHandle != null &&
        SoLoud.instance.isInitialized &&
        SoLoud.instance.getIsValidVoiceHandle(vst3PlayHandle!)) {
      try {
        SoLoud.instance.setVolume(vst3PlayHandle!, eff.clamp(0.0, 1.0));
      } catch (_) {}
    }
    for (final vList in activeVoices.values) {
      for (final voice in vList) {
        voice.applyVolumeMultiplier(eff, atTime: atTime);
      }
    }
    for (final voice in sustainedVoices) {
      voice.applyVolumeMultiplier(eff, atTime: atTime);
    }
    for (final voice in sostenutoVoices) {
      voice.applyVolumeMultiplier(eff, atTime: atTime);
    }
  }

  /// Releases all active and sustained voices on this channel with release fade.
  Future<void> releaseAllVoices({
    Duration? releaseDuration,
    Duration? atTime,
  }) async {
    heldNotes.clear();
    final inst = effectiveVst3Instrument;
    if (inst != null) {
      for (final note in {...activeVst3Notes, ...sustainedVst3Notes}) {
        try {
          inst.noteOff(pitch: note, channel: channel);
        } catch (_) {}
      }
    }
    activeVst3Notes.clear();
    sustainedVst3Notes.clear();
    final all = <SoundFontVoice>[];
    for (final vList in activeVoices.values) {
      all.addAll(vList);
    }
    all.addAll(sustainedVoices);
    all.addAll(sostenutoVoices);
    for (final vList in releasingVoices.values) {
      all.addAll(vList);
    }
    activeVoices.clear();
    sustainedVoices.clear();
    sostenutoVoices.clear();
    releasingVoices.clear();

    for (final voice in all) {
      await voice.release(customRelease: releaseDuration, atTime: atTime);
    }
  }

  /// Immediately stops all sounding voices on this channel without fade (CC 120 All Sound Off).
  Future<void> stopAllVoicesImmediate() async {
    heldNotes.clear();
    final inst = effectiveVst3Instrument;
    if (inst != null) {
      for (final note in {...activeVst3Notes, ...sustainedVst3Notes}) {
        try {
          inst.noteOff(pitch: note, channel: channel);
        } catch (_) {}
      }
    }
    activeVst3Notes.clear();
    sustainedVst3Notes.clear();
    final all = <SoundFontVoice>[];
    for (final vList in activeVoices.values) {
      all.addAll(vList);
    }
    all.addAll(sustainedVoices);
    all.addAll(sostenutoVoices);
    for (final vList in releasingVoices.values) {
      all.addAll(vList);
    }
    activeVoices.clear();
    sustainedVoices.clear();
    sostenutoVoices.clear();
    releasingVoices.clear();

    for (final voice in all) {
      await voice.stop();
    }
  }

  /// Resets controllers to standard GM default values.
  void resetControllers() {
    volume = 100.0 / 127.0;
    expression = 1.0;
    pan = 0.0;
    pitchBend = 0.0;
    applyModulation(0.0);
    applyReverbSend(0.0);
    applyChorusSend(0.0);
    isSustainPedalOn = false;
    isSostenutoPedalOn = false;
    isSoftPedalOn = false;
    bankMsb = 0;
    bankLsb = 0;
    bank = (channel == 9 ? 128 : 0);
  }

  /// Disposes this channel's dedicated SoLoud mixing [Bus] if one was created.
  void disposeBus() {
    if (vst3PlayHandle != null &&
        SoLoud.instance.isInitialized &&
        SoLoud.instance.getIsValidVoiceHandle(vst3PlayHandle!)) {
      try {
        SoLoud.instance.stop(vst3PlayHandle!);
      } catch (_) {}
    }
    vst3PlayHandle = null;
    if (_bus != null) {
      try {
        _bus!.dispose();
      } catch (_) {}
      _bus = null;
    }
  }

  /// Returns the suggested or active instrument name for this channel.
  ///
  /// Checks in priority order:
  /// 1. Assigned [vst3InstrumentName] (when a VST3 Virtual Instrument is active)
  /// 2. Channel 10 (index 9): "Standard Drum Kit"
  /// 3. Active [presetOverride] name
  /// 4. Matched preset in [soundFont] (if provided)
  /// 5. Track or instrument name metadata from [midiFile] (if provided)
  /// 6. Universal General MIDI 1 instrument name for [program]
  String getSuggestedInstrumentName({
    SoundFontFile? soundFont,
    MidiFile? midiFile,
  }) {
    if (vst3Instrument != null && !vst3Instrument!.isDisposed) {
      return vst3InstrumentName ?? 'VST3 Synth';
    }
    if (presetOverride != null) {
      return presetOverride!.name;
    }
    if (sharedVst3Instrument != null && !sharedVst3Instrument!.isDisposed) {
      return '${sharedVst3InstrumentName ?? 'VST3'} (Ch ${channel + 1})';
    }

    final effectiveSf = customPlayer?.soundFont ?? soundFont;

    if (channel == 9) {
      if (effectiveSf != null) {
        final drumPreset = effectiveSf.findPreset(bank: 128, program: program);
        if (drumPreset != null) return drumPreset.name;
      }
      return 'Standard Drum Kit';
    }

    if (effectiveSf != null) {
      final p = effectiveSf.findPreset(bank: bank, program: program);
      if (p != null) return p.name;
    }

    return GeneralMidi.getProgramName(program);
  }

  /// Returns the General MIDI instrument family name (e.g. "Piano", "Strings", "Brass", "Synth Lead")
  /// or "Drums / Percussion" for Channel 10, or the SoundFont/VST3 name when a custom preset or VST3 synth is assigned.
  String getSuggestedFamilyName() {
    if (vst3Instrument != null && !vst3Instrument!.isDisposed) {
      return 'VST3 Instrument';
    }
    if (presetOverride != null) {
      final sfName = customPlayer?.soundFont.name;
      if (sfName != null && sfName.isNotEmpty) {
        return sfName;
      }
      return 'Custom Preset';
    }
    if (sharedVst3Instrument != null && !sharedVst3Instrument!.isDisposed) {
      return 'VST3 Multi-Timbral';
    }
    if (channel == 9) return 'Drums / Percussion';
    return GeneralMidi.getFamilyName(program);
  }
}
