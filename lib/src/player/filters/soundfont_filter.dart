// ignore_for_file: experimental_member_use

import 'package:flutter_soloud/flutter_soloud.dart';

/// Available audio filter types for SoundFont playback (Master or Per-Bus).
enum SoundFontFilterType {
  /// Algorithmic room and hall reverberation (Freeverb).
  freeverb(
    'Reverb (Freeverb)',
    'Spatial room acoustics and concert hall resonance',
  ),

  /// Stereo echo delay with feedback and tone damping.
  echo('Echo / Delay', 'Stereo echo repeats and feedback delay'),

  /// Low-pass, high-pass, and band-pass biquad resonant filter.
  biquad('Biquad Filter', 'Lowpass, highpass, and bandpass resonant filter'),

  /// Modulated delay-line flanger and chorus effect.
  flanger('Flanger / Chorus', 'Modulated pitch shimmering and stereo width'),

  /// Low-frequency bass boost enhancer.
  bassBoost('Bass Boost', 'Low-frequency enhancement and punch'),

  /// Bit-crushing and sample-rate reduction effect.
  lofi('Lo-Fi', 'Bit-crushing and vintage sampler rate reduction'),

  /// Non-linear waveshaping distortion and harmonic saturation.
  waveShaper('Wave Shaper', 'Harmonic saturation and distortion'),

  /// Dynamic range compressor with threshold, ratio, makeup gain, attack, and release.
  compressor(
    'Compressor',
    'Dynamic range compression with threshold, ratio, attack, and release',
  ),

  /// Brickwall peak limiter and output ceiling protector.
  limiter(
    'Limiter',
    'Brickwall peak limiting and output ceiling protection',
  ),

  /// Multi-band Gaussian parametric equalizer.
  parametricEq(
    'Parametric EQ',
    'Multi-band Gaussian parametric equalizer (Low, Mid, High)',
  ),

  /// Real-time pitch shifter in semitones without altering tempo.
  pitchShift(
    'Pitch Shift',
    'Real-time pitch shifting in semitones without altering tempo',
  ),

  /// Bipolar sine carrier ring and amplitude modulator.
  amplitudeModulator(
    'Ring / Amp Modulator',
    'Bipolar sine carrier amplitude modulation and vibrato/tremolo',
  ),

  /// Custom DSP or desktop VST3 effect insert slot 1 (`0`).
  customSlot0(
    'Custom DSP / VST3 Slot 1',
    'User-programmable native/Web DSP callback or desktop VST3 effect insert #1',
  ),

  /// Custom DSP or desktop VST3 effect insert slot 2 (`1`).
  customSlot1(
    'Custom DSP / VST3 Slot 2',
    'User-programmable native/Web DSP callback or desktop VST3 effect insert #2',
  ),

  /// Custom DSP or desktop VST3 effect insert slot 3 (`2`).
  customSlot2(
    'Custom DSP / VST3 Slot 3',
    'User-programmable native/Web DSP callback or desktop VST3 effect insert #3',
  ),

  /// Custom DSP or desktop VST3 effect insert slot 4 (`3`).
  customSlot3(
    'Custom DSP / VST3 Slot 4',
    'User-programmable native/Web DSP callback or desktop VST3 effect insert #4',
  ),

  /// Custom DSP or desktop VST3 effect insert slot 5 (`4`).
  customSlot4(
    'Custom DSP / VST3 Slot 5',
    'User-programmable native/Web DSP callback or desktop VST3 effect insert #5',
  ),

  /// Custom DSP or desktop VST3 effect insert slot 6 (`5`).
  customSlot5(
    'Custom DSP / VST3 Slot 6',
    'User-programmable native/Web DSP callback or desktop VST3 effect insert #6',
  ),

  /// Custom DSP or desktop VST3 effect insert slot 7 (`6`).
  customSlot6(
    'Custom DSP / VST3 Slot 7',
    'User-programmable native/Web DSP callback or desktop VST3 effect insert #7',
  ),

  /// Custom DSP or desktop VST3 effect insert slot 8 (`7`).
  customSlot7(
    'Custom DSP / VST3 Slot 8',
    'User-programmable native/Web DSP callback or desktop VST3 effect insert #8',
  );

