import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import '../models/instrument.dart';
import '../models/preset.dart';
import '../models/sample_info.dart';
import '../models/zone.dart';
import '../soundfont_file.dart';
import 'player_options.dart';
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

  /// In-memory cache for raw or interleaved sample bytes.
  final Map<int, Uint8List> _sampleBytesCache = {};

  /// In-memory cache for joined stereo PCM bytes keyed by "leftId_rightId".
  final Map<String, Uint8List> _stereoBytesCache = {};

  /// In-memory cache for preserved [AudioSource] instances.
  final Map<String, AudioSource> _audioSourceCache = {};

  SoundFontPlayer({
    required this.soundFont,
    this.options = const SoundFontPlayerOptions(),
  })  : _sustainTime = options.sustainTime,
        _sustainMultiplier = options.sustainMultiplier;

  double? _sustainTime;
  double _sustainMultiplier = 1.0;

  /// Global sustain duration in seconds (e.g. 0.05 to 5.0).
  /// Used when notes or zones have no native release envelope.
  double? get sustainTime => _sustainTime;
  set sustainTime(double? value) {
    _sustainTime = value?.clamp(0.01, 10.0);
  }

  /// Global sustain multiplier (e.g. 0.0 to 10.0, default 1.0).
  /// Scales the native release envelope when notes or zones define one.
  double get sustainMultiplier => _sustainMultiplier;
  set sustainMultiplier(double value) {
    _sustainMultiplier = value.clamp(0.0, 20.0);
  }

  /// Plays a single [SampleInfo] with optional pitch, volume, pan, loop,
  /// and sample-accurate engine scheduling overrides.
  Future<SoundFontVoice> playSample(
    SampleInfo sample, {
    int key = 60,
    int velocity = 100,
    double? volume,
    double? pan,
    double? pitchRatio,
    bool? looping,
    Duration? loopingStartAt,
    Duration? loopingEndAt,
    Duration? atTime,
    Duration? duration,
    Zone? zone,
    Zone? presetZone,
    bool trackVoice = true,
  }) async {
    final speed = pitchRatio ??
        VoiceCalculator.calculatePitchRatio(
          key: key,
          sample: sample,
          zone: zone,
          presetZone: presetZone,
        );

    final vol = volume ??
        VoiceCalculator.calculateVolume(
          velocity: velocity,
          zone: zone,
          presetZone: presetZone,
          masterVolume: options.masterVolume,
        );

    final p = pan ??
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
    final loopStart = loopingStartAt ?? loopInfo.loopStart;
    final loopEnd = loopingEndAt ?? loopInfo.loopEnd;

    final releaseDuration = VoiceCalculator.calculateReleaseDuration(
      zone: zone,
      presetZone: presetZone,
      defaultDuration: options.defaultReleaseDuration,
      sustainTime: _sustainTime,
      sustainMultiplier: _sustainMultiplier,
    );

    AudioSource audio;
    final cacheKey = 'sample_${sample.id}';

    if (options.cacheAudioSources && _audioSourceCache.containsKey(cacheKey)) {
      audio = _audioSourceCache[cacheKey]!;
    } else {
      Uint8List? preloaded;
      if (_sampleBytesCache.containsKey(sample.id)) {
        preloaded = _sampleBytesCache[sample.id];
      }

      audio = SampleStreamer.streamSample(
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
    }

    final validLoop = shouldLoop && loopEnd != null && loopEnd > loopStart;
    final useScheduled = !validLoop &&
        (atTime != null || duration != null || options.useScheduledPlayback);

    SoundHandle handle;
    if (useScheduled) {
      final scheduledAt = atTime ??
          (SoLoud.instance.isInitialized
              ? SoLoud.instance.getEngineTime()
              : Duration.zero);

      final attackSec = zone?.volEnvAttack ?? presetZone?.volEnvAttack;
      final hasAttack = attackSec != null && attackSec > 0.005;

      handle = SoLoud.instance.playScheduled(
        audio,
        scheduledAt,
        duration: (duration != null && releaseDuration == Duration.zero)
            ? duration
            : null,
        volume: hasAttack ? 0.0 : vol,
        pan: p,
        busId: options.defaultBusId,
      );

      if (hasAttack) {
        final attackDuration =
            Duration(microseconds: (attackSec * 1000000).round());
        SoLoud.instance.fadeScheduled(
          handle,
          scheduledAt,
          vol,
          attackDuration,
        );
      }

      if (duration != null) {
        final noteOffTime = scheduledAt + duration;
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
    } else {
      handle = SoLoud.instance.play(
        audio,
        volume: vol,
        pan: p,
        looping: validLoop,
        loopingStartAt: validLoop ? loopStart : Duration.zero,
        loopingEndAt: validLoop ? loopEnd : null,
        busId: options.defaultBusId,
      );
    }

    if (speed != 1.0) {
      SoLoud.instance.setRelativePlaySpeed(handle, speed);
    }

    final voice = SoundFontVoice(
      key: key,
      velocity: velocity,
      handles: [handle],
      sources: [audio],
      releaseDuration: releaseDuration,
      sampleId: sample.id,
    );

    if (trackVoice) {
      _trackVoice(key, voice);
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
    double? customPan,
    Duration? atTime,
    Duration? duration,
    Zone? presetZone,
    bool trackVoice = true,
  }) async {
    // Find matching zones for this key and velocity
    var matchingZones = instrument.zones
        .where((z) =>
            z.matches(key, velocity) &&
            (z.sampleRef != null || z.sampleID != null))
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
    Duration maxRelease = options.defaultReleaseDuration;

    // Check for stereo sample pairs among matching zones
    final handledSampleIds = <int>{};

    for (int i = 0; i < matchingZones.length; i++) {
      final zone = matchingZones[i];
      final sample = zone.sampleRef ??
          (zone.sampleID != null && zone.sampleID! < soundFont.samples.length
              ? soundFont.samples[zone.sampleID!]
              : null);

      if (sample == null || handledSampleIds.contains(sample.id)) continue;

      // Check if stereo joining applies
      if (options.joinStereoChannels &&
          StereoJoiner.isStereoCandidate(sample)) {
        final pairedSample = StereoJoiner.findLinkedSample(soundFont, sample);
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
            zone: zone,
            presetZone: presetZone,
            customVolume: customVolume,
            customPan: customPan,
            atTime: atTime,
            duration: duration,
          );

          allHandles.addAll(stereoVoice.handles);
          allSources.addAll(stereoVoice.sources);
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
        pan: customPan,
        atTime: atTime,
        duration: duration,
        zone: zone,
        presetZone: presetZone,
        trackVoice: false,
      );

      allHandles.addAll(voice.handles);
      allSources.addAll(voice.sources);
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
    double? customPan,
    Duration? atTime,
    Duration? duration,
  }) async {
    var matchingPresetZones =
        preset.zones.where((pz) => pz.matches(key, velocity)).toList();

    if (matchingPresetZones.isEmpty) {
      matchingPresetZones = preset.zones.take(1).toList();
    }

    if (matchingPresetZones.isEmpty) {
      return SoundFontVoice(key: key, velocity: velocity, handles: []);
    }

    final allHandles = <SoundHandle>[];
    final allSources = <AudioSource>[];
    Duration maxRelease = options.defaultReleaseDuration;

    for (final pz in matchingPresetZones) {
      final inst = (pz.instrumentID != null &&
              pz.instrumentID! < soundFont.instruments.length)
          ? soundFont.instruments[pz.instrumentID!]
          : null;

      if (inst != null) {
        final voice = await playInstrument(
          inst,
          key: key,
          velocity: velocity,
          customVolume: customVolume,
          customPan: customPan,
          atTime: atTime,
          duration: duration,
          presetZone: pz,
          trackVoice: false,
        );
        allHandles.addAll(voice.handles);
        allSources.addAll(voice.sources);
        if (voice.releaseDuration > maxRelease) {
          maxRelease = voice.releaseDuration;
        }
      } else if (pz.sampleRef != null || pz.sampleID != null) {
        final sample = pz.sampleRef ??
            (pz.sampleID != null && pz.sampleID! < soundFont.samples.length
                ? soundFont.samples[pz.sampleID!]
                : null);
        if (sample != null) {
          if (options.joinStereoChannels &&
              StereoJoiner.isStereoCandidate(sample)) {
            final pairedSample = StereoJoiner.findLinkedSample(soundFont, sample);
            if (pairedSample != null) {
              final leftSample = sample.isLeft ? sample : pairedSample;
              final rightSample = sample.isRight ? sample : pairedSample;

              final stereoVoice = await _playJoinedStereoPair(
                leftSample: leftSample,
                rightSample: rightSample,
                key: key,
                velocity: velocity,
                presetZone: pz,
                customVolume: customVolume,
                customPan: customPan,
                atTime: atTime,
                duration: duration,
              );

              allHandles.addAll(stereoVoice.handles);
              allSources.addAll(stereoVoice.sources);
              if (stereoVoice.releaseDuration > maxRelease) {
                maxRelease = stereoVoice.releaseDuration;
              }
              continue;
            }
          }

          final voice = await playSample(
            sample,
            key: key,
            velocity: velocity,
            volume: customVolume,
            pan: customPan,
            atTime: atTime,
            duration: duration,
            presetZone: pz,
            trackVoice: false,
          );
          allHandles.addAll(voice.handles);
          allSources.addAll(voice.sources);
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
    );

    _trackVoice(key, compoundVoice);
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
    double? customPan,
  }) =>
      playPreset(
        preset,
        key: key,
        velocity: velocity,
        customVolume: customVolume,
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
    double? customPan,
  }) =>
      playInstrument(
        instrument,
        key: key,
        velocity: velocity,
        customVolume: customVolume,
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
  }) =>
      playSample(
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
    final voices = _activeVoices.remove(key);
    if (voices == null || voices.isEmpty) return;

    for (final voice in voices) {
      await voice.release(customRelease: releaseDuration);
    }
  }

  /// Stops all active voices across all keys.
  Future<void> allNotesOff({Duration? releaseDuration}) async {
    final allKeys = _activeVoices.keys.toList();
    for (final key in allKeys) {
      await noteOff(key, releaseDuration: releaseDuration);
    }
    _activeVoices.clear();
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
    Uint8List? bytes = _sampleBytesCache[sample.id];
    if (bytes == null) {
      bytes = await soundFont.getSampleBytes(sample);
      if (bytes.isNotEmpty) {
        _sampleBytesCache[sample.id] = bytes;
      }
    }

    final cacheKey = 'sample_${sample.id}';
    if (createAudioSource &&
        options.cacheAudioSources &&
        !_audioSourceCache.containsKey(cacheKey) &&
        bytes.isNotEmpty) {
      final audio = SampleStreamer.streamSample(
        soundFont: soundFont,
        sample: sample,
        preloadedBytes: bytes,
        chunkSize: options.streamChunkSize,
        bufferingType: BufferingType.preserved,
        autoDispose: false,
      );
      _audioSourceCache[cacheKey] = audio;
    }
  }

  /// Preloads audio bytes and prepares the stereo [AudioSource] for a left-right sample pair.
  Future<void> preloadStereoPair(
    SampleInfo leftSample,
    SampleInfo rightSample, {
    bool createAudioSource = true,
  }) async {
    final stereoKey = '${leftSample.id}_${rightSample.id}';
    Uint8List? stereoBytes = _stereoBytesCache[stereoKey];

    if (stereoBytes == null) {
      final leftBytes = _sampleBytesCache[leftSample.id] ??
          await soundFont.getSampleBytes(leftSample);
      final rightBytes = _sampleBytesCache[rightSample.id] ??
          await soundFont.getSampleBytes(rightSample);

      if (leftBytes.isNotEmpty && rightBytes.isNotEmpty) {
        stereoBytes = StereoJoiner.interleavePcm16(
          leftBytes: leftBytes,
          rightBytes: rightBytes,
        );
        _stereoBytesCache[stereoKey] = stereoBytes;
      }
    }

    final cacheKey = 'stereo_$stereoKey';
    if (createAudioSource &&
        options.cacheAudioSources &&
        !_audioSourceCache.containsKey(cacheKey) &&
        stereoBytes != null &&
        stereoBytes.isNotEmpty) {
      final audio = SampleStreamer.streamStereoPcm(
        stereoPcmBytes: stereoBytes,
        sampleRate: leftSample.sampleRate,
        chunkSize: options.streamChunkSize,
        bufferingType: BufferingType.preserved,
        autoDispose: false,
      );
      _audioSourceCache[cacheKey] = audio;
    }
  }

  /// Preloads all samples needed for [instrument] with optional progress callback.
  Future<void> preloadInstrument(
    Instrument instrument, {
    void Function(double progress, int loaded, int total)? onProgress,
    bool createAudioSources = true,
  }) async {
    final samples = <SampleInfo>{};
    for (final zone in instrument.zones) {
      final sample = zone.sampleRef ??
          (zone.sampleID != null && zone.sampleID! < soundFont.samples.length
              ? soundFont.samples[zone.sampleID!]
              : null);
      if (sample != null) samples.add(sample);
    }

    int index = 0;
    final total = samples.length;
    for (final s in samples) {
      await preloadSample(s, createAudioSource: createAudioSources);
      index++;
      onProgress?.call(total > 0 ? index / total : 1.0, index, total);
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
      final inst = (pz.instrumentID != null &&
              pz.instrumentID! < soundFont.instruments.length)
          ? soundFont.instruments[pz.instrumentID!]
          : null;
      if (inst != null) {
        for (final iz in inst.zones) {
          final s = iz.sampleRef ??
              (iz.sampleID != null && iz.sampleID! < soundFont.samples.length
                  ? soundFont.samples[iz.sampleID!]
                  : null);
          if (s != null) samples.add(s);
        }
      }
      final s = pz.sampleRef ??
          (pz.sampleID != null && pz.sampleID! < soundFont.samples.length
              ? soundFont.samples[pz.sampleID!]
              : null);
      if (s != null) samples.add(s);
    }

    int index = 0;
    final total = samples.length;
    for (final s in samples) {
      await preloadSample(s, createAudioSource: createAudioSources);
      index++;
      onProgress?.call(total > 0 ? index / total : 1.0, index, total);
    }
  }

  /// Preloads all samples in the entire [soundFont] with optional progress callback.
  Future<void> preloadAll({
    void Function(double progress, int loaded, int total)? onProgress,
    bool createAudioSources = true,
  }) async {
    final total = soundFont.samples.length;
    for (int i = 0; i < total; i++) {
      final sample = soundFont.samples[i];
      await preloadSample(sample, createAudioSource: createAudioSources);
      onProgress?.call(total > 0 ? (i + 1) / total : 1.0, i + 1, total);
    }

    // Preload stereo pairs if enabled
    if (options.joinStereoChannels) {
      for (final sample in soundFont.samples) {
        if (sample.isLeft) {
          final right = StereoJoiner.findLinkedSample(soundFont, sample);
          if (right != null) {
            await preloadStereoPair(sample, right,
                createAudioSource: createAudioSources);
          }
        }
      }
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
    double? customPan,
    Duration? atTime,
    Duration? duration,
  }) async {
    final speed = VoiceCalculator.calculatePitchRatio(
      key: key,
      sample: leftSample,
      zone: zone,
      presetZone: presetZone,
    );

    final vol = customVolume ??
        VoiceCalculator.calculateVolume(
          velocity: velocity,
          zone: zone,
          presetZone: presetZone,
          masterVolume: options.masterVolume,
        );

    final p = customPan ??
        VoiceCalculator.calculatePan(
          presetZone: presetZone,
        );

    final loopInfo = VoiceCalculator.calculateLoopRegion(
      sample: leftSample,
      zone: zone,
    );

    final releaseDuration = VoiceCalculator.calculateReleaseDuration(
      zone: zone,
      presetZone: presetZone,
      defaultDuration: options.defaultReleaseDuration,
      sustainTime: _sustainTime,
      sustainMultiplier: _sustainMultiplier,
    );

    final stereoKey = '${leftSample.id}_${rightSample.id}';
    Uint8List? stereoBytes = _stereoBytesCache[stereoKey];

    if (stereoBytes == null) {
      final leftBytes = _sampleBytesCache[leftSample.id] ??
          await soundFont.getSampleBytes(leftSample);
      final rightBytes = _sampleBytesCache[rightSample.id] ??
          await soundFont.getSampleBytes(rightSample);

      stereoBytes = StereoJoiner.interleavePcm16(
        leftBytes: leftBytes,
        rightBytes: rightBytes,
      );
      _stereoBytesCache[stereoKey] = stereoBytes;
    }

    AudioSource audio;
    final cacheKey = 'stereo_$stereoKey';

    if (options.cacheAudioSources && _audioSourceCache.containsKey(cacheKey)) {
      audio = _audioSourceCache[cacheKey]!;
    } else {
      audio = SampleStreamer.streamStereoPcm(
        stereoPcmBytes: stereoBytes,
        sampleRate: leftSample.sampleRate,
        chunkSize: options.streamChunkSize,
        bufferingType: BufferingType.preserved,
        autoDispose: false,
      );

      if (options.cacheAudioSources) {
        _audioSourceCache[cacheKey] = audio;
      }
    }

    final validLoop = loopInfo.isLooping &&
        loopInfo.loopEnd != null &&
        loopInfo.loopEnd! > loopInfo.loopStart;
    final useScheduled = !validLoop &&
        (atTime != null || duration != null || options.useScheduledPlayback);

    SoundHandle handle;
    if (useScheduled) {
      final scheduledAt = atTime ??
          (SoLoud.instance.isInitialized
              ? SoLoud.instance.getEngineTime()
              : Duration.zero);

      final attackSec = zone?.volEnvAttack ?? presetZone?.volEnvAttack;
      final hasAttack = attackSec != null && attackSec > 0.005;

      handle = SoLoud.instance.playScheduled(
        audio,
        scheduledAt,
        duration: (duration != null && releaseDuration == Duration.zero)
            ? duration
            : null,
        volume: hasAttack ? 0.0 : vol,
        pan: p,
        busId: options.defaultBusId,
      );

      if (hasAttack) {
        final attackDuration =
            Duration(microseconds: (attackSec * 1000000).round());
        SoLoud.instance.fadeScheduled(
          handle,
          scheduledAt,
          vol,
          attackDuration,
        );
      }

      if (duration != null) {
        final noteOffTime = scheduledAt + duration;
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
    } else {
      handle = SoLoud.instance.play(
        audio,
        volume: vol,
        pan: p,
        looping: validLoop,
        loopingStartAt: validLoop ? loopInfo.loopStart : Duration.zero,
        loopingEndAt: validLoop ? loopInfo.loopEnd : null,
        busId: options.defaultBusId,
      );
    }

    if (speed != 1.0) {
      SoLoud.instance.setRelativePlaySpeed(handle, speed);
    }

    return SoundFontVoice(
      key: key,
      velocity: velocity,
      handles: [handle],
      sources: [audio],
      releaseDuration: releaseDuration,
      sampleId: leftSample.id,
    );
  }

  /// Returns all active sound handles playing the given [sample].
  List<SoundHandle> getActiveHandlesForSample(SampleInfo sample) {
    final result = <SoundHandle>[];
    final cachedSource = _audioSourceCache['sample_${sample.id}'];

    for (final voiceList in _activeVoices.values) {
      for (final voice in voiceList) {
        if (voice.isReleased) continue;
        final isMatch = voice.sampleId == sample.id ||
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
    _activeVoices.putIfAbsent(key, () => []).add(voice);
  }

  /// Releases all player resources and stops all playing handles.
  Future<void> dispose() async {
    await allNotesOff();
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
