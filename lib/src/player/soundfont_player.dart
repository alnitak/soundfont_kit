import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import '../models/instrument.dart';
import '../models/preset.dart';
import '../models/sample_info.dart';
import '../models/soundfont_format.dart';
import '../models/zone.dart';
import '../soundfont_file.dart';
import 'filters/soundfont_filter.dart';
import 'player_options.dart';
import 'realtime_synthesizer.dart';
import 'sample_streamer.dart';
import 'stereo_joiner.dart';
import 'soundfont_voice.dart';
import 'voice_calculator.dart';

/// Comprehensive audio player for [SoundFontFile] instruments, presets, and samples
/// powered by `flutter_soloud`.
class SoundFontPlayer {
  /// The backing SoundFont file.
  final SoundFontFile soundFont;

  /// Player configuration options.
  SoundFontPlayerOptions options;

  /// Active voices keyed by MIDI key for polyphonic voice lifecycle management.
  final Map<int, List<SoundFontVoice>> _activeVoices = {};

  /// Voices currently fading out during release, keyed by MIDI key.
  final Map<int, List<SoundFontVoice>> _releasingVoices = {};

  /// In-memory cache for raw or interleaved sample bytes.
  final Map<int, Uint8List> _sampleBytesCache = {};

  /// In-memory cache for joined stereo PCM bytes keyed by "leftId_rightId".
  final Map<String, Uint8List> _stereoBytesCache = {};

  /// In-memory cache for preserved [AudioSource] instances.
  final Map<String, AudioSource> _audioSourceCache = {};

  /// Active in-flight futures for loading audio sources to deduplicate concurrent requests.
  final Map<String, Future<AudioSource?>> _loadingAudioSources = {};

  /// Set of currently held/active MIDI keys to avoid orphaned voices when noteOff fires during async creation.
  final Set<int> _heldKeys = {};

  static int _instanceCounter = 0;
  final int _playerId = ++_instanceCounter;

  Bus? _mixingBus;
  bool _ownsMixingBus = false;
  RealtimeSoundFontSynthesizer? _realtimeSynth;

  /// Optional dedicated SoLoud mixing [Bus] for this player.
  Bus? get mixingBus => _mixingBus;

  /// Filter rack scoped to this player's [mixingBus] (or global if no bus is attached).
  SoundFontFilterRack get busFilters => _mixingBus != null
      ? SoundFontFilterRack.forBus(_mixingBus!)
      : const SoundFontFilterRack.global();

  /// Effective bus ID used when playing voices (`mixingBus?.busId ?? options.defaultBusId`).
  int get effectiveBusId => _mixingBus?.busId ?? options.defaultBusId;

  /// Attaches an existing [bus] or creates a dedicated SoLoud mixing [Bus]
  /// for this player so per-player filters, VST3 effects, and volume/pan apply
  /// independently.
  Bus enableMixingBus({Bus? bus, String? name}) {
    if (bus != null) {
      _mixingBus = bus;
      _ownsMixingBus = false;
      if (!bus.isActive && SoLoud.instance.isInitialized) {
        bus.playOnEngine();
      }
      return bus;
    }
    if (_mixingBus != null) return _mixingBus!;
    final created = SoLoud.instance.createMixingBus(
      name: name ?? 'SoundFontPlayer $_playerId',
    );
    if (SoLoud.instance.isInitialized) {
      created.playOnEngine();
    }
    _mixingBus = created;
    _ownsMixingBus = true;
    return created;
  }

  /// Lazily initializes and returns the worker-isolate [RealtimeSoundFontSynthesizer].
  Future<RealtimeSoundFontSynthesizer> ensureRealtimeSynthesizer() async {
    final synth = _realtimeSynth ??= RealtimeSoundFontSynthesizer(
      sampleRate: 44100,
      busId: effectiveBusId,
    );
    await synth.ensureStarted();
    return synth;
  }

  String _sampleCacheKey(int sampleId) => 'sf_${_playerId}_s_$sampleId';
  String _stereoCacheKey(int leftId, int rightId) =>
      'sf_${_playerId}_st_${leftId}_$rightId';

  /// Creates a [SoundFontPlayer] for [soundFont] with optional [options].
  SoundFontPlayer({
    required this.soundFont,
    this.options = const SoundFontPlayerOptions(),
  }) : _sustainTime = options.sustainTime,
       _sustain = options.sustain;

  double? _sustainTime;
  double _sustain = 1.0;

  /// Global master sustain factor (e.g. 0.0 to 10.0, default 1.0).
  ///
  /// Works across all SoundFonts:
  /// - Scales authentic release envelopes for instruments with native release.
  /// - Scales fallback decay ([sustainTime] or default duration) for instruments without.
  /// - `0.0`: Staccato cutoff upon note release.
  /// - `1.0`: Natural authentic release.
  /// - `> 1.0`: Extended sustain (damper pedal simulation).
  double get sustain => _sustain;
  set sustain(double value) {
    _sustain = value.clamp(0.0, 20.0);
  }

  /// Global fallback sustain duration in seconds (e.g. 0.05 to 5.0).
  /// Used when notes or zones have no native release envelope.
  /// This base duration is multiplied by [sustain].
  double? get sustainTime => _sustainTime;
  set sustainTime(double? value) {
    _sustainTime = value?.clamp(0.01, 10.0);
  }

  /// Deprecated alias for [sustain].
  double get sustainMultiplier => _sustain;
  set sustainMultiplier(double value) {
    sustain = value;
  }

  Future<AudioSource?> _getOrLoadSampleAudioSource(
    SampleInfo sample, {
    bool createAudioSource = true,
  }) async {
    final cacheKey = _sampleCacheKey(sample.id);

    if (options.cacheAudioSources && _audioSourceCache.containsKey(cacheKey)) {
      return _audioSourceCache[cacheKey];
    }

    if (_loadingAudioSources.containsKey(cacheKey)) {
      return _loadingAudioSources[cacheKey]!;
    }

    final future = () async {
      Uint8List? preloaded = _sampleBytesCache[sample.id];
      if (preloaded == null) {
        final bytes = await soundFont.getSampleBytes(sample);
        if (bytes.isNotEmpty) {
          _sampleBytesCache[sample.id] = bytes;
          preloaded = bytes;
        }
      }

      AudioSource? audio;
      if (createAudioSource && preloaded != null && preloaded.isNotEmpty) {
        audio = await SampleStreamer.loadAudioSourceFromBytes(
          bytes: preloaded,
          compression: sample.compression,
          sampleRate: sample.sampleRate,
          channels: sample.channels,
          sourceKey: cacheKey,
        );
      }

      if (audio == null && !createAudioSource) {
        return null;
      }

      audio ??= SampleStreamer.streamSample(
        soundFont: soundFont,
        sample: sample,
        preloadedBytes: preloaded,
        chunkSize: options.streamChunkSize,
        bufferingType: BufferingType.preserved,
        autoDispose: false,
      );

      if (options.cacheAudioSources) {
        _audioSourceCache[cacheKey] = audio;
      }
      return audio;
    }();

    _loadingAudioSources[cacheKey] = future;
    try {
      return await future;
    } finally {
      _loadingAudioSources.remove(cacheKey);
    }
  }

