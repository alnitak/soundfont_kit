import 'package:flutter_soloud/flutter_soloud.dart';

/// Available global audio filter types for SoundFont playback.
enum SoundFontFilterType {
  freeverb(
    'Reverb (Freeverb)',
    'Spatial room acoustics and concert hall resonance',
  ),
  echo('Echo / Delay', 'Stereo echo repeats and feedback delay'),
  biquad('Biquad Filter', 'Lowpass, highpass, and bandpass resonant filter'),
  flanger('Flanger / Chorus', 'Modulated pitch shimmering and stereo width'),
  bassBoost('Bass Boost', 'Low-frequency enhancement and punch'),
  lofi('Lo-Fi', 'Bit-crushing and vintage sampler rate reduction'),
  waveShaper('Wave Shaper', 'Harmonic saturation and distortion');

  final String label;
  final String description;

  const SoundFontFilterType(this.label, this.description);
}

/// Metadata description of a single adjustable filter parameter.
class FilterParameterInfo {
  final String id;
  final String name;
  final double min;
  final double max;
  final double defaultValue;
  final String unit;
  final double Function() getValue;
  final void Function(double val) onSetValue;

  const FilterParameterInfo({
    required this.id,
    required this.name,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.unit = '',
    required this.getValue,
    required this.onSetValue,
  });

  double get currentValue => getValue();

  void setValue(double val) {
    onSetValue(val.clamp(min, max));
  }
}

/// Controller managing SoLoud global output audio filters.
class SoundFontGlobalFilters {
  const SoundFontGlobalFilters();

  /// Checks whether a specific global filter is currently active.
  bool isActive(SoundFontFilterType type) {
    if (!SoLoud.instance.isInitialized) return false;
    final filters = SoLoud.instance.filters;
    return switch (type) {
      SoundFontFilterType.freeverb => filters.freeverbFilter.isActive,
      SoundFontFilterType.echo => filters.echoFilter.isActive,
      SoundFontFilterType.biquad => filters.biquadResonantFilter.isActive,
      SoundFontFilterType.flanger => filters.flangerFilter.isActive,
      SoundFontFilterType.bassBoost => filters.bassBoostFilter.isActive,
      SoundFontFilterType.lofi => filters.lofiFilter.isActive,
      SoundFontFilterType.waveShaper => filters.waveShaperFilter.isActive,
    };
  }

  /// Toggles activation of a global filter safely by verifying current active state.
  void toggle(SoundFontFilterType type, bool active) {
    if (!SoLoud.instance.isInitialized) return;
    final isCurrentlyActive = isActive(type);
    if (active == isCurrentlyActive) return;

    final filters = SoLoud.instance.filters;
    switch (type) {
      case SoundFontFilterType.freeverb:
        active
            ? filters.freeverbFilter.activate()
            : filters.freeverbFilter.deactivate();
        break;
      case SoundFontFilterType.echo:
        active
            ? filters.echoFilter.activate()
            : filters.echoFilter.deactivate();
        break;
      case SoundFontFilterType.biquad:
        active
            ? filters.biquadResonantFilter.activate()
            : filters.biquadResonantFilter.deactivate();
        break;
      case SoundFontFilterType.flanger:
        active
            ? filters.flangerFilter.activate()
            : filters.flangerFilter.deactivate();
        break;
      case SoundFontFilterType.bassBoost:
        active
            ? filters.bassBoostFilter.activate()
            : filters.bassBoostFilter.deactivate();
        break;
      case SoundFontFilterType.lofi:
        active
            ? filters.lofiFilter.activate()
            : filters.lofiFilter.deactivate();
        break;
      case SoundFontFilterType.waveShaper:
        active
            ? filters.waveShaperFilter.activate()
            : filters.waveShaperFilter.deactivate();
        break;
    }
  }

  /// Deactivates all active global filters.
  void deactivateAll() {
    if (!SoLoud.instance.isInitialized) return;
    for (final type in SoundFontFilterType.values) {
      if (isActive(type)) {
        toggle(type, false);
      }
    }
  }

