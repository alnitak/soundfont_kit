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
  });

  /// Plays a single [SampleInfo] with optional pitch, volume, pan, and loop overrides.
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
    Zone? zone,
    Zone? presetZone,
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

      final bufferingType = options.cacheAudioSources
          ? BufferingType.preserved
          : BufferingType.released;

      audio = SampleStreamer.streamSample(
        soundFont: soundFont,
        sample: sample,
        preloadedBytes: preloaded,
        chunkSize: options.streamChunkSize,
        bufferingType: bufferingType,
        autoDispose: bufferingType == BufferingType.released,
      );

      if (options.cacheAudioSources) {
        _audioSourceCache[cacheKey] = audio;
      }
    }

    final handle = SoLoud.instance.play(
      audio,
      volume: vol,
      pan: p,
      looping: shouldLoop,
      loopingStartAt: loopStart,
      loopingEndAt: loopEnd,
      busId: options.defaultBusId,
    );

    if (speed != 1.0) {
      SoLoud.instance.setRelativePlaySpeed(handle, speed);
    }

    final voice = SoundFontVoice(
      key: key,
      velocity: velocity,
      handles: [handle],
      sources: [audio],
      releaseDuration: releaseDuration,
    );

    _trackVoice(key, voice);
    return voice;
  }

  /// Plays an [Instrument] for a given MIDI [key] and [velocity].
  Future<SoundFontVoice> playInstrument(
    Instrument instrument, {
    int key = 60,
    int velocity = 100,
    double? customVolume,
    double? customPan,
    Zone? presetZone,
  }) async {
    // Find matching zones for this key and velocity
    var matchingZones = instrument.zones
        .where((z) => z.matches(key, velocity) && (z.sampleRef != null || z.sampleID != null))
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
      if (options.joinStereoChannels && StereoJoiner.isStereoCandidate(sample)) {
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
        zone: zone,
        presetZone: presetZone,
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

    _trackVoice(key, compoundVoice);
    return compoundVoice;
  }

  /// Plays a [Preset] for a given MIDI [key] and [velocity].
  Future<SoundFontVoice> playPreset(
    Preset preset, {
    int key = 60,
    int velocity = 100,
    double? customVolume,
    double? customPan,
  }) async {
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
          presetZone: pz,
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
          final voice = await playSample(
            sample,
            key: key,
            velocity: velocity,
            volume: customVolume,
            pan: customPan,
            presetZone: pz,
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

  /// Note-on trigger: plays specified [preset], [instrument], or default bank/instrument.
  Future<SoundFontVoice> noteOn(
    int key, {
    int velocity = 100,
    Instrument? instrument,
    Preset? preset,
    double? customVolume,
    double? customPan,
  }) async {
    if (preset != null) {
      return playPreset(
        preset,
        key: key,
        velocity: velocity,
        customVolume: customVolume,
        customPan: customPan,
      );
    }

    if (instrument != null) {
      return playInstrument(
        instrument,
        key: key,
        velocity: velocity,
        customVolume: customVolume,
        customPan: customPan,
      );
    }

    if (soundFont.presets.isNotEmpty) {
      return playPreset(
        soundFont.presets.first,
        key: key,
        velocity: velocity,
        customVolume: customVolume,
        customPan: customPan,
      );
    }

    if (soundFont.instruments.isNotEmpty) {
      return playInstrument(
        soundFont.instruments.first,
        key: key,
        velocity: velocity,
        customVolume: customVolume,
        customPan: customPan,
      );
    }

    if (soundFont.samples.isNotEmpty) {
      return playSample(
        soundFont.samples.first,
        key: key,
        velocity: velocity,
        volume: customVolume,
        pan: customPan,
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

  /// Preloads audio bytes for [sample] into cache.
  Future<void> preloadSample(SampleInfo sample) async {
    if (_sampleBytesCache.containsKey(sample.id)) return;
    final bytes = await soundFont.getSampleBytes(sample);
    if (bytes.isNotEmpty) {
      _sampleBytesCache[sample.id] = bytes;
    }
  }

  /// Preloads all samples needed for [instrument].
  Future<void> preloadInstrument(Instrument instrument) async {
    for (final zone in instrument.zones) {
      final sample = zone.sampleRef ??
          (zone.sampleID != null && zone.sampleID! < soundFont.samples.length
              ? soundFont.samples[zone.sampleID!]
              : null);
      if (sample != null) {
        await preloadSample(sample);
      }
    }
  }

  /// Preloads all samples needed for [preset].
  Future<void> preloadPreset(Preset preset) async {
    for (final pz in preset.zones) {
      final inst = (pz.instrumentID != null &&
              pz.instrumentID! < soundFont.instruments.length)
          ? soundFont.instruments[pz.instrumentID!]
          : null;
      if (inst != null) {
        await preloadInstrument(inst);
      }
      final sample = pz.sampleRef ??
          (pz.sampleID != null && pz.sampleID! < soundFont.samples.length
              ? soundFont.samples[pz.sampleID!]
              : null);
      if (sample != null) {
        await preloadSample(sample);
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
          zone: zone,
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
      final bufferingType = options.cacheAudioSources
          ? BufferingType.preserved
          : BufferingType.released;

      audio = SampleStreamer.streamStereoPcm(
        stereoPcmBytes: stereoBytes,
        sampleRate: leftSample.sampleRate,
        chunkSize: options.streamChunkSize,
        bufferingType: bufferingType,
        autoDispose: bufferingType == BufferingType.released,
      );

      if (options.cacheAudioSources) {
        _audioSourceCache[cacheKey] = audio;
      }
    }

    final handle = SoLoud.instance.play(
      audio,
      volume: vol,
      pan: p,
      looping: loopInfo.isLooping,
      loopingStartAt: loopInfo.loopStart,
      loopingEndAt: loopInfo.loopEnd,
      busId: options.defaultBusId,
    );

    if (speed != 1.0) {
      SoLoud.instance.setRelativePlaySpeed(handle, speed);
    }

    return SoundFontVoice(
      key: key,
      velocity: velocity,
      handles: [handle],
      sources: [audio],
      releaseDuration: releaseDuration,
    );
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