  Future<AudioSource?> _getOrLoadStereoAudioSource(
    SampleInfo leftSample,
    SampleInfo rightSample, {
    bool createAudioSource = true,
  }) async {
    final cacheKey = _stereoCacheKey(leftSample.id, rightSample.id);

    if (options.cacheAudioSources && _audioSourceCache.containsKey(cacheKey)) {
      return _audioSourceCache[cacheKey];
    }

    if (_loadingAudioSources.containsKey(cacheKey)) {
      return _loadingAudioSources[cacheKey]!;
    }

    final future = () async {
      Uint8List? leftBytes = _sampleBytesCache[leftSample.id];
      if (leftBytes == null) {
        final bytes = await soundFont.getSampleBytes(leftSample);
        if (bytes.isNotEmpty) {
          _sampleBytesCache[leftSample.id] = bytes;
          leftBytes = bytes;
        }
      }

      Uint8List? rightBytes = _sampleBytesCache[rightSample.id];
      if (rightBytes == null) {
        final bytes = await soundFont.getSampleBytes(rightSample);
        if (bytes.isNotEmpty) {
          _sampleBytesCache[rightSample.id] = bytes;
          rightBytes = bytes;
        }
      }

      AudioSource? audio;
      if (createAudioSource &&
          leftBytes != null &&
          leftBytes.isNotEmpty &&
          rightBytes != null &&
          rightBytes.isNotEmpty) {
        audio = await SampleStreamer.joinTwoAudioSources(
          leftBytes: leftBytes,
          rightBytes: rightBytes,
          leftSample: leftSample,
          rightSample: rightSample,
          sourceKey: cacheKey,
        );
      }

      if (options.cacheAudioSources && audio != null) {
        _audioSourceCache[cacheKey] = audio;
      }
      return audio;
    }();

    _loadingAudioSources[cacheKey] = future;
    try {
      return await future;
    } finally {
      _loadingAudioSources.remove(cacheKey);
    }
  }

  /// Plays a single [SampleInfo] with optional pitch, volume, pan, loop,
  /// and sample-accurate engine scheduling overrides.
  Future<SoundFontVoice> playSample(
    SampleInfo sample, {
    int? key,
    int velocity = 100,
    double? volume,
    double? baseVolume,
    double? pan,
    double? pitchRatio,
    bool? looping,
    int? loopingStartOffsetAt,
    int? loopingEndOffsetAt,
    Duration? atTime,
    Duration? duration,
    Zone? zone,
    Zone? presetZone,
    bool trackVoice = true,
    int? busId,
  }) async {
    final effectiveKey =
        key ?? (sample.originalPitch > 0 ? sample.originalPitch : 60);
    if (!SoLoud.instance.isInitialized) {
      return SoundFontVoice(key: effectiveKey, velocity: velocity, handles: []);
    }
    if (trackVoice) {
      _heldKeys.add(effectiveKey);
    }

    // Exclusive Class / Choke Group handling (SF2 Gen 57 / SFZ group & off_by)
    final exc = VoiceCalculator.resolveExclusiveClass(
      zone: zone,
      presetZone: presetZone,
    );
    if (exc.offByGroup != null) {
      await _chokeExclusiveClassVoices(exc.offByGroup!, atTime: atTime);
    }

    final speed =
        pitchRatio ??
        VoiceCalculator.calculatePitchRatio(
          key: effectiveKey,
          sample: sample,
          zone: zone,
          presetZone: presetZone,
        );

    final vol =
        volume ??
        VoiceCalculator.calculateVolume(
          velocity: velocity,
          zone: zone,
          presetZone: presetZone,
          masterVolume: options.masterVolume,
        );

    final p =
        pan ??
        VoiceCalculator.calculatePan(
          zone: zone,
          presetZone: presetZone,
          sample: sample,
        );

    final loopInfo = VoiceCalculator.calculateLoopRegion(
      sample: sample,
      zone: zone,
    );

    final shouldLoop = looping ?? loopInfo.isLooping;
    final startOffset = loopingStartOffsetAt ?? loopInfo.startFrames;
    final endOffset = loopingEndOffsetAt ?? loopInfo.endFrames;

    final releaseDuration = VoiceCalculator.calculateReleaseDuration(
      zone: zone,
      presetZone: presetZone,
      defaultDuration: options.defaultReleaseDuration,
      sustainTime: _sustainTime,
      sustain: _sustain,
    );

    final validLoop =
        shouldLoop &&
        startOffset >= 0 &&
        endOffset != null &&
        endOffset > startOffset;

    // Mode B: Worker-Isolate Real-Time Synthesizer (16-bit PCM samples)
    if (options.synthMode == SoundFontSynthMode.realtimeIsolateSynth &&
        sample.compression == SampleCompression.pcm16) {
      final synth = await ensureRealtimeSynthesizer();
      Uint8List? preloaded = _sampleBytesCache[sample.id];
      if (preloaded == null) {
        final bytes = await soundFont.getSampleBytes(sample);
        if (bytes.isNotEmpty) {
          _sampleBytesCache[sample.id] = bytes;
          preloaded = bytes;
        }
      }
      if (preloaded != null && preloaded.isNotEmpty) {
        synth.registerSamplePcm(sample.id, preloaded);
        final vId = synth.triggerVoice(
          key: effectiveKey,
          velocity: velocity,
          leftSample: sample,
          zone: zone,
          presetZone: presetZone,
          basePitchRatio: speed,
          peakVolume: vol,
          pan: p,
          isLooping: validLoop,
          loopStart: validLoop ? startOffset : 0,
          loopEnd: validLoop ? endOffset : 0,
          releaseDuration: releaseDuration,
        );
        final voice = SoundFontVoice(
          key: effectiveKey,
          velocity: velocity,
          handles: const [],
          releaseDuration: releaseDuration,
          sampleId: sample.id,
          baseSpeeds: [speed],
          baseVolumes: [baseVolume ?? vol],
          basePans: [p],
          exclusiveClasses: exc.exclusiveClass != null
              ? {exc.exclusiveClass!}
              : const {},
          realtimeVoiceIds: [vId],
          realtimeSynth: synth,
        );
        if (duration != null) {
          voice.addEnvelopeTimer(
            Timer(duration, () => voice.release()),
          );
        }
        if (trackVoice) {
          _trackVoice(effectiveKey, voice);
        }
        return voice;
      }
    }

    final audio = await _getOrLoadSampleAudioSource(sample);
    if (audio == null) {
      return SoundFontVoice(key: effectiveKey, velocity: velocity, handles: []);
    }

    final volStages = VoiceCalculator.calculateVolEnvStages(
      zone: zone,
      presetZone: presetZone,
      peakVolume: vol,
    );
    final scheduledAt = (atTime ?? Duration.zero) + volStages.delay;
    final hasAttack = volStages.attack > const Duration(milliseconds: 5);
    final initialVol = hasAttack ? 0.01 : vol;
    final targetBusId = busId ?? effectiveBusId;

    _activatePerVoiceFilterOnSourceIfNeeded(audio, zone: zone, presetZone: presetZone);

    final handle = SoLoud.instance.playScheduled(
      audio,
      scheduledAt,
      duration: duration,
      volume: initialVol,
      pan: p,
      scale: speed,
      looping: validLoop,
      loopingStartOffsetAt: validLoop ? startOffset : null,
      loopingEndOffsetAt: validLoop ? endOffset : null,
      busId: targetBusId,
    );

    _applyPerVoiceFilterIfNeeded(audio, handle, zone: zone, presetZone: presetZone);

    final voice = SoundFontVoice(
      key: effectiveKey,
      velocity: velocity,
      handles: [handle],
      sources: [audio],
      releaseDuration: releaseDuration,
      sampleId: sample.id,
      baseSpeeds: [speed],
      baseVolumes: [baseVolume ?? vol],
      basePans: [p],
      exclusiveClasses: exc.exclusiveClass != null
          ? {exc.exclusiveClass!}
          : const {},
    );

    _scheduleDahdsrStages(
      voice: voice,
      handle: handle,
      peakVolume: vol,
      volStages: volStages,
      atTime: atTime,
      scheduledStart: scheduledAt,
      duration: duration,
      releaseDuration: releaseDuration,
    );

    if (trackVoice) {
      _trackVoice(effectiveKey, voice);
    }
    return voice;
  }