  /// Short human-readable display title of the filter.
  final String label;

  /// Summary description of the filter's acoustic effect.
  final String description;

  const SoundFontFilterType(this.label, this.description);

  /// Whether this filter type represents one of the 8 custom DSP / VST3 slots.
  bool get isCustomSlot => customSlotIndex != null;

  /// Returns `0..7` if this filter is a custom DSP / VST3 slot, or `null` otherwise.
  int? get customSlotIndex => switch (this) {
    SoundFontFilterType.customSlot0 => 0,
    SoundFontFilterType.customSlot1 => 1,
    SoundFontFilterType.customSlot2 => 2,
    SoundFontFilterType.customSlot3 => 3,
    SoundFontFilterType.customSlot4 => 4,
    SoundFontFilterType.customSlot5 => 5,
    SoundFontFilterType.customSlot6 => 6,
    SoundFontFilterType.customSlot7 => 7,
    _ => null,
  };

  /// Returns the [SoundFontFilterType] for a custom slot index (`0..7`).
  static SoundFontFilterType fromCustomSlotIndex(int slotIndex) {
    return switch (slotIndex) {
      0 => SoundFontFilterType.customSlot0,
      1 => SoundFontFilterType.customSlot1,
      2 => SoundFontFilterType.customSlot2,
      3 => SoundFontFilterType.customSlot3,
      4 => SoundFontFilterType.customSlot4,
      5 => SoundFontFilterType.customSlot5,
      6 => SoundFontFilterType.customSlot6,
      7 => SoundFontFilterType.customSlot7,
      _ => throw RangeError.range(slotIndex, 0, 7, 'slotIndex'),
    };
  }
}

/// Metadata description and live control callbacks for a single adjustable filter parameter.
class FilterParameterInfo {
  /// Stable machine-readable parameter identifier (e.g., `'wet'`, `'room_size'`).
  final String id;

  /// Human-readable display label for the parameter.
  final String name;

  /// Minimum allowed parameter value.
  final double min;

  /// Maximum allowed parameter value.
  final double max;

  /// Default initial parameter value.
  final double defaultValue;

  /// Optional display unit suffix (e.g., `'Hz'`, `'dB'`, `'ms'`, `'%'`).
  final String unit;

  /// Callback returning the current live value of this parameter.
  final double Function() getValue;

  /// Callback setting the live value of this parameter.
  final void Function(double val) onSetValue;

  /// Optional callback that smoothly fades this parameter to `to` over `duration`.
  final void Function(double to, Duration duration)? onFade;

  /// Optional callback that continuously oscillates this parameter between `from` and `to` with LFO `period`.
  final void Function(double from, double to, Duration period)? onOscillate;

  /// Creates a [FilterParameterInfo] descriptor.
  const FilterParameterInfo({
    required this.id,
    required this.name,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.unit = '',
    required this.getValue,
    required this.onSetValue,
    this.onFade,
    this.onOscillate,
  });

  /// Creates a [FilterParameterInfo] bound to a lazy SoLoud filter parameter resolver [resolveParam].
  factory FilterParameterInfo.fromParam({
    required String id,
    required String name,
    required double min,
    required double max,
    required double defaultValue,
    String unit = '',
    required dynamic Function() resolveParam,
  }) {
    return FilterParameterInfo(
      id: id,
      name: name,
      min: min,
      max: max,
      defaultValue: defaultValue,
      unit: unit,
      getValue: () {
        try {
          return (resolveParam().value as num).toDouble();
        } catch (_) {
          return defaultValue;
        }
      },
      onSetValue: (v) {
        try {
          resolveParam().value = v;
        } catch (_) {}
      },
      onFade: (to, duration) {
        try {
          resolveParam().fadeFilterParameter(
            to: to.clamp(min, max),
            time: duration,
          );
        } catch (_) {}
      },
      onOscillate: (from, to, period) {
        try {
          resolveParam().oscillateFilterParameter(
            from: from.clamp(min, max),
            to: to.clamp(min, max),
            time: period,
          );
        } catch (_) {}
      },
    );
  }

  /// Current live value of this filter parameter.
  double get currentValue => getValue();