  /// Retrieves parameter metadata and control callbacks for a specific filter.
  List<FilterParameterInfo> getParameters(SoundFontFilterType type) {
    if (!SoLoud.instance.isInitialized) return const [];
    final filters = SoLoud.instance.filters;

    return switch (type) {
      SoundFontFilterType.freeverb => [
        FilterParameterInfo(
          id: 'room_size',
          name: 'Room Size',
          min: filters.freeverbFilter.queryRoomSize.min,
          max: filters.freeverbFilter.queryRoomSize.max,
          defaultValue: filters.freeverbFilter.queryRoomSize.def,
          unit: '%',
          getValue: () => filters.freeverbFilter.roomSize.value,
          onSetValue: (v) => filters.freeverbFilter.roomSize.value = v,
        ),
        FilterParameterInfo(
          id: 'damp',
          name: 'Dampening',
          min: filters.freeverbFilter.queryDamp.min,
          max: filters.freeverbFilter.queryDamp.max,
          defaultValue: filters.freeverbFilter.queryDamp.def,
          unit: '%',
          getValue: () => filters.freeverbFilter.damp.value,
          onSetValue: (v) => filters.freeverbFilter.damp.value = v,
        ),
        FilterParameterInfo(
          id: 'width',
          name: 'Width',
          min: filters.freeverbFilter.queryWidth.min,
          max: filters.freeverbFilter.queryWidth.max,
          defaultValue: filters.freeverbFilter.queryWidth.def,
          unit: '%',
          getValue: () => filters.freeverbFilter.width.value,
          onSetValue: (v) => filters.freeverbFilter.width.value = v,
        ),
        FilterParameterInfo(
          id: 'wet',
          name: 'Wet Level',
          min: filters.freeverbFilter.queryWet.min,
          max: filters.freeverbFilter.queryWet.max,
          defaultValue: filters.freeverbFilter.queryWet.def,
          unit: '%',
          getValue: () => filters.freeverbFilter.wet.value,
          onSetValue: (v) => filters.freeverbFilter.wet.value = v,
        ),
      ],
      SoundFontFilterType.echo => [
        FilterParameterInfo(
          id: 'delay',
          name: 'Delay Time',
          min: filters.echoFilter.queryDelay.min,
          max: filters.echoFilter.queryDelay.max <= 10.0
              ? filters.echoFilter.queryDelay.max
              : 3.0,
          defaultValue: filters.echoFilter.queryDelay.def,
          unit: 's',
          getValue: () => filters.echoFilter.delay.value,
          onSetValue: (v) => filters.echoFilter.delay.value = v,
        ),
        FilterParameterInfo(
          id: 'decay',
          name: 'Feedback',
          min: filters.echoFilter.queryDecay.min,
          max: filters.echoFilter.queryDecay.max,
          defaultValue: filters.echoFilter.queryDecay.def,
          unit: '%',
          getValue: () => filters.echoFilter.decay.value,
          onSetValue: (v) => filters.echoFilter.decay.value = v,
        ),
        FilterParameterInfo(
          id: 'filter',
          name: 'Tone Damping',
          min: filters.echoFilter.queryFilter.min,
          max: filters.echoFilter.queryFilter.max,
          defaultValue: filters.echoFilter.queryFilter.def,
          unit: '%',
          getValue: () => filters.echoFilter.filter.value,
          onSetValue: (v) => filters.echoFilter.filter.value = v,
        ),
        FilterParameterInfo(
          id: 'wet',
          name: 'Wet Level',
          min: filters.echoFilter.queryWet.min,
          max: filters.echoFilter.queryWet.max,
          defaultValue: filters.echoFilter.queryWet.def,
          unit: '%',
          getValue: () => filters.echoFilter.wet.value,
          onSetValue: (v) => filters.echoFilter.wet.value = v,
        ),
      ],
      SoundFontFilterType.biquad => [
        FilterParameterInfo(
          id: 'frequency',
          name: 'Cutoff',
          min: filters.biquadResonantFilter.queryFrequency.min,
          max: filters.biquadResonantFilter.queryFrequency.max,
          defaultValue: filters.biquadResonantFilter.queryFrequency.def,
          unit: 'Hz',
          getValue: () => filters.biquadResonantFilter.frequency.value,
          onSetValue: (v) => filters.biquadResonantFilter.frequency.value = v,
        ),
        FilterParameterInfo(
          id: 'resonance',
          name: 'Resonance',
          min: filters.biquadResonantFilter.queryResonance.min,
          max: filters.biquadResonantFilter.queryResonance.max,
          defaultValue: filters.biquadResonantFilter.queryResonance.def,
          unit: 'Q',
          getValue: () => filters.biquadResonantFilter.resonance.value,
          onSetValue: (v) => filters.biquadResonantFilter.resonance.value = v,
        ),
        FilterParameterInfo(
          id: 'wet',
          name: 'Wet Level',
          min: filters.biquadResonantFilter.queryWet.min,
          max: filters.biquadResonantFilter.queryWet.max,
          defaultValue: filters.biquadResonantFilter.queryWet.def,
          unit: '%',
          getValue: () => filters.biquadResonantFilter.wet.value,
          onSetValue: (v) => filters.biquadResonantFilter.wet.value = v,
        ),
      ],
      SoundFontFilterType.flanger => [
        FilterParameterInfo(
          id: 'delay',
          name: 'Delay Time',
          min: filters.flangerFilter.queryDelay.min,
          max: filters.flangerFilter.queryDelay.max,
          defaultValue: filters.flangerFilter.queryDelay.def,
          unit: 's',
          getValue: () => filters.flangerFilter.delay.value,
          onSetValue: (v) => filters.flangerFilter.delay.value = v,
        ),
        FilterParameterInfo(
          id: 'freq',
          name: 'LFO Freq',
          min: filters.flangerFilter.queryFreq.min,
          max: filters.flangerFilter.queryFreq.max,
          defaultValue: filters.flangerFilter.queryFreq.def,
          unit: 'Hz',
          getValue: () => filters.flangerFilter.freq.value,
          onSetValue: (v) => filters.flangerFilter.freq.value = v,
        ),
        FilterParameterInfo(
          id: 'wet',
          name: 'Wet Level',
          min: filters.flangerFilter.queryWet.min,
          max: filters.flangerFilter.queryWet.max,
          defaultValue: filters.flangerFilter.queryWet.def,
          unit: '%',
          getValue: () => filters.flangerFilter.wet.value,
          onSetValue: (v) => filters.flangerFilter.wet.value = v,
        ),
      ],
      SoundFontFilterType.bassBoost => [
        FilterParameterInfo(
          id: 'boost',
          name: 'Bass Boost',
          min: filters.bassBoostFilter.queryBoost.min,
          max: filters.bassBoostFilter.queryBoost.max,
          defaultValue: filters.bassBoostFilter.queryBoost.def,
          unit: 'x',
          getValue: () => filters.bassBoostFilter.boost.value,
          onSetValue: (v) => filters.bassBoostFilter.boost.value = v,
        ),
        FilterParameterInfo(
          id: 'wet',
          name: 'Wet Level',
          min: filters.bassBoostFilter.queryWet.min,
          max: filters.bassBoostFilter.queryWet.max,
          defaultValue: filters.bassBoostFilter.queryWet.def,
          unit: '%',
          getValue: () => filters.bassBoostFilter.wet.value,
          onSetValue: (v) => filters.bassBoostFilter.wet.value = v,
        ),
      ],
      SoundFontFilterType.lofi => [
        FilterParameterInfo(
          id: 'samplerate',
          name: 'Sample Rate',
          min: filters.lofiFilter.querySamplerate.min,
          max: filters.lofiFilter.querySamplerate.max,
          defaultValue: filters.lofiFilter.querySamplerate.def,
          unit: 'Hz',
          getValue: () => filters.lofiFilter.samplerate.value,
          onSetValue: (v) => filters.lofiFilter.samplerate.value = v,
        ),
        FilterParameterInfo(
          id: 'bitdepth',
          name: 'Bit Depth',
          min: filters.lofiFilter.queryBitdepth.min,
          max: filters.lofiFilter.queryBitdepth.max,
          defaultValue: filters.lofiFilter.queryBitdepth.def,
          unit: 'bits',
          getValue: () => filters.lofiFilter.bitdepth.value,
          onSetValue: (v) => filters.lofiFilter.bitdepth.value = v,
        ),
        FilterParameterInfo(
          id: 'wet',
          name: 'Wet Level',
          min: filters.lofiFilter.queryWet.min,
          max: filters.lofiFilter.queryWet.max,
          defaultValue: filters.lofiFilter.queryWet.def,
          unit: '%',
          getValue: () => filters.lofiFilter.wet.value,
          onSetValue: (v) => filters.lofiFilter.wet.value = v,
        ),
      ],
      SoundFontFilterType.waveShaper => [
        FilterParameterInfo(
          id: 'amount',
          name: 'Drive',
          min: filters.waveShaperFilter.queryAmount.min,
          max: filters.waveShaperFilter.queryAmount.max,
          defaultValue: filters.waveShaperFilter.queryAmount.def,
          unit: '',
          getValue: () => filters.waveShaperFilter.amount.value,
          onSetValue: (v) => filters.waveShaperFilter.amount.value = v,
        ),
        FilterParameterInfo(
          id: 'wet',
          name: 'Wet Level',
          min: filters.waveShaperFilter.queryWet.min,
          max: filters.waveShaperFilter.queryWet.max,
          defaultValue: filters.waveShaperFilter.queryWet.def,
          unit: '%',
          getValue: () => filters.waveShaperFilter.wet.value,
          onSetValue: (v) => filters.waveShaperFilter.wet.value = v,
        ),
      ],
    };
  }
}