  /// Plays an [Instrument] for a given MIDI [key] and [velocity], with optional
  /// sample-accurate engine clock scheduling.
  Future<SoundFontVoice> playInstrument(
    Instrument instrument, {
    int key = 60,
    int velocity = 100,
    double? customVolume,
    double? baseVolume,
    double? customPan,
    Duration? atTime,
    Duration? duration,
    Zone? presetZone,
    bool trackVoice = true,
    Set<int>? handledSampleIds,
    int? busId,
  }) async {
    if (trackVoice) {
      _heldKeys.add(key);
    }

    // Find matching zones for this key and velocity
    var matchingZones = instrument.zones
        .where(
          (z) =>
              z.matches(key, velocity) &&
              (z.sampleRef != null || z.sampleID != null),
        )
        .toList();

    // Fallback if no specific zone matches: pick first zone with a sample
    if (matchingZones.isEmpty) {
      matchingZones = instrument.zones
          .where((z) => z.sampleRef != null || z.sampleID != null)
          .take(1)
          .toList();
    }

    if (matchingZones.isEmpty) {
      return SoundFontVoice(key: key, velocity: velocity, handles: []);
    }

    final allHandles = <SoundHandle>[];
    final allSources = <AudioSource>[];
    final allBaseSpeeds = <double>[];
    final allBaseVolumes = <double>[];
    final allBasePans = <double>[];
    final allExclusiveClasses = <int>{};
    final allRealtimeVoiceIds = <int>[];
    RealtimeSoundFontSynthesizer? activeRealtimeSynth;
    Duration maxRelease = options.defaultReleaseDuration;

    // Check for stereo sample pairs among matching zones
    final effectiveHandledSampleIds = handledSampleIds ?? <int>{};

    for (int i = 0; i < matchingZones.length; i++) {
      final zone = matchingZones[i];
      final sample =
          zone.sampleRef ??
          (zone.sampleID != null && zone.sampleID! < soundFont.samples.length
              ? soundFont.samples[zone.sampleID!]
              : null);

      if (sample == null || effectiveHandledSampleIds.contains(sample.id)) {
        continue;
      }

      // Check if stereo joining applies
      if (options.joinStereoChannels &&
          StereoJoiner.isStereoCandidate(sample)) {
        final pairedSample = StereoJoiner.findLinkedSample(soundFont, sample);
        if (pairedSample != null) {
          effectiveHandledSampleIds.add(sample.id);
          effectiveHandledSampleIds.add(pairedSample.id);

          final leftSample = sample.isLeft ? sample : pairedSample;
          final rightSample = sample.isRight ? sample : pairedSample;

          final stereoVoice = await _playJoinedStereoPair(
            leftSample: leftSample,
            rightSample: rightSample,
            key: key,
            velocity: velocity,
            zone: zone,
            presetZone: presetZone,
            customVolume: customVolume,
            baseVolume: baseVolume,
            customPan: customPan,
            atTime: atTime,
            duration: duration,
            busId: busId,
          );

          allHandles.addAll(stereoVoice.handles);
          allSources.addAll(stereoVoice.sources);
          allBaseSpeeds.addAll(stereoVoice.baseSpeeds);
          allBaseVolumes.addAll(stereoVoice.baseVolumes);
          allBasePans.addAll(stereoVoice.basePans);
          allExclusiveClasses.addAll(stereoVoice.exclusiveClasses);
          allRealtimeVoiceIds.addAll(stereoVoice.realtimeVoiceIds);
          activeRealtimeSynth ??= stereoVoice.realtimeSynth;
          if (stereoVoice.releaseDuration > maxRelease) {
            maxRelease = stereoVoice.releaseDuration;
          }
          continue;
        }
      }

      effectiveHandledSampleIds.add(sample.id);
      final voice = await playSample(
        sample,
        key: key,
        velocity: velocity,
        volume: customVolume,
        baseVolume: baseVolume,
        pan: customPan,
        atTime: atTime,
        duration: duration,
        zone: zone,
        presetZone: presetZone,
        trackVoice: false,
        busId: busId,
      );

      allHandles.addAll(voice.handles);
      allSources.addAll(voice.sources);
      allBaseSpeeds.addAll(voice.baseSpeeds);
      allBaseVolumes.addAll(voice.baseVolumes);
      allBasePans.addAll(voice.basePans);
      allExclusiveClasses.addAll(voice.exclusiveClasses);
      allRealtimeVoiceIds.addAll(voice.realtimeVoiceIds);
      activeRealtimeSynth ??= voice.realtimeSynth;
      if (voice.releaseDuration > maxRelease) {
        maxRelease = voice.releaseDuration;
      }
    }

    final compoundVoice = SoundFontVoice(
      key: key,
      velocity: velocity,
      handles: allHandles,
      sources: allSources,
      releaseDuration: maxRelease,
      baseSpeeds: allBaseSpeeds,
      baseVolumes: allBaseVolumes,
      basePans: allBasePans,
      exclusiveClasses: allExclusiveClasses,
      realtimeVoiceIds: allRealtimeVoiceIds,
      realtimeSynth: activeRealtimeSynth,
    );

    if (trackVoice) {
      _trackVoice(key, compoundVoice);
    }
    return compoundVoice;
  }

