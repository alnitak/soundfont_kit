import 'dart:async';
import '../models/preset.dart';
import '../player/soundfont_player.dart';
import 'midi_channel_state.dart';
import 'midi_models.dart';
import 'midi_timeline.dart';

/// Event type emitted during live MIDI playback.
enum MidiPlaybackEventType {
  noteOn,
  noteOff,
  programChange,
  controlChange,
  pitchBend,
  tempoChange,
  stateChange,
  seek,
}

/// Information packet emitted when an event occurs during MIDI playback.
class MidiPlaybackEvent {
  final MidiPlaybackEventType type;
  final int channel;
  final int note;
  final int velocity;
  final int? program;
  final int? controller;
  final int? value;
  final double? bpm;
  final Duration timestamp;

  const MidiPlaybackEvent({
    required this.type,
    this.channel = 0,
    this.note = 0,
    this.velocity = 0,
    this.program,
    this.controller,
    this.value,
    this.bpm,
    required this.timestamp,
  });

  @override
  String toString() =>
      'MidiPlaybackEvent($type, ch: $channel, note: $note, vel: $velocity, t: ${timestamp.inMilliseconds}ms)';
}

/// Comprehensive MIDI file sequencer and player backed by a [SoundFontPlayer].
class MidiPlayer {
  /// The underlying [SoundFontPlayer] responsible for audio synthesis.
  final SoundFontPlayer player;

  /// The active parsed MIDI timeline.
  MidiTimeline? _timeline;

  /// Active channel states for all 16 MIDI channels.
  final List<MidiChannelState> channels = List.generate(
    16,
    (i) => MidiChannelState(channel: i),
  );

  /// Global preset override. When set, all MIDI channels play through this preset.
  Preset? forcedPresetOverride;

  /// Playback speed multiplier (e.g. 0.5 for half-speed, 2.0 for double-speed).
  double speedMultiplier = 1.0;

  /// Whether playback automatically loops from the beginning upon reaching the end.
  bool looping = false;

  /// Lookahead window duration in milliseconds for sample-accurate scheduling.
  int lookaheadMs = 350;

  /// Scheduling timer interval in milliseconds.
  int scheduleIntervalMs = 40;

  bool _isPlaying = false;
  bool _isPaused = false;
  Duration _position = Duration.zero;
  int _nextEventIndex = 0;

  Timer? _scheduleTimer;
  DateTime? _playbackWallStart;
  Duration _playbackPosStart = Duration.zero;

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<MidiPlaybackEvent> _eventController =
      StreamController<MidiPlaybackEvent>.broadcast();

  MidiPlayer({required this.player});

  /// The currently loaded [MidiFile] (or null if none).
  MidiFile? get midiFile => _timeline?.file;

  /// The currently loaded [MidiTimeline].
  MidiTimeline? get timeline => _timeline;

  /// Total duration of the loaded MIDI file.
  Duration get duration => _timeline?.duration ?? Duration.zero;

  /// The set of 0-based MIDI channels (0-15) actively used by the loaded MIDI file.
  Set<int> get usedChannels => _timeline?.usedChannels ?? {};

  /// Current playback position.
  Duration get position => _position;

  /// Whether the player is actively playing.
  bool get isPlaying => _isPlaying;

  /// Whether playback is currently paused.
  bool get isPaused => _isPaused;

  /// Broadcast stream emitting the current playback position as playback advances.
  Stream<Duration> get positionStream => _positionController.stream;

  /// Broadcast stream emitting live playback events (NoteOn, NoteOff, etc.) for UI visualizers.
  Stream<MidiPlaybackEvent> get eventStream => _eventController.stream;

  /// Loads a [MidiFile] into the player and prepares the timeline.
  ///
  /// If [autoPreload] is true (default), automatically scans all presets used by the song
  /// and preloads their audio samples into memory cache to guarantee glitch-free playback.
  Future<void> load(
    MidiFile file, {
    bool autoPreload = true,
    void Function(double progress, int loaded, int total)? onPreloadProgress,
  }) async {
    await stop();

    final timeline = MidiTimeline.fromMidiFile(file);
    _timeline = timeline;
    _position = Duration.zero;
    _nextEventIndex = 0;

    // Reset channel states to timeline start snapshot
    _applySnapshotAt(Duration.zero);

    if (autoPreload) {
      await preloadSongPresets(onProgress: onPreloadProgress);
    }
  }