  /// Updates this filter parameter to [val], clamped to `[min, max]`.
  void setValue(double val) {
    onSetValue(val.clamp(min, max));
  }

  /// Smoothly ramps this parameter to [to] over [duration] using SoLoud's C++ fader.
  void fadeTo(double to, Duration duration) {
    if (onFade != null) {
      onFade!(to.clamp(min, max), duration);
    } else {
      setValue(to);
    }
  }

  /// Continuously modulates this parameter between [from] and [to] with [period]
  /// using SoLoud's C++ LFO oscillator.
  void oscillate({
    required double from,
    required double to,
    required Duration period,
  }) {
    onOscillate?.call(from.clamp(min, max), to.clamp(min, max), period);
  }
}

/// Alias for [SoundFontGlobalFilters] representing either a global master filter
/// rack or a per-channel / per-player mixing [Bus] filter rack.
typedef SoundFontFilterRack = SoundFontGlobalFilters;

/// Controller managing SoLoud audio filters (either globally on the Master
/// output or scoped to a specific mixing [Bus]).
class SoundFontGlobalFilters {
  /// Optional mixing [Bus] when this filter rack is scoped to a specific channel
  /// or player bus. When `null`, controls `SoLoud.instance.filters` globally.
  final Bus? bus;

  /// Creates a global Master output filter controller.
  const SoundFontGlobalFilters() : bus = null;

  /// Creates a global Master output filter controller.
  const SoundFontGlobalFilters.global() : bus = null;

  /// Creates a filter controller scoped to a specific mixing [bus].
  const SoundFontGlobalFilters.forBus(Bus this.bus);

  /// Whether this filter rack targets a mixing [Bus] rather than the global output.
  bool get isBusScoped => bus != null;

  dynamic _resolveFilterBase(SoundFontFilterType type) {
    final b = bus;
    if (b != null) {
      final f = b.filters;
      final slot = type.customSlotIndex;
      if (slot != null) return f.customFilter(slot);
      return switch (type) {
        SoundFontFilterType.freeverb => f.freeverbFilter,
        SoundFontFilterType.echo => f.echoFilter,
        SoundFontFilterType.biquad => f.biquadFilter,
        SoundFontFilterType.flanger => f.flangerFilter,
        SoundFontFilterType.bassBoost => f.bassBoostFilter,
        SoundFontFilterType.lofi => f.lofiFilter,
        SoundFontFilterType.waveShaper => f.waveShaperFilter,
        SoundFontFilterType.compressor => f.compressorFilter,
        SoundFontFilterType.limiter => f.limiterFilter,
        SoundFontFilterType.parametricEq => f.parametricEqFilter,
        SoundFontFilterType.pitchShift => f.pitchShiftFilter,
        SoundFontFilterType.amplitudeModulator => f.amplitudeModulatorFilter,
        _ => f.customFilter(0),
      };
    }

    final f = SoLoud.instance.filters;
    final slot = type.customSlotIndex;
    if (slot != null) return f.customFilter(slot);
    return switch (type) {
      SoundFontFilterType.freeverb => f.freeverbFilter,
      SoundFontFilterType.echo => f.echoFilter,
      SoundFontFilterType.biquad => f.biquadResonantFilter,
      SoundFontFilterType.flanger => f.flangerFilter,
      SoundFontFilterType.bassBoost => f.bassBoostFilter,
      SoundFontFilterType.lofi => f.lofiFilter,
      SoundFontFilterType.waveShaper => f.waveShaperFilter,
      SoundFontFilterType.compressor => f.compressorFilter,
      SoundFontFilterType.limiter => f.limiterFilter,
      SoundFontFilterType.parametricEq => f.parametricEqFilter,
      SoundFontFilterType.pitchShift => f.pitchShiftFilter,
      SoundFontFilterType.amplitudeModulator => f.amplitudeModulatorFilter,
      _ => f.customFilter(0),
    };
  }

  /// Accesses one of the 8 user-programmable [CustomFilterSlot]s (`0..7`) on
  /// this filter rack (either Master or [bus]).
  CustomFilterSlot customSlot(int slotIndex) {
    final b = bus;
    if (b != null) {
      return b.filters.customFilter(slotIndex);
    }
    return SoLoud.instance.filters.customFilter(slotIndex);
  }