  /// Plays a [Preset] for a given MIDI [key] and [velocity], with optional
  /// sample-accurate engine clock scheduling.
  Future<SoundFontVoice> playPreset(
    Preset preset, {
    int key = 60,
    int velocity = 100,
    double? customVolume,
    double? baseVolume,
    double? customPan,
    Duration? atTime,
    Duration? duration,
    bool trackVoice = true,
    int? busId,
  }) async {
    if (trackVoice) {
      _heldKeys.add(key);
    }
    var matchingPresetZones = preset.zones
        .where((pz) => pz.matches(key, velocity))
        .toList();

    if (matchingPresetZones.isEmpty) {
      matchingPresetZones = preset.zones.take(1).toList();
    }

    if (matchingPresetZones.isEmpty) {
      return SoundFontVoice(key: key, velocity: velocity, handles: []);
    }

    final allHandles = <SoundHandle>[];
    final allSources = <AudioSource>[];
    final allBaseSpeeds = <double>[];
    final allBaseVolumes = <double>[];
    final allBasePans = <double>[];
    final allExclusiveClasses = <int>{};
    final allRealtimeVoiceIds = <int>[];
    RealtimeSoundFontSynthesizer? activeRealtimeSynth;
    Duration maxRelease = options.defaultReleaseDuration;
    final handledSampleIds = <int>{};

    for (final pz in matchingPresetZones) {
      final inst =
          (pz.instrumentID != null &&
              pz.instrumentID! < soundFont.instruments.length)
          ? soundFont.instruments[pz.instrumentID!]
          : null;

      if (inst != null) {
        final voice = await playInstrument(
          inst,
          key: key,
          velocity: velocity,
          customVolume: customVolume,
          baseVolume: baseVolume,
          customPan: customPan,
          atTime: atTime,
          duration: duration,
          presetZone: pz,
          trackVoice: false,
          handledSampleIds: handledSampleIds,
          busId: busId,
        );
        allHandles.addAll(voice.handles);
        allSources.addAll(voice.sources);
        allBaseSpeeds.addAll(voice.baseSpeeds);
        allBaseVolumes.addAll(voice.baseVolumes);
        allBasePans.addAll(voice.basePans);
        allExclusiveClasses.addAll(voice.exclusiveClasses);
        allRealtimeVoiceIds.addAll(voice.realtimeVoiceIds);
        activeRealtimeSynth ??= voice.realtimeSynth;
        if (voice.releaseDuration > maxRelease) {
          maxRelease = voice.releaseDuration;
        }
      } else if (pz.sampleRef != null || pz.sampleID != null) {
        final sample =
            pz.sampleRef ??
            (pz.sampleID != null && pz.sampleID! < soundFont.samples.length
                ? soundFont.samples[pz.sampleID!]
                : null);
        if (sample != null && !handledSampleIds.contains(sample.id)) {
          if (options.joinStereoChannels &&
              StereoJoiner.isStereoCandidate(sample)) {
            final pairedSample = StereoJoiner.findLinkedSample(
              soundFont,
              sample,
            );
            if (pairedSample != null) {
              handledSampleIds.add(sample.id);
              handledSampleIds.add(pairedSample.id);
              final leftSample = sample.isLeft ? sample : pairedSample;
              final rightSample = sample.isRight ? sample : pairedSample;

              final stereoVoice = await _playJoinedStereoPair(
                leftSample: leftSample,
                rightSample: rightSample,
                key: key,
                velocity: velocity,
                presetZone: pz,
                customVolume: customVolume,
                baseVolume: baseVolume,
                customPan: customPan,
                atTime: atTime,
                duration: duration,
                busId: busId,
              );

              allHandles.addAll(stereoVoice.handles);
              allSources.addAll(stereoVoice.sources);
              allBaseSpeeds.addAll(stereoVoice.baseSpeeds);
              allBaseVolumes.addAll(stereoVoice.baseVolumes);
              allBasePans.addAll(stereoVoice.basePans);
              allExclusiveClasses.addAll(stereoVoice.exclusiveClasses);
              allRealtimeVoiceIds.addAll(stereoVoice.realtimeVoiceIds);
              activeRealtimeSynth ??= stereoVoice.realtimeSynth;
              if (stereoVoice.releaseDuration > maxRelease) {
                maxRelease = stereoVoice.releaseDuration;
              }
              continue;
            }
          }

          handledSampleIds.add(sample.id);
          final voice = await playSample(
            sample,
            key: key,
            velocity: velocity,
            volume: customVolume,
            baseVolume: baseVolume,
            pan: customPan,
            atTime: atTime,
            duration: duration,
            presetZone: pz,
            trackVoice: false,
            busId: busId,
          );
          allHandles.addAll(voice.handles);
          allSources.addAll(voice.sources);
          allBaseSpeeds.addAll(voice.baseSpeeds);
          allBaseVolumes.addAll(voice.baseVolumes);
          allBasePans.addAll(voice.basePans);
          allExclusiveClasses.addAll(voice.exclusiveClasses);
          allRealtimeVoiceIds.addAll(voice.realtimeVoiceIds);
          activeRealtimeSynth ??= voice.realtimeSynth;
          if (voice.releaseDuration > maxRelease) {
            maxRelease = voice.releaseDuration;
          }
        }
      }
    }

    final compoundVoice = SoundFontVoice(
      key: key,
      velocity: velocity,
      handles: allHandles,
      sources: allSources,
      releaseDuration: maxRelease,
      baseSpeeds: allBaseSpeeds,
      baseVolumes: allBaseVolumes,
      basePans: allBasePans,
      exclusiveClasses: allExclusiveClasses,
      realtimeVoiceIds: allRealtimeVoiceIds,
      realtimeSynth: activeRealtimeSynth,
    );

    if (trackVoice) {
      _trackVoice(key, compoundVoice);
    }
    return compoundVoice;
  }

  /// Schedules a [Preset] playback at an absolute engine [atTime] with optional [duration].
  Future<SoundFontVoice> playPresetScheduled(
    Preset preset, {
    required Duration atTime,
    Duration? duration,
    int key = 60,
    int velocity = 100,
    double? customVolume,
    double? baseVolume,
    double? customPan,
  }) => playPreset(
    preset,
    key: key,
    velocity: velocity,
    customVolume: customVolume,
    baseVolume: baseVolume,
    customPan: customPan,
    atTime: atTime,
    duration: duration,
  );