  /// Preloads all presets referenced by ProgramChange events in the loaded MIDI song.
  Future<void> preloadSongPresets({
    void Function(double progress, int loaded, int total)? onProgress,
  }) async {
    if (_timeline == null) return;

    final presetsToLoad = <Preset>{};

    if (forcedPresetOverride != null) {
      presetsToLoad.add(forcedPresetOverride!);
    } else {
      // Gather all bank/program combinations in the song
      final bankProgramPairs = <(int bank, int program)>{};

      // Default Channel 1-16 programs
      for (int ch = 0; ch < 16; ch++) {
        bankProgramPairs.add((ch == 9 ? 128 : 0, 0));
      }

      for (final timed in _timeline!.events) {
        if (timed.event is ProgramChangeEvent) {
          final pce = timed.event as ProgramChangeEvent;
          final bank = pce.channel == 9 ? 128 : 0;
          bankProgramPairs.add((bank, pce.program));
        }
      }

      for (final (bank, prog) in bankProgramPairs) {
        final preset = player.soundFont.findPreset(bank: bank, program: prog);
        if (preset != null) {
          presetsToLoad.add(preset);
        }
      }

      if (presetsToLoad.isEmpty && player.soundFont.presets.isNotEmpty) {
        presetsToLoad.add(player.soundFont.presets.first);
      }
    }

    final total = presetsToLoad.length;
    int loaded = 0;
    for (final preset in presetsToLoad) {
      await player.preloadPreset(preset);
      loaded++;
      onProgress?.call(
        (loaded / total).clamp(0.0, 1.0),
        loaded,
        total,
      );
    }
  }

  /// Preloads the active or assigned preset for [channel] on its respective SoundFont player.
  Future<void> preloadChannelPreset(int channel) async {
    if (channel < 0 || channel >= channels.length) return;
    final ch = channels[channel];
    final preset = _resolvePresetForChannel(ch);
    if (preset != null) {
      final targetPlayer = ch.customPlayer ?? player;
      await targetPlayer.preloadPreset(preset);
    }
  }

  /// Starts or resumes playback.
  Future<void> play() async {
    if (_timeline == null) return;
    if (_isPlaying) return;

    _isPlaying = true;
    _isPaused = false;
    _playbackWallStart = DateTime.now();
    _playbackPosStart = _position;

    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(
      Duration(milliseconds: scheduleIntervalMs),
      _onScheduleTick,
    );

    _eventController.add(
      MidiPlaybackEvent(
        type: MidiPlaybackEventType.stateChange,
        timestamp: _position,
      ),
    );
  }

  /// Pauses playback, holding the current position.
  Future<void> pause() async {
    if (!_isPlaying) return;

    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _isPlaying = false;
    _isPaused = true;

    // Release any sounding voices
    await _releaseAllChannelVoices();

    _eventController.add(
      MidiPlaybackEvent(
        type: MidiPlaybackEventType.stateChange,
        timestamp: _position,
      ),
    );
  }

  /// Stops playback and resets the position to the beginning.
  Future<void> stop() async {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _isPlaying = false;
    _isPaused = false;
    _position = Duration.zero;
    _nextEventIndex = 0;

    await _releaseAllChannelVoices();
    _applySnapshotAt(Duration.zero);
    _positionController.add(Duration.zero);

    _eventController.add(
      MidiPlaybackEvent(
        type: MidiPlaybackEventType.stateChange,
        timestamp: Duration.zero,
      ),
    );
  }

  /// Seeks to [target] duration.
  Future<void> seek(Duration target) async {
    if (_timeline == null) return;
    var clamped = target;
    if (clamped < Duration.zero) clamped = Duration.zero;
    if (clamped > _timeline!.duration) clamped = _timeline!.duration;

    // Immediately update positioning and event index synchronously to prevent
    // lookahead timer ticks from scheduling stale events during async voice release.
    _position = clamped;
    _playbackPosStart = clamped;
    _playbackWallStart = DateTime.now();
    _applySnapshotAt(clamped);

    await _releaseAllChannelVoices();

    if (_isPlaying) {
      _playbackPosStart = _position;
      _playbackWallStart = DateTime.now();
    }

    _positionController.add(_position);
    _eventController.add(
      MidiPlaybackEvent(
        type: MidiPlaybackEventType.seek,
        timestamp: clamped,
      ),
    );
  }

  /// Mutes or unmutes a specific MIDI [channel].
  void setChannelMute(int channel, bool muted) {
    if (channel >= 0 && channel < 16) {
      channels[channel].isMuted = muted;
      if (muted) {
        channels[channel].releaseAllVoices();
      }
    }
  }