  /// All 8 [CustomFilterSlot]s (`0..7`) on this filter rack.
  List<CustomFilterSlot> get customSlots {
    final b = bus;
    if (b != null) {
      return b.filters.customFilters;
    }
    return SoLoud.instance.filters.customFilters;
  }

  /// Checks whether a specific filter is currently active on this scope.
  bool isActive(SoundFontFilterType type) {
    if (!SoLoud.instance.isInitialized) return false;
    if (bus != null && !bus!.isActive) return false;
    try {
      return _resolveFilterBase(type).isActive as bool;
    } catch (_) {
      return false;
    }
  }

  /// Toggles activation of a filter safely by verifying current active state.
  void toggle(SoundFontFilterType type, bool active) {
    if (!SoLoud.instance.isInitialized) return;
    if (bus != null && !bus!.isActive) return;
    final isCurrentlyActive = isActive(type);
    if (active == isCurrentlyActive) return;

    try {
      final filter = _resolveFilterBase(type);
      if (active) {
        filter.activate();
      } else {
        filter.deactivate();
      }
    } catch (_) {}
  }

  /// Deactivates all active filters on this scope.
  void deactivateAll() {
    if (!SoLoud.instance.isInitialized) return;
    for (final type in SoundFontFilterType.values) {
      if (isActive(type)) {
        toggle(type, false);
      }
    }
  }

  /// Smoothly fades a filter parameter identified by [paramId] to [to] over [duration].
  void fadeParameter(
    SoundFontFilterType type,
    String paramId, {
    required double to,
    required Duration duration,
  }) {
    final params = getParameters(type);
    for (final p in params) {
      if (p.id == paramId) {
        p.fadeTo(to, duration);
        return;
      }
    }
  }

  /// Oscillates a filter parameter identified by [paramId] between [from] and [to]
  /// with LFO [period].
  void oscillateParameter(
    SoundFontFilterType type,
    String paramId, {
    required double from,
    required double to,
    required Duration period,
  }) {
    final params = getParameters(type);
    for (final p in params) {
      if (p.id == paramId) {
        p.oscillate(from: from, to: to, period: period);
        return;
      }
    }
  }