  /// Schedules an [Instrument] playback at an absolute engine [atTime] with optional [duration].
  Future<SoundFontVoice> playInstrumentScheduled(
    Instrument instrument, {
    required Duration atTime,
    Duration? duration,
    int key = 60,
    int velocity = 100,
    double? customVolume,
    double? baseVolume,
    double? customPan,
  }) => playInstrument(
    instrument,
    key: key,
    velocity: velocity,
    customVolume: customVolume,
    baseVolume: baseVolume,
    customPan: customPan,
    atTime: atTime,
    duration: duration,
  );

  /// Schedules a [SampleInfo] playback at an absolute engine [atTime] with optional [duration].
  Future<SoundFontVoice> playSampleScheduled(
    SampleInfo sample, {
    required Duration atTime,
    Duration? duration,
    int key = 60,
    int velocity = 100,
    double? volume,
    double? pan,
    double? pitchRatio,
    Zone? zone,
    Zone? presetZone,
  }) => playSample(
    sample,
    key: key,
    velocity: velocity,
    volume: volume,
    pan: pan,
    pitchRatio: pitchRatio,
    atTime: atTime,
    duration: duration,
    zone: zone,
    presetZone: presetZone,
  );

  /// Note-on trigger: plays specified [preset], [instrument], or default bank/instrument.
  Future<SoundFontVoice> noteOn(
    int key, {
    int velocity = 100,
    Instrument? instrument,
    Preset? preset,
    double? customVolume,
    double? customPan,
    Duration? atTime,
    Duration? duration,
  }) async {
    if (preset != null) {
      return playPreset(
        preset,
        key: key,
        velocity: velocity,
        customVolume: customVolume,
        customPan: customPan,
        atTime: atTime,
        duration: duration,
      );
    }

    if (instrument != null) {
      return playInstrument(
        instrument,
        key: key,
        velocity: velocity,
        customVolume: customVolume,
        customPan: customPan,
        atTime: atTime,
        duration: duration,
      );
    }

    if (soundFont.presets.isNotEmpty) {
      return playPreset(
        soundFont.presets.first,
        key: key,
        velocity: velocity,
        customVolume: customVolume,
        customPan: customPan,
        atTime: atTime,
        duration: duration,
      );
    }

    if (soundFont.instruments.isNotEmpty) {
      return playInstrument(
        soundFont.instruments.first,
        key: key,
        velocity: velocity,
        customVolume: customVolume,
        customPan: customPan,
        atTime: atTime,
        duration: duration,
      );
    }

    if (soundFont.samples.isNotEmpty) {
      return playSample(
        soundFont.samples.first,
        key: key,
        velocity: velocity,
        volume: customVolume,
        pan: customPan,
        atTime: atTime,
        duration: duration,
      );
    }

    return SoundFontVoice(key: key, velocity: velocity, handles: []);
  }

  /// Note-off trigger: initiates release volume envelope on all voices for [key].
  Future<void> noteOff(int key, {Duration? releaseDuration}) async {
    _heldKeys.remove(key);
    final voices = _activeVoices.remove(key);
    if (voices == null || voices.isEmpty) return;

    final releasingList = _releasingVoices.putIfAbsent(key, () => []);
    for (final voice in voices) {
      releasingList.add(voice);
      final fade = releaseDuration ?? voice.releaseDuration;
      Timer(fade + const Duration(milliseconds: 50), () {
        releasingList.remove(voice);
      });
      await voice.release(customRelease: releaseDuration);
    }
  }

  /// Stops all active voices across all keys.
  Future<void> allNotesOff({Duration? releaseDuration}) async {
    _heldKeys.clear();
    final allKeys = _activeVoices.keys.toList();
    for (final key in allKeys) {
      await noteOff(key, releaseDuration: releaseDuration);
    }
    _activeVoices.clear();
    _releasingVoices.clear();
    _realtimeSynth?.allNotesOff(releaseDuration: releaseDuration);
  }

  /// Immediately terminates all sounds in the SoLoud mixer output and clears active voices.
  Future<void> stopMixerOutput() async {
    await allNotesOff(releaseDuration: Duration.zero);
    if (SoLoud.instance.isInitialized) {
      try {
        SoLoud.instance.stopAll();
      } catch (_) {}
    }
  }

  /// Preloads audio bytes and optionally prepares the [AudioSource] for [sample] into cache.
  Future<void> preloadSample(
    SampleInfo sample, {
    bool createAudioSource = true,
  }) async {
    await _getOrLoadSampleAudioSource(
      sample,
      createAudioSource: createAudioSource,
    );
  }

  /// Preloads audio bytes and prepares the stereo [AudioSource] for a left-right sample pair.
  Future<void> preloadStereoPair(
    SampleInfo leftSample,
    SampleInfo rightSample, {
    bool createAudioSource = true,
  }) async {
    await _getOrLoadStereoAudioSource(
      leftSample,
      rightSample,
      createAudioSource: createAudioSource,
    );
  }

  /// Preloads all samples needed for [instrument] with optional progress callback.
  Future<void> preloadInstrument(
    Instrument instrument, {
    void Function(double progress, int loaded, int total)? onProgress,
    bool createAudioSources = true,
  }) async {
    final samples = <SampleInfo>{};
    for (final zone in instrument.zones) {
      final sample =
          zone.sampleRef ??
          (zone.sampleID != null && zone.sampleID! < soundFont.samples.length
              ? soundFont.samples[zone.sampleID!]
              : null);
      if (sample != null) samples.add(sample);
    }

    final total = samples.length;
    if (total == 0) {
      onProgress?.call(1.0, 0, 0);
      return;
    }

    final stereoPairs = <(SampleInfo, SampleInfo)>[];
    final pairedSampleIds = <int>{};

    if (options.joinStereoChannels) {
      for (final sample in samples) {
        if (sample.isLeft && !pairedSampleIds.contains(sample.id)) {
          final right = StereoJoiner.findLinkedSample(soundFont, sample);
          if (right != null) {
            stereoPairs.add((sample, right));
            pairedSampleIds.add(sample.id);
            pairedSampleIds.add(right.id);
          }
        }
      }
    }

    final monoSamples = <SampleInfo>[];
    for (final sample in samples) {
      if (!pairedSampleIds.contains(sample.id)) {
        monoSamples.add(sample);
      }
    }

    int loadedCount = 0;

    for (final (left, right) in stereoPairs) {
      await preloadStereoPair(
        left,
        right,
        createAudioSource: createAudioSources,
      );
      final countIncrement =
          (samples.contains(left) ? 1 : 0) + (samples.contains(right) ? 1 : 0);
      loadedCount += countIncrement > 0 ? countIncrement : 2;
      onProgress?.call(
        (loadedCount / total).clamp(0.0, 1.0),
        loadedCount.clamp(0, total),
        total,
      );
    }

    for (final sample in monoSamples) {
      await preloadSample(sample, createAudioSource: createAudioSources);
      loadedCount += 1;
      onProgress?.call(
        (loadedCount / total).clamp(0.0, 1.0),
        loadedCount.clamp(0, total),
        total,
      );
    }
  }