  /// Sets Solo mode for a specific MIDI [channel].
  void setChannelSolo(int channel, bool solo) {
    if (channel >= 0 && channel < 16) {
      channels[channel].isSolo = solo;
      // If soloing, release voices on non-soloed channels
      if (solo) {
        for (int i = 0; i < 16; i++) {
          if (i != channel && !channels[i].isSolo) {
            channels[i].releaseAllVoices();
          }
        }
      }
    }
  }

  /// Sets the volume multiplier (0.0 to 1.0) for [channel].
  void setChannelVolume(int channel, double volume) {
    if (channel >= 0 && channel < 16) {
      channels[channel].volume = volume.clamp(0.0, 1.0);
    }
  }

  /// Sets the stereo pan position (-1.0 to 1.0) for [channel].
  void setChannelPan(int channel, double pan) {
    if (channel >= 0 && channel < 16) {
      channels[channel].pan = pan.clamp(-1.0, 1.0);
    }
  }

  /// Returns the suggested or active instrument name for [channel].
  String getSuggestedInstrumentName(int channel) {
    if (channel < 0 || channel >= 16) return 'Unknown';
    if (forcedPresetOverride != null) return forcedPresetOverride!.name;
    final ch = channels[channel];
    return ch.getSuggestedInstrumentName(
      soundFont: ch.customPlayer?.soundFont ?? player.soundFont,
      midiFile: midiFile,
    );
  }

  /// Returns the instrument family name or custom SoundFont name for [channel].
  String getSuggestedFamilyName(int channel) {
    if (channel < 0 || channel >= 16) return 'Unknown';
    return channels[channel].getSuggestedFamilyName();
  }

  // ---------------------------------------------------------------------------
  // Internal Scheduler
  // ---------------------------------------------------------------------------

  void _onScheduleTick(Timer timer) {
    if (!_isPlaying || _timeline == null || _playbackWallStart == null) return;

    final elapsedWall = DateTime.now().difference(_playbackWallStart!);
    final virtualElapsed = Duration(
      microseconds: (elapsedWall.inMicroseconds * speedMultiplier).round(),
    );
    _position = _playbackPosStart + virtualElapsed;

    _positionController.add(_position);

    if (_position >= _timeline!.duration) {
      if (looping) {
        seek(Duration.zero);
        return;
      } else {
        stop();
        return;
      }
    }

    final lookaheadDuration = Duration(
      microseconds: (lookaheadMs * 1000 * speedMultiplier).round(),
    );
    final windowEnd = _position + lookaheadDuration;

    final events = _timeline!.events;
    final anySolo = channels.any((c) => c.isSolo);

    while (_nextEventIndex < events.length) {
      final timed = events[_nextEventIndex];
      if (timed.timestamp > windowEnd) {
        break;
      }

      _nextEventIndex++;
      _processTimedEvent(timed, anySolo);
    }
  }

  void _processTimedEvent(TimedMidiEvent timed, bool anySolo) {
    final event = timed.event;

    // Calculate delay from current virtual time
    final deltaUs = timed.timestamp.inMicroseconds - _position.inMicroseconds;
    final delay = deltaUs > 0
        ? Duration(microseconds: (deltaUs / speedMultiplier).round())
        : Duration.zero;

    if (event is NoteOnEvent) {
      final ch = channels[event.channel];
      if (event.isNoteOff) {
        ch.handleNoteOff(event.note);
        _eventController.add(
          MidiPlaybackEvent(
            type: MidiPlaybackEventType.noteOff,
            channel: event.channel,
            note: event.note,
            velocity: 0,
            timestamp: timed.timestamp,
          ),
        );
      } else {
        final shouldPlay = !ch.isMuted && (!anySolo || ch.isSolo);
        if (shouldPlay) {
          final targetPlayer = ch.customPlayer ?? player;
          final preset = _resolvePresetForChannel(ch);
          if (preset != null) {
            final vol = (ch.effectiveVolume * (event.velocity / 127.0)).clamp(0.0, 1.0);
            targetPlayer
                .playPresetScheduled(
                  preset,
                  atTime: delay,
                  key: event.note,
                  velocity: event.velocity,
                  customVolume: vol,
                  customPan: ch.pan,
                )
                .then((voice) {
                  ch.addVoice(event.note, voice);
                });
          }
        }

        _eventController.add(
          MidiPlaybackEvent(
            type: MidiPlaybackEventType.noteOn,
            channel: event.channel,
            note: event.note,
            velocity: event.velocity,
            timestamp: timed.timestamp,
          ),
        );
      }
    } else if (event is NoteOffEvent) {
      final ch = channels[event.channel];
      ch.handleNoteOff(event.note);
      _eventController.add(
        MidiPlaybackEvent(
          type: MidiPlaybackEventType.noteOff,
          channel: event.channel,
          note: event.note,
          velocity: event.velocity,
          timestamp: timed.timestamp,
        ),
      );
    } else if (event is ProgramChangeEvent) {
      channels[event.channel].program = event.program;
      _eventController.add(
        MidiPlaybackEvent(
          type: MidiPlaybackEventType.programChange,
          channel: event.channel,
          program: event.program,
          timestamp: timed.timestamp,
        ),
      );
    } else if (event is ControlChangeEvent) {
      final ch = channels[event.channel];
      if (event.isSustainPedal) {
        ch.setSustainPedal(event.isSustainOn);
      } else if (event.controller == 7) {
        ch.volume = event.value / 127.0;
      } else if (event.controller == 10) {
        ch.pan = (event.value - 64) / 64.0;
      } else if (event.controller == 11) {
        ch.expression = event.value / 127.0;
      } else if (event.isAllNotesOff) {
        ch.releaseAllVoices();
      }

      _eventController.add(
        MidiPlaybackEvent(
          type: MidiPlaybackEventType.controlChange,
          channel: event.channel,
          controller: event.controller,
          value: event.value,
          timestamp: timed.timestamp,
        ),
      );
    } else if (event is PitchBendEvent) {
      channels[event.channel].pitchBend = event.normalized;
      _eventController.add(
        MidiPlaybackEvent(
          type: MidiPlaybackEventType.pitchBend,
          channel: event.channel,
          value: event.value,
          timestamp: timed.timestamp,
        ),
      );
    } else if (event is SetTempoEvent) {
      _eventController.add(
        MidiPlaybackEvent(
          type: MidiPlaybackEventType.tempoChange,
          bpm: event.bpm,
          timestamp: timed.timestamp,
        ),
      );
    }
  }

