import 'dart:math' as math;
import '../models/preset.dart';
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

  /// Currently sounding voices keyed by MIDI note.
  final Map<int, List<SoundFontVoice>> activeVoices = {};

  /// Voices whose NoteOff was received while sustain pedal was held down.
  final List<SoundFontVoice> sustainedVoices = [];

  /// Voices captured when sostenuto pedal was depressed.
  final Set<SoundFontVoice> sostenutoVoices = {};

  /// Set of MIDI keys currently held down on this channel.
  final Set<int> heldNotes = {};

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
    this.isSustainPedalOn = false,
    this.isSostenutoPedalOn = false,
    this.isSoftPedalOn = false,
    this.transpose = 0,
    this.isMuted = false,
    this.isSolo = false,
    this.customPlayer,
    this.presetOverride,
  }) : bank = bank ?? (channel == 9 ? 128 : 0);

  /// Current relative pitch bend playback speed multiplier ($2^{\frac{\text{semitones} \times \text{bend}}{12}}$).
  double get pitchBendMultiplier {
    if (pitchBend == 0.0) return 1.0;
    return math.pow(2.0, (pitchBend * pitchBendRangeSemitones) / 12.0).toDouble();
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
  }

  /// Registers a newly triggered voice for [key], applying current channel controllers.
  void addVoice(int key, SoundFontVoice voice) {
    if (pitchBend != 0.0) {
      voice.applyPitchBend(pitchBendMultiplier);
    }
    if (effectiveVolume != 1.0) {
      voice.applyVolumeMultiplier(effectiveVolume);
    }
    if (pan != 0.0) {
      voice.applyPan(pan);
    }

    if (!heldNotes.contains(key)) {
      if (isSustainPedalOn) {
        sustainedVoices.add(voice);
      } else {
        voice.release(customRelease: Duration.zero);
      }
      return;
    }
    activeVoices.putIfAbsent(key, () => []).add(voice);
  }

  /// Handles Note-Off for [key]. If sustain or sostenuto pedal is pressed, the voice is marked for delayed release.
  Future<void> handleNoteOff(int key, {Duration? releaseDuration}) async {
    heldNotes.remove(key);
    final voices = activeVoices.remove(key);
    if (voices == null || voices.isEmpty) return;

    for (final voice in voices) {
      if (sostenutoVoices.contains(voice)) {
        // Voice is held by sostenuto pedal until pedal release
        continue;
      }
      if (isSustainPedalOn) {
        sustainedVoices.add(voice);
      } else {
        await voice.release(customRelease: releaseDuration);
      }
    }
  }

  /// Updates the sustain pedal state (CC 64). When pedal is released, all deferred voices are faded out.
  Future<void> setSustainPedal(bool on, {Duration? releaseDuration}) async {
    isSustainPedalOn = on;
    if (!on && sustainedVoices.isNotEmpty) {
      final toRelease = List<SoundFontVoice>.from(sustainedVoices);
      sustainedVoices.clear();
      for (final voice in toRelease) {
        if (!sostenutoVoices.contains(voice)) {
          await voice.release(customRelease: releaseDuration);
        }
      }
    }
  }

  /// Updates the sostenuto pedal state (CC 66).
  ///
  /// When depressed, locks in all currently sounding voices and keeps them sounding
  /// even through subsequent NoteOffs until the pedal is released.
  Future<void> setSostenutoPedal(bool on, {Duration? releaseDuration}) async {
    isSostenutoPedalOn = on;
    if (on) {
      // Capture all currently active voices
      for (final vList in activeVoices.values) {
        sostenutoVoices.addAll(vList);
      }
    } else {
      // Release all captured voices that are no longer physically held
      final toRelease = sostenutoVoices.where((v) => !heldNotes.contains(v.key)).toList();
      sostenutoVoices.clear();
      for (final voice in toRelease) {
        if (isSustainPedalOn) {
          sustainedVoices.add(voice);
        } else {
          await voice.release(customRelease: releaseDuration);
        }
      }
    }
  }

  /// Updates the soft pedal (una corda) state (CC 67).
  void setSoftPedal(bool on) {
    isSoftPedalOn = on;
    _applyVolumeToAllVoices();
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
  void applyVolume(double vol) {
    volume = vol;
    _applyVolumeToAllVoices();
  }

  /// Dynamically updates expression across all active and sounding voices.
  void applyExpression(double expr) {
    expression = expr;
    _applyVolumeToAllVoices();
  }

  /// Dynamically updates stereo pan across all active and sounding voices.
  void applyPan(double p) {
    pan = p;
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

  void _applyVolumeToAllVoices() {
    final eff = effectiveVolume;
    for (final vList in activeVoices.values) {
      for (final voice in vList) {
        voice.applyVolumeMultiplier(eff);
      }
    }
    for (final voice in sustainedVoices) {
      voice.applyVolumeMultiplier(eff);
    }
    for (final voice in sostenutoVoices) {
      voice.applyVolumeMultiplier(eff);
    }
  }

  /// Releases all active and sustained voices on this channel with release fade.
  Future<void> releaseAllVoices({Duration? releaseDuration}) async {
    heldNotes.clear();
    final all = <SoundFontVoice>[];
    for (final vList in activeVoices.values) {
      all.addAll(vList);
    }
    all.addAll(sustainedVoices);
    all.addAll(sostenutoVoices);
    activeVoices.clear();
    sustainedVoices.clear();
    sostenutoVoices.clear();

    for (final voice in all) {
      await voice.release(customRelease: releaseDuration);
    }
  }

  /// Immediately stops all sounding voices on this channel without fade (CC 120 All Sound Off).
  Future<void> stopAllVoicesImmediate() async {
    heldNotes.clear();
    final all = <SoundFontVoice>[];
    for (final vList in activeVoices.values) {
      all.addAll(vList);
    }
    all.addAll(sustainedVoices);
    all.addAll(sostenutoVoices);
    activeVoices.clear();
    sustainedVoices.clear();
    sostenutoVoices.clear();

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
    modulation = 0.0;
    isSustainPedalOn = false;
    isSostenutoPedalOn = false;
    isSoftPedalOn = false;
    bankMsb = 0;
    bankLsb = 0;
    bank = (channel == 9 ? 128 : 0);
  }

  /// Returns the suggested or active instrument name for this channel.
  ///
  /// Checks in priority order:
  /// 1. Channel 10 (index 9): "Standard Drum Kit"
  /// 2. Active [presetOverride] name
  /// 3. Matched preset in [soundFont] (if provided)
  /// 4. Track or instrument name metadata from [midiFile] (if provided)
  /// 5. Universal General MIDI 1 instrument name for [program]
  String getSuggestedInstrumentName({
    SoundFontFile? soundFont,
    MidiFile? midiFile,
  }) {
    if (presetOverride != null) {
      return presetOverride!.name;
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
  /// or "Drums / Percussion" for Channel 10, or the SoundFont name when a custom preset is assigned.
  String getSuggestedFamilyName() {
    if (presetOverride != null) {
      final sfName = customPlayer?.soundFont.name;
      if (sfName != null && sfName.isNotEmpty) {
        return sfName;
      }
      return 'Custom Preset';
    }
    if (channel == 9) return 'Drums / Percussion';
    return GeneralMidi.getFamilyName(program);
  }
}