  /// Preloads all samples needed for [preset] with optional progress callback.
  Future<void> preloadPreset(
    Preset preset, {
    void Function(double progress, int loaded, int total)? onProgress,
    bool createAudioSources = true,
  }) async {
    final samples = <SampleInfo>{};
    for (final pz in preset.zones) {
      final inst =
          (pz.instrumentID != null &&
              pz.instrumentID! < soundFont.instruments.length)
          ? soundFont.instruments[pz.instrumentID!]
          : null;
      if (inst != null) {
        for (final iz in inst.zones) {
          final s =
              iz.sampleRef ??
              (iz.sampleID != null && iz.sampleID! < soundFont.samples.length
                  ? soundFont.samples[iz.sampleID!]
                  : null);
          if (s != null) samples.add(s);
        }
      }
      final s =
          pz.sampleRef ??
          (pz.sampleID != null && pz.sampleID! < soundFont.samples.length
              ? soundFont.samples[pz.sampleID!]
              : null);
      if (s != null) samples.add(s);
    }

    final total = samples.length;
    if (total == 0) {
      onProgress?.call(1.0, 0, 0);
      return;
    }

    final stereoPairs = <(SampleInfo, SampleInfo)>[];
    final pairedSampleIds = <int>{};

    if (options.joinStereoChannels) {
      for (final sample in samples) {
        if (sample.isLeft && !pairedSampleIds.contains(sample.id)) {
          final right = StereoJoiner.findLinkedSample(soundFont, sample);
          if (right != null) {
            stereoPairs.add((sample, right));
            pairedSampleIds.add(sample.id);
            pairedSampleIds.add(right.id);
          }
        }
      }
    }

    final monoSamples = <SampleInfo>[];
    for (final sample in samples) {
      if (!pairedSampleIds.contains(sample.id)) {
        monoSamples.add(sample);
      }
    }

    int loadedCount = 0;

    for (final (left, right) in stereoPairs) {
      await preloadStereoPair(
        left,
        right,
        createAudioSource: createAudioSources,
      );
      final countIncrement =
          (samples.contains(left) ? 1 : 0) + (samples.contains(right) ? 1 : 0);
      loadedCount += countIncrement > 0 ? countIncrement : 2;
      onProgress?.call(
        (loadedCount / total).clamp(0.0, 1.0),
        loadedCount.clamp(0, total),
        total,
      );
    }

    for (final sample in monoSamples) {
      await preloadSample(sample, createAudioSource: createAudioSources);
      loadedCount += 1;
      onProgress?.call(
        (loadedCount / total).clamp(0.0, 1.0),
        loadedCount.clamp(0, total),
        total,
      );
    }
  }

  /// Preloads all samples in the entire [soundFont] with optional progress callback.
  Future<void> preloadAll({
    void Function(double progress, int loaded, int total)? onProgress,
    bool createAudioSources = true,
  }) async {
    final total = soundFont.samples.length;
    if (total == 0) {
      onProgress?.call(1.0, 0, 0);
      return;
    }

    final stereoPairs = <(SampleInfo, SampleInfo)>[];
    final pairedSampleIds = <int>{};

    // Group stereo pairs first if enabled
    if (options.joinStereoChannels) {
      for (final sample in soundFont.samples) {
        if (sample.isLeft && !pairedSampleIds.contains(sample.id)) {
          final right = StereoJoiner.findLinkedSample(soundFont, sample);
          if (right != null) {
            stereoPairs.add((sample, right));
            pairedSampleIds.add(sample.id);
            pairedSampleIds.add(right.id);
          }
        }
      }
    }

    final monoSamples = <SampleInfo>[];
    for (final sample in soundFont.samples) {
      if (!pairedSampleIds.contains(sample.id)) {
        monoSamples.add(sample);
      }
    }

    int loadedCount = 0;

    for (final (left, right) in stereoPairs) {
      await preloadStereoPair(
        left,
        right,
        createAudioSource: createAudioSources,
      );
      loadedCount += 2;
      onProgress?.call(
        (loadedCount / total).clamp(0.0, 1.0),
        loadedCount.clamp(0, total),
        total,
      );
    }

    for (final sample in monoSamples) {
      await preloadSample(sample, createAudioSource: createAudioSources);
      loadedCount += 1;
      onProgress?.call(
        (loadedCount / total).clamp(0.0, 1.0),
        loadedCount.clamp(0, total),
        total,
      );
    }
  }