  /// Retrieves parameter metadata and control callbacks for a specific filter.
  List<FilterParameterInfo> getParameters(SoundFontFilterType type) {
    if (!SoLoud.instance.isInitialized) return const [];
    final b = bus;
    final g = SoLoud.instance.filters;

    final slotIdx = type.customSlotIndex;
    if (slotIdx != null) {
      return [
        FilterParameterInfo.fromParam(
          id: 'wet',
          name: 'Wet Level',
          min: 0.0,
          max: 1.0,
          defaultValue: 1.0,
          unit: '%',
          resolveParam: () => b != null
              ? b.filters.customFilter(slotIdx).wet()
              : g.customFilter(slotIdx).wet,
        ),
        for (var pIdx = 1; pIdx <= CustomFilterSlot.maxUserParams; pIdx++)
          FilterParameterInfo.fromParam(
            id: 'param_$pIdx',
            name: 'Param $pIdx',
            min: 0.0,
            max: 1.0,
            defaultValue: 0.0,
            unit: '',
            resolveParam: () => b != null
                ? b.filters.customFilter(slotIdx).param(pIdx, min: 0.0, max: 1.0)
                : g.customFilter(slotIdx).param(pIdx, min: 0.0, max: 1.0),
          ),
      ];
    }

    return switch (type) {
      SoundFontFilterType.freeverb => [
        FilterParameterInfo.fromParam(
          id: 'room_size',
          name: 'Room Size',
          min: g.freeverbFilter.queryRoomSize.min,
          max: g.freeverbFilter.queryRoomSize.max,
          defaultValue: g.freeverbFilter.queryRoomSize.def,
          unit: '%',
          resolveParam: () =>
              b != null ? b.filters.freeverbFilter.roomSize() : g.freeverbFilter.roomSize,
        ),
        FilterParameterInfo.fromParam(
          id: 'damp',
          name: 'Dampening',
          min: g.freeverbFilter.queryDamp.min,
          max: g.freeverbFilter.queryDamp.max,
          defaultValue: g.freeverbFilter.queryDamp.def,
          unit: '%',
          resolveParam: () =>
              b != null ? b.filters.freeverbFilter.damp() : g.freeverbFilter.damp,
        ),
        FilterParameterInfo.fromParam(
          id: 'width',
          name: 'Width',
          min: g.freeverbFilter.queryWidth.min,
          max: g.freeverbFilter.queryWidth.max,
          defaultValue: g.freeverbFilter.queryWidth.def,
          unit: '%',
          resolveParam: () =>
              b != null ? b.filters.freeverbFilter.width() : g.freeverbFilter.width,
        ),
        FilterParameterInfo.fromParam(
          id: 'wet',
          name: 'Wet Level',
          min: g.freeverbFilter.queryWet.min,
          max: g.freeverbFilter.queryWet.max,
          defaultValue: g.freeverbFilter.queryWet.def,
          unit: '%',
          resolveParam: () =>
              b != null ? b.filters.freeverbFilter.wet() : g.freeverbFilter.wet,
        ),
      ],
      SoundFontFilterType.echo => [
        FilterParameterInfo.fromParam(
          id: 'delay',
          name: 'Delay Time',
          min: g.echoFilter.queryDelay.min,
          max: g.echoFilter.queryDelay.max <= 10.0
              ? g.echoFilter.queryDelay.max
              : 3.0,
          defaultValue: g.echoFilter.queryDelay.def,
          unit: 's',
          resolveParam: () =>
              b != null ? b.filters.echoFilter.delay() : g.echoFilter.delay,
        ),
        FilterParameterInfo.fromParam(
          id: 'decay',
          name: 'Feedback',
          min: g.echoFilter.queryDecay.min,
          max: g.echoFilter.queryDecay.max,
          defaultValue: g.echoFilter.queryDecay.def,
          unit: '%',
          resolveParam: () =>
              b != null ? b.filters.echoFilter.decay() : g.echoFilter.decay,
        ),
        FilterParameterInfo.fromParam(
          id: 'filter',
          name: 'Tone Damping',
          min: g.echoFilter.queryFilter.min,
          max: g.echoFilter.queryFilter.max,
          defaultValue: g.echoFilter.queryFilter.def,
          unit: '%',
          resolveParam: () =>
              b != null ? b.filters.echoFilter.filter() : g.echoFilter.filter,
        ),
        FilterParameterInfo.fromParam(
          id: 'wet',
          name: 'Wet Level',
          min: g.echoFilter.queryWet.min,
          max: g.echoFilter.queryWet.max,
          defaultValue: g.echoFilter.queryWet.def,
          unit: '%',
          resolveParam: () =>
              b != null ? b.filters.echoFilter.wet() : g.echoFilter.wet,
        ),
      ],
      SoundFontFilterType.biquad => [
        FilterParameterInfo.fromParam(
          id: 'frequency',
          name: 'Cutoff',
          min: g.biquadResonantFilter.queryFrequency.min,
          max: g.biquadResonantFilter.queryFrequency.max,
          defaultValue: g.biquadResonantFilter.queryFrequency.def,
          unit: 'Hz',
          resolveParam: () => b != null
              ? b.filters.biquadFilter.frequency()
              : g.biquadResonantFilter.frequency,
        ),
        FilterParameterInfo.fromParam(
          id: 'resonance',
          name: 'Resonance',
          min: g.biquadResonantFilter.queryResonance.min,
          max: g.biquadResonantFilter.queryResonance.max,
          defaultValue: g.biquadResonantFilter.queryResonance.def,
          unit: 'Q',
          resolveParam: () => b != null
              ? b.filters.biquadFilter.resonance()
              : g.biquadResonantFilter.resonance,
        ),
        FilterParameterInfo.fromParam(
          id: 'wet',
          name: 'Wet Level',
          min: g.biquadResonantFilter.queryWet.min,
          max: g.biquadResonantFilter.queryWet.max,
          defaultValue: g.biquadResonantFilter.queryWet.def,
          unit: '%',
          resolveParam: () => b != null
              ? b.filters.biquadFilter.wet()
              : g.biquadResonantFilter.wet,
        ),
      ],
      SoundFontFilterType.flanger => [
        FilterParameterInfo.fromParam(
          id: 'delay',
          name: 'Delay Time',
          min: g.flangerFilter.queryDelay.min,
          max: g.flangerFilter.queryDelay.max,
          defaultValue: g.flangerFilter.queryDelay.def,
          unit: 's',
          resolveParam: () =>
              b != null ? b.filters.flangerFilter.delay() : g.flangerFilter.delay,
        ),
        FilterParameterInfo.fromParam(
          id: 'freq',
          name: 'LFO Freq',
          min: g.flangerFilter.queryFreq.min,
          max: g.flangerFilter.queryFreq.max,
          defaultValue: g.flangerFilter.queryFreq.def,
          unit: 'Hz',
          resolveParam: () =>
              b != null ? b.filters.flangerFilter.freq() : g.flangerFilter.freq,
        ),
        FilterParameterInfo.fromParam(
          id: 'wet',
          name: 'Wet Level',
          min: g.flangerFilter.queryWet.min,
          max: g.flangerFilter.queryWet.max,
          defaultValue: g.flangerFilter.queryWet.def,
          unit: '%',
          resolveParam: () =>
              b != null ? b.filters.flangerFilter.wet() : g.flangerFilter.wet,
        ),
      ],
      SoundFontFilterType.bassBoost => [
        FilterParameterInfo.fromParam(
          id: 'boost',
          name: 'Bass Boost',
          min: g.bassBoostFilter.queryBoost.min,
          max: g.bassBoostFilter.queryBoost.max,
          defaultValue: g.bassBoostFilter.queryBoost.def,
          unit: 'x',
          resolveParam: () => b != null
              ? b.filters.bassBoostFilter.boost()
              : g.bassBoostFilter.boost,
        ),
        FilterParameterInfo.fromParam(
          id: 'wet',
          name: 'Wet Level',
          min: g.bassBoostFilter.queryWet.min,
          max: g.bassBoostFilter.queryWet.max,
          defaultValue: g.bassBoostFilter.queryWet.def,
          unit: '%',
          resolveParam: () =>
              b != null ? b.filters.bassBoostFilter.wet() : g.bassBoostFilter.wet,
        ),
      ],
      SoundFontFilterType.lofi => [
        FilterParameterInfo.fromParam(
          id: 'samplerate',
          name: 'Sample Rate',
          min: g.lofiFilter.querySamplerate.min,
          max: g.lofiFilter.querySamplerate.max,
          defaultValue: g.lofiFilter.querySamplerate.def,
          unit: 'Hz',
          resolveParam: () => b != null
              ? b.filters.lofiFilter.samplerate()
              : g.lofiFilter.samplerate,
        ),
        FilterParameterInfo.fromParam(
          id: 'bitdepth',
          name: 'Bit Depth',
          min: g.lofiFilter.queryBitdepth.min,
          max: g.lofiFilter.queryBitdepth.max,
          defaultValue: g.lofiFilter.queryBitdepth.def,
          unit: 'bits',
          resolveParam: () => b != null
              ? b.filters.lofiFilter.bitdepth()
              : g.lofiFilter.bitdepth,
        ),
        FilterParameterInfo.fromParam(
          id: 'wet',
          name: 'Wet Level',
          min: g.lofiFilter.queryWet.min,
          max: g.lofiFilter.queryWet.max,
          defaultValue: g.lofiFilter.queryWet.def,
          unit: '%',
          resolveParam: () =>
              b != null ? b.filters.lofiFilter.wet() : g.lofiFilter.wet,
        ),
      ],
      SoundFontFilterType.waveShaper => [
        FilterParameterInfo.fromParam(
          id: 'amount',
          name: 'Drive',
          min: g.waveShaperFilter.queryAmount.min,
          max: g.waveShaperFilter.queryAmount.max,
          defaultValue: g.waveShaperFilter.queryAmount.def,
          unit: '',
          resolveParam: () => b != null
              ? b.filters.waveShaperFilter.amount()
              : g.waveShaperFilter.amount,
        ),
        FilterParameterInfo.fromParam(
          id: 'wet',
          name: 'Wet Level',
          min: g.waveShaperFilter.queryWet.min,
          max: g.waveShaperFilter.queryWet.max,
          defaultValue: g.waveShaperFilter.queryWet.def,
          unit: '%',
          resolveParam: () => b != null
              ? b.filters.waveShaperFilter.wet()
              : g.waveShaperFilter.wet,
        ),
      ],
      SoundFontFilterType.compressor => [
        FilterParameterInfo.fromParam(
          id: 'threshold',
          name: 'Threshold',
          min: g.compressorFilter.queryThreshold.min,
          max: g.compressorFilter.queryThreshold.max,
          defaultValue: g.compressorFilter.queryThreshold.def,
          unit: 'dB',
          resolveParam: () => b != null
              ? b.filters.compressorFilter.threshold()
              : g.compressorFilter.threshold,
        ),
        FilterParameterInfo.fromParam(
          id: 'ratio',
          name: 'Ratio',
          min: g.compressorFilter.queryRatio.min,
          max: g.compressorFilter.queryRatio.max,
          defaultValue: g.compressorFilter.queryRatio.def,
          unit: ':1',
          resolveParam: () => b != null
              ? b.filters.compressorFilter.ratio()
              : g.compressorFilter.ratio,
        ),
        FilterParameterInfo.fromParam(
          id: 'makeup_gain',
          name: 'Makeup Gain',
          min: g.compressorFilter.queryMakeupGain.min,
          max: g.compressorFilter.queryMakeupGain.max,
          defaultValue: g.compressorFilter.queryMakeupGain.def,
          unit: 'dB',
          resolveParam: () => b != null
              ? b.filters.compressorFilter.makeupGain()
              : g.compressorFilter.makeupGain,
        ),
        FilterParameterInfo.fromParam(
          id: 'attack',
          name: 'Attack Time',
          min: g.compressorFilter.queryAttackTime.min,
          max: g.compressorFilter.queryAttackTime.max,
          defaultValue: g.compressorFilter.queryAttackTime.def,
          unit: 'ms',
          resolveParam: () => b != null
              ? b.filters.compressorFilter.attackTime()
              : g.compressorFilter.attackTime,
        ),
        FilterParameterInfo.fromParam(
          id: 'release',
          name: 'Release Time',
          min: g.compressorFilter.queryReleaseTime.min,
          max: g.compressorFilter.queryReleaseTime.max,
          defaultValue: g.compressorFilter.queryReleaseTime.def,
          unit: 'ms',
          resolveParam: () => b != null
              ? b.filters.compressorFilter.releaseTime()
              : g.compressorFilter.releaseTime,
        ),
        FilterParameterInfo.fromParam(
          id: 'wet',
          name: 'Wet Level',
          min: g.compressorFilter.queryWet.min,
          max: g.compressorFilter.queryWet.max,
          defaultValue: g.compressorFilter.queryWet.def,
          unit: '%',
          resolveParam: () => b != null
              ? b.filters.compressorFilter.wet()
              : g.compressorFilter.wet,
        ),
      ],
      SoundFontFilterType.limiter => [
        FilterParameterInfo.fromParam(
          id: 'threshold',
          name: 'Threshold',
          min: g.limiterFilter.queryThreshold.min,
          max: g.limiterFilter.queryThreshold.max,
          defaultValue: g.limiterFilter.queryThreshold.def,
          unit: 'dB',
          resolveParam: () => b != null
              ? b.filters.limiterFilter.threshold()
              : g.limiterFilter.threshold,
        ),
        FilterParameterInfo.fromParam(
          id: 'ceiling',
          name: 'Output Ceiling',
          min: g.limiterFilter.queryOutputCeiling.min,
          max: g.limiterFilter.queryOutputCeiling.max,
          defaultValue: g.limiterFilter.queryOutputCeiling.def,
          unit: 'dB',
          resolveParam: () => b != null
              ? b.filters.limiterFilter.outputCeiling()
              : g.limiterFilter.outputCeiling,
        ),
        FilterParameterInfo.fromParam(
          id: 'release',
          name: 'Release Time',
          min: g.limiterFilter.queryReleaseTime.min,
          max: g.limiterFilter.queryReleaseTime.max,
          defaultValue: g.limiterFilter.queryReleaseTime.def,
          unit: 'ms',
          resolveParam: () => b != null
              ? b.filters.limiterFilter.releaseTime()
              : g.limiterFilter.releaseTime,
        ),
        FilterParameterInfo.fromParam(
          id: 'wet',
          name: 'Wet Level',
          min: g.limiterFilter.queryWet.min,
          max: g.limiterFilter.queryWet.max,
          defaultValue: g.limiterFilter.queryWet.def,
          unit: '%',
          resolveParam: () =>
              b != null ? b.filters.limiterFilter.wet() : g.limiterFilter.wet,
        ),
      ],
      SoundFontFilterType.parametricEq => [
        FilterParameterInfo.fromParam(
          id: 'band_0_gain',
          name: 'Low Gain (30 Hz)',
          min: 0.0,
          max: 4.0,
          defaultValue: 1.0,
          unit: 'x',
          resolveParam: () => b != null
              ? b.filters.parametricEqFilter.bandGain(0)
              : g.parametricEqFilter.bandGain(0),
        ),
        FilterParameterInfo.fromParam(
          id: 'band_1_gain',
          name: 'Mid Gain (600 Hz)',
          min: 0.0,
          max: 4.0,
          defaultValue: 1.0,
          unit: 'x',
          resolveParam: () => b != null
              ? b.filters.parametricEqFilter.bandGain(1)
              : g.parametricEqFilter.bandGain(1),
        ),
        FilterParameterInfo.fromParam(
          id: 'band_2_gain',
          name: 'High Gain (12 kHz)',
          min: 0.0,
          max: 4.0,
          defaultValue: 1.0,
          unit: 'x',
          resolveParam: () => b != null
              ? b.filters.parametricEqFilter.bandGain(2)
              : g.parametricEqFilter.bandGain(2),
        ),
        FilterParameterInfo.fromParam(
          id: 'wet',
          name: 'Wet Level',
          min: 0.0,
          max: 1.0,
          defaultValue: 1.0,
          unit: '%',
          resolveParam: () => b != null
              ? b.filters.parametricEqFilter.wet()
              : g.parametricEqFilter.wet,
        ),
      ],
      SoundFontFilterType.pitchShift => [
        FilterParameterInfo.fromParam(
          id: 'semitones',
          name: 'Semitones',
          min: g.pitchShiftFilter.querySemitones.min,
          max: g.pitchShiftFilter.querySemitones.max,
          defaultValue: g.pitchShiftFilter.querySemitones.def,
          unit: 'st',
          resolveParam: () => b != null
              ? b.filters.pitchShiftFilter.semitones()
              : g.pitchShiftFilter.semitones,
        ),
        FilterParameterInfo.fromParam(
          id: 'wet',
          name: 'Wet Level',
          min: g.pitchShiftFilter.queryWet.min,
          max: g.pitchShiftFilter.queryWet.max,
          defaultValue: g.pitchShiftFilter.queryWet.def,
          unit: '%',
          resolveParam: () => b != null
              ? b.filters.pitchShiftFilter.wet()
              : g.pitchShiftFilter.wet,
        ),
      ],
      SoundFontFilterType.amplitudeModulator => [
        FilterParameterInfo.fromParam(
          id: 'frequency',
          name: 'Carrier Freq',
          min: g.amplitudeModulatorFilter.queryFrequency.min,
          max: g.amplitudeModulatorFilter.queryFrequency.max,
          defaultValue: g.amplitudeModulatorFilter.queryFrequency.def,
          unit: 'Hz',
          resolveParam: () => b != null
              ? b.filters.amplitudeModulatorFilter.frequency()
              : g.amplitudeModulatorFilter.frequency,
        ),
        FilterParameterInfo.fromParam(
          id: 'wet',
          name: 'Wet Level',
          min: g.amplitudeModulatorFilter.queryWet.min,
          max: g.amplitudeModulatorFilter.queryWet.max,
          defaultValue: g.amplitudeModulatorFilter.queryWet.def,
          unit: '%',
          resolveParam: () => b != null
              ? b.filters.amplitudeModulatorFilter.wet()
              : g.amplitudeModulatorFilter.wet,
        ),
      ],
      _ => const [],
    };
  }
}