  /// Sets or clears a custom [SoundFontPlayer] and [Preset] for a specific MIDI channel (0-15).
  void setChannelSoundFont(
    int channel, {
    SoundFontPlayer? customPlayer,
    Preset? preset,
  }) {
    if (channel < 0 || channel >= channels.length) return;
    channels[channel].customPlayer = customPlayer;
    channels[channel].presetOverride = preset;
  }

  /// Clears any custom SoundFont or preset overrides for a specific MIDI channel (0-15).
  void clearChannelOverride(int channel) {
    if (channel < 0 || channel >= channels.length) return;
    channels[channel].customPlayer = null;
    channels[channel].presetOverride = null;
  }

  Preset? _resolvePresetForChannel(MidiChannelState ch) {
    if (forcedPresetOverride != null) {
      return forcedPresetOverride;
    }
    if (ch.presetOverride != null) {
      return ch.presetOverride;
    }
    final targetPlayer = ch.customPlayer ?? player;
    final preset = targetPlayer.soundFont.findPreset(
      bank: ch.bank,
      program: ch.program,
    );
    if (preset != null) return preset;

    // Fallback: search Bank 0 if requested bank was not found
    if (ch.bank != 0) {
      final fallbackBank0 = targetPlayer.soundFont.findPreset(
        bank: 0,
        program: ch.program,
      );
      if (fallbackBank0 != null) return fallbackBank0;
    }

    // Default fallback: first preset in soundfont
    return targetPlayer.soundFont.presets.isNotEmpty
        ? targetPlayer.soundFont.presets.first
        : null;
  }

  void _applySnapshotAt(Duration timestamp) {
    if (_timeline == null) return;
    final (snapshots, nextIndex) = _timeline!.getSnapshotAt(timestamp);
    _nextEventIndex = nextIndex;

    for (final entry in snapshots.entries) {
      final ch = channels[entry.key];
      final snap = entry.value;
      ch.bank = snap.bank;
      ch.program = snap.program;
      ch.volume = snap.volume / 127.0;
      ch.expression = snap.expression / 127.0;
      ch.pan = (snap.pan - 64) / 64.0;
      ch.isSustainPedalOn = snap.isSustainPedalOn;
    }
  }

  Future<void> _releaseAllChannelVoices() async {
    for (final ch in channels) {
      await ch.releaseAllVoices(releaseDuration: Duration.zero);
    }
    await player.allNotesOff(releaseDuration: Duration.zero);
    for (final ch in channels) {
      if (ch.customPlayer != null) {
        await ch.customPlayer!.allNotesOff(releaseDuration: Duration.zero);
      }
    }
  }

  /// Disposes of the player, stopping active playback and closing streams.
  Future<void> dispose() async {
    await stop();
    _positionController.close();
    _eventController.close();
  }
}