  Future<SoundFontVoice> _playJoinedStereoPair({
    required SampleInfo leftSample,
    required SampleInfo rightSample,
    required int key,
    required int velocity,
    Zone? zone,
    Zone? presetZone,
    double? customVolume,
    double? baseVolume,
    double? customPan,
    Duration? atTime,
    Duration? duration,
    int? busId,
  }) async {
    final exc = VoiceCalculator.resolveExclusiveClass(
      zone: zone,
      presetZone: presetZone,
    );
    if (exc.offByGroup != null) {
      await _chokeExclusiveClassVoices(exc.offByGroup!, atTime: atTime);
    }

    final speed = VoiceCalculator.calculatePitchRatio(
      key: key,
      sample: leftSample,
      zone: zone,
      presetZone: presetZone,
    );

    final vol =
        customVolume ??
        VoiceCalculator.calculateVolume(
          velocity: velocity,
          zone: zone,
          presetZone: presetZone,
          masterVolume: options.masterVolume,
        );

    if (!SoLoud.instance.isInitialized) {
      return SoundFontVoice(key: key, velocity: velocity, handles: []);
    }

    final p = customPan ?? VoiceCalculator.calculatePan(presetZone: presetZone);

    final loopInfo = VoiceCalculator.calculateLoopRegion(
      sample: leftSample,
      zone: zone,
    );

    final releaseDuration = VoiceCalculator.calculateReleaseDuration(
      zone: zone,
      presetZone: presetZone,
      defaultDuration: options.defaultReleaseDuration,
      sustainTime: _sustainTime,
      sustain: _sustain,
    );

    final validLoop =
        loopInfo.isLooping &&
        loopInfo.startFrames >= 0 &&
        loopInfo.endFrames != null &&
        loopInfo.endFrames! > loopInfo.startFrames;

    // Mode B: Worker-Isolate Real-Time Synthesizer (16-bit PCM samples)
    if (options.synthMode == SoundFontSynthMode.realtimeIsolateSynth &&
        leftSample.compression == SampleCompression.pcm16 &&
        rightSample.compression == SampleCompression.pcm16) {
      final synth = await ensureRealtimeSynthesizer();
      Uint8List? leftBytes = _sampleBytesCache[leftSample.id];
      if (leftBytes == null) {
        final b = await soundFont.getSampleBytes(leftSample);
        if (b.isNotEmpty) {
          _sampleBytesCache[leftSample.id] = b;
          leftBytes = b;
        }
      }
      Uint8List? rightBytes = _sampleBytesCache[rightSample.id];
      if (rightBytes == null) {
        final b = await soundFont.getSampleBytes(rightSample);
        if (b.isNotEmpty) {
          _sampleBytesCache[rightSample.id] = b;
          rightBytes = b;
        }
      }
      if (leftBytes != null && leftBytes.isNotEmpty) {
        synth.registerSamplePcm(leftSample.id, leftBytes);
        if (rightBytes != null && rightBytes.isNotEmpty) {
          synth.registerSamplePcm(rightSample.id, rightBytes);
        }
        final vId = synth.triggerVoice(
          key: key,
          velocity: velocity,
          leftSample: leftSample,
          rightSample: rightBytes != null ? rightSample : null,
          zone: zone,
          presetZone: presetZone,
          basePitchRatio: speed,
          peakVolume: vol,
          pan: p,
          isLooping: validLoop,
          loopStart: validLoop ? loopInfo.startFrames : 0,
          loopEnd: validLoop ? (loopInfo.endFrames ?? 0) : 0,
          releaseDuration: releaseDuration,
        );
        final voice = SoundFontVoice(
          key: key,
          velocity: velocity,
          handles: const [],
          releaseDuration: releaseDuration,
          sampleId: leftSample.id,
          baseSpeeds: [speed],
          baseVolumes: [baseVolume ?? vol],
          basePans: [p],
          exclusiveClasses: exc.exclusiveClass != null
              ? {exc.exclusiveClass!}
              : const {},
          realtimeVoiceIds: [vId],
          realtimeSynth: synth,
        );
        if (duration != null) {
          voice.addEnvelopeTimer(
            Timer(duration, () => voice.release()),
          );
        }
        return voice;
      }
    }

    final audio = await _getOrLoadStereoAudioSource(leftSample, rightSample);
    if (audio == null) {
      return SoundFontVoice(key: key, velocity: velocity, handles: []);
    }

    final volStages = VoiceCalculator.calculateVolEnvStages(
      zone: zone,
      presetZone: presetZone,
      peakVolume: vol,
    );
    final scheduledAt = (atTime ?? Duration.zero) + volStages.delay;
    final hasAttack = volStages.attack > const Duration(milliseconds: 5);
    final initialVol = hasAttack ? 0.01 : vol;
    final targetBusId = busId ?? effectiveBusId;

    _activatePerVoiceFilterOnSourceIfNeeded(audio, zone: zone, presetZone: presetZone);

    // joinTwoSources resamples both channels to the engine sample rate, so
    // scale loop frame offsets from leftSample.sampleRate to engineSampleRate.
    final engineRate = SoLoud.instance.sampleRate;
    final sampleRateScale =
        (engineRate > 0 &&
            leftSample.sampleRate > 0 &&
            engineRate != leftSample.sampleRate)
        ? (engineRate / leftSample.sampleRate)
        : 1.0;
    final scaledLoopStart = validLoop
        ? (loopInfo.startFrames * sampleRateScale).round()
        : null;
    final scaledLoopEnd = (validLoop && loopInfo.endFrames != null)
        ? (loopInfo.endFrames! * sampleRateScale).round()
        : null;

    final handle = SoLoud.instance.playScheduled(
      audio,
      scheduledAt,
      duration: duration,
      volume: initialVol,
      pan: p,
      scale: speed,
      looping: validLoop,
      loopingStartOffsetAt: scaledLoopStart,
      loopingEndOffsetAt: scaledLoopEnd,
      busId: targetBusId,
    );

    _applyPerVoiceFilterIfNeeded(audio, handle, zone: zone, presetZone: presetZone);

    final voice = SoundFontVoice(
      key: key,
      velocity: velocity,
      handles: [handle],
      sources: [audio],
      releaseDuration: releaseDuration,
      sampleId: leftSample.id,
      baseSpeeds: [speed],
      baseVolumes: [baseVolume ?? vol],
      basePans: [p],
      exclusiveClasses: exc.exclusiveClass != null
          ? {exc.exclusiveClass!}
          : const {},
    );

    _scheduleDahdsrStages(
      voice: voice,
      handle: handle,
      peakVolume: vol,
      volStages: volStages,
      atTime: atTime,
      scheduledStart: scheduledAt,
      duration: duration,
      releaseDuration: releaseDuration,
    );

    return voice;
  }

  Future<void> _chokeExclusiveClassVoices(
    int chokeGroup, {
    Duration? atTime,
  }) async {
    for (final voiceList in _activeVoices.values) {
      for (final v in voiceList) {
        if (!v.isReleased && v.exclusiveClasses.contains(chokeGroup)) {
          await v.choke(atTime: atTime);
        }
      }
    }
  }

  void _activatePerVoiceFilterOnSourceIfNeeded(
    AudioSource audio, {
    Zone? zone,
    Zone? presetZone,
  }) {
    if (!options.enablePerVoiceFilter) return;
    final filter = VoiceCalculator.calculateFilterParams(
      zone: zone,
      presetZone: presetZone,
    );
    if (!filter.enabled) return;

    try {
      final biquad = audio.filters.biquadFilter;
      if (!biquad.isActive) {
        biquad.activate();
      }
    } catch (_) {
      // Gracefully ignore if single-source filter is unsupported on current target
    }
  }

  void _applyPerVoiceFilterIfNeeded(
    AudioSource audio,
    SoundHandle handle, {
    Zone? zone,
    Zone? presetZone,
  }) {
    if (!options.enablePerVoiceFilter) return;
    final filter = VoiceCalculator.calculateFilterParams(
      zone: zone,
      presetZone: presetZone,
    );
    if (!filter.enabled) return;

    try {
      final biquad = audio.filters.biquadFilter;
      if (!biquad.isActive) {
        biquad.activate();
      }
      biquad.frequency(soundHandle: handle).value = filter.cutoffHz;
      biquad.resonance(soundHandle: handle).value = filter.resonanceQ;
      biquad.wet(soundHandle: handle).value = 1.0;
    } catch (_) {
      // Gracefully ignore if single-source filter is unsupported on current target
    }
  }

  void _scheduleDahdsrStages({
    required SoundFontVoice voice,
    required SoundHandle handle,
    required double peakVolume,
    required ({
      Duration delay,
      Duration attack,
      Duration hold,
      Duration decay,
      double sustainVolume,
    })
    volStages,
    required Duration? atTime,
    required Duration scheduledStart,
    required Duration? duration,
    required Duration releaseDuration,
  }) {
    final hasAttack = volStages.attack > const Duration(milliseconds: 5);
    final hasDecay =
        volStages.decay > const Duration(milliseconds: 5) &&
        (peakVolume - volStages.sustainVolume).abs() > 0.005;

    if (atTime != null) {
      if (hasAttack) {
        SoLoud.instance.fadeScheduled(
          handle,
          scheduledStart,
          peakVolume,
          volStages.attack,
        );
      }
      if (hasDecay) {
        final decayStart = scheduledStart + volStages.attack + volStages.hold;
        if (duration == null || decayStart < scheduledStart + duration) {
          if (!hasAttack && duration == null) {
            SoLoud.instance.fadeScheduled(
              handle,
              decayStart,
              volStages.sustainVolume,
              volStages.decay,
              thenStop: volStages.sustainVolume <= 0.0005,
            );
          } else {
            final timeToDecay =
                volStages.delay + volStages.attack + volStages.hold;
            voice.addEnvelopeTimer(
              Timer(timeToDecay, () {
                if (!voice.isReleased &&
                    SoLoud.instance.getIsValidVoiceHandle(handle)) {
                  SoLoud.instance.fadeScheduled(
                    handle,
                    decayStart,
                    volStages.sustainVolume,
                    volStages.decay,
                    thenStop: volStages.sustainVolume <= 0.0005,
                  );
                }
              }),
            );
          }
        }
      }
      if (duration != null) {
        final noteOffTime = scheduledStart + duration;
        if (!hasAttack && !hasDecay) {
          if (releaseDuration > Duration.zero) {
            SoLoud.instance.fadeScheduled(
              handle,
              noteOffTime,
              0.0,
              releaseDuration,
              thenStop: true,
            );
          } else {
            SoLoud.instance.stopScheduled(handle, noteOffTime);
          }
        } else {
          voice.addEnvelopeTimer(
            Timer(volStages.delay + duration, () {
              if (!voice.isReleased &&
                  SoLoud.instance.getIsValidVoiceHandle(handle)) {
                if (releaseDuration > Duration.zero) {
                  SoLoud.instance.fadeScheduled(
                    handle,
                    noteOffTime,
                    0.0,
                    releaseDuration,
                    thenStop: true,
                  );
                } else {
                  SoLoud.instance.stopScheduled(handle, noteOffTime);
                }
              }
            }),
          );
        }
      }
      return;
    }

    // Immediate real-time playback (atTime == null)
    if (hasAttack) {
      if (volStages.delay > Duration.zero) {
        voice.addEnvelopeTimer(
          Timer(volStages.delay, () {
            if (!voice.isReleased &&
                SoLoud.instance.getIsValidVoiceHandle(handle)) {
              SoLoud.instance.fadeVolume(handle, peakVolume, volStages.attack);
            }
          }),
        );
      } else {
        SoLoud.instance.fadeVolume(handle, peakVolume, volStages.attack);
      }
    }

    if (hasDecay) {
      final timeToDecay = volStages.delay + volStages.attack + volStages.hold;
      if (timeToDecay > Duration.zero) {
        voice.addEnvelopeTimer(
          Timer(timeToDecay, () {
            if (!voice.isReleased &&
                SoLoud.instance.getIsValidVoiceHandle(handle)) {
              final now = SoLoud.instance.isInitialized
                  ? SoLoud.instance.getEngineTime()
                  : Duration.zero;
              SoLoud.instance.fadeScheduled(
                handle,
                now,
                volStages.sustainVolume,
                volStages.decay,
                thenStop: volStages.sustainVolume <= 0.0005,
              );
            }
          }),
        );
      } else {
        final now = SoLoud.instance.isInitialized
            ? SoLoud.instance.getEngineTime()
            : Duration.zero;
        SoLoud.instance.fadeScheduled(
          handle,
          now,
          volStages.sustainVolume,
          volStages.decay,
          thenStop: volStages.sustainVolume <= 0.0005,
        );
      }
    }

    if (duration != null) {
      final totalNoteHold = volStages.delay + duration;
      voice.addEnvelopeTimer(
        Timer(totalNoteHold, () {
          voice.release(customRelease: releaseDuration);
        }),
      );
    }
  }

  /// Returns all active sound handles playing the given [sample].
  List<SoundHandle> getActiveHandlesForSample(SampleInfo sample) {
    final result = <SoundHandle>[];
    final cachedSource = _audioSourceCache[_sampleCacheKey(sample.id)];

    for (final voiceList in _activeVoices.values) {
      for (final voice in voiceList) {
        if (voice.isReleased) continue;
        final isMatch =
            voice.sampleId == sample.id ||
            (cachedSource != null && voice.sources.contains(cachedSource));

        if (isMatch) {
          for (final handle in voice.handles) {
            if (SoLoud.instance.isInitialized &&
                SoLoud.instance.getIsValidVoiceHandle(handle)) {
              result.add(handle);
            }
          }
        }
      }
    }
    return result;
  }

  void _trackVoice(int key, SoundFontVoice voice) {
    if (!_heldKeys.contains(key)) {
      // Key was already released while this voice was being prepared asynchronously
      voice.release();
      return;
    }
    // Dampen existing active or releasing voices for the same key to avoid voice pile-up and phase artifacts
    final existing = _activeVoices[key];
    if (existing != null && existing.isNotEmpty) {
      for (final v in existing) {
        v.release(customRelease: const Duration(milliseconds: 15));
      }
      existing.clear();
    }
    final releasing = _releasingVoices.remove(key);
    if (releasing != null && releasing.isNotEmpty) {
      for (final v in releasing) {
        v.release(customRelease: const Duration(milliseconds: 15));
      }
    }
    _activeVoices.putIfAbsent(key, () => []).add(voice);
  }

  /// Releases all player resources and stops all playing handles.
  Future<void> dispose() async {
    await allNotesOff();
    if (_realtimeSynth != null) {
      await _realtimeSynth!.dispose();
      _realtimeSynth = null;
    }
    if (_ownsMixingBus && _mixingBus != null) {
      try {
        _mixingBus!.dispose();
      } catch (_) {}
      _mixingBus = null;
      _ownsMixingBus = false;
    }
    _loadingAudioSources.clear();
    for (final audio in _audioSourceCache.values) {
      try {
        await SoLoud.instance.disposeSource(audio);
      } catch (_) {}
    }
    _audioSourceCache.clear();
    _sampleBytesCache.clear();
    _stereoBytesCache.clear();
  }
}
