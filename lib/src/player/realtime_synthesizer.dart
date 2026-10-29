import 'dart:async';
// ignore_for_file: experimental_member_use

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import '../models/sample_info.dart';
import '../models/zone.dart';
import 'voice_calculator.dart';

/// Descriptor sent to the real-time synthesizer worker isolate to trigger a voice.
class RealtimeVoiceTrigger {
  final int voiceId;
  final int key;
  final int velocity;
  final int leftSampleId;
  final int? rightSampleId;
  final int sampleRate;
  final double basePitchRatio;
  final double peakVolume;
  final double pan;
  final bool isLooping;
  final int loopStart;
  final int loopEnd;

  // Volume DAHDSR
  final double volDelaySec;
  final double volAttackSec;
  final double volHoldSec;
  final double volDecaySec;
  final double volSustainLevel;
  final double volReleaseSec;

  // Modulation DAHDSR
  final double modDelaySec;
  final double modAttackSec;
  final double modHoldSec;
  final double modDecaySec;
  final double modSustainLevel;
  final double modReleaseSec;
  final int modEnvToPitchCents;
  final int modEnvToFilterCents;

  // Low-Pass Resonant SVF Filter
  final bool filterEnabled;
  final double filterCutoffHz;
  final double filterResonanceQ;

  // LFOs
  final double modLfoDelaySec;
  final double modLfoFreqHz;
  final int modLfoToPitchCents;
  final int modLfoToFilterCents;
  final double modLfoToVolumeDb;
  final double vibLfoDelaySec;
  final double vibLfoFreqHz;
  final int vibLfoToPitchCents;

  // Choke Group
  final int? exclusiveClass;
  final int? offByGroup;

  const RealtimeVoiceTrigger({
    required this.voiceId,
    required this.key,
    required this.velocity,
    required this.leftSampleId,
    this.rightSampleId,
    required this.sampleRate,
    required this.basePitchRatio,
    required this.peakVolume,
    required this.pan,
    required this.isLooping,
    required this.loopStart,
    required this.loopEnd,
    required this.volDelaySec,
    required this.volAttackSec,
    required this.volHoldSec,
    required this.volDecaySec,
    required this.volSustainLevel,
    required this.volReleaseSec,
    required this.modDelaySec,
    required this.modAttackSec,
    required this.modHoldSec,
    required this.modDecaySec,
    required this.modSustainLevel,
    required this.modReleaseSec,
    required this.modEnvToPitchCents,
    required this.modEnvToFilterCents,
    required this.filterEnabled,
    required this.filterCutoffHz,
    required this.filterResonanceQ,
    required this.modLfoDelaySec,
    required this.modLfoFreqHz,
    required this.modLfoToPitchCents,
    required this.modLfoToFilterCents,
    required this.modLfoToVolumeDb,
    required this.vibLfoDelaySec,
    required this.vibLfoFreqHz,
    required this.vibLfoToPitchCents,
    this.exclusiveClass,
    this.offByGroup,
  });
}

enum _EnvStage { delay, attack, hold, decay, sustain, release, choke, off }

class _ActiveSynthVoice {
  final RealtimeVoiceTrigger trigger;
  final Int16List leftPcm;
  final Int16List? rightPcm;

  double phase = 0.0;
  double ageSec = 0.0;

  // Volume Envelope State
  _EnvStage volStage = _EnvStage.delay;
  double volStageTime = 0.0;
  double volLevel = 0.0;
  double volReleaseStartLevel = 0.0;
  double customReleaseSec = -1.0;

  // Modulation Envelope State
  _EnvStage modStage = _EnvStage.delay;
  double modStageTime = 0.0;
  double modLevel = 0.0;
  double modReleaseStartLevel = 0.0;

  // LFO Phases
  double modLfoPhase = 0.0;
  double vibLfoPhase = 0.0;

  // Cytomic TPT SVF State (Left & Right channels)
  double ic1eqL = 0.0;
  double ic2eqL = 0.0;
  double ic1eqR = 0.0;
  double ic2eqR = 0.0;
  double svfG = 0.0;
  double svfK = 1.414;
  double svfA1 = 0.0;
  double svfA2 = 0.0;
  double svfA3 = 0.0;

  // Dynamic controllers
  double pitchBendMultiplier = 1.0;
  double volumeMultiplier = 1.0;
  double panOverride = double.nan;
  int modWheelCents = 0;

  _ActiveSynthVoice({
    required this.trigger,
    required this.leftPcm,
    this.rightPcm,
  }) {
    if (trigger.volDelaySec <= 0.0005) {
      if (trigger.volAttackSec <= 0.0005) {
        volLevel = 1.0;
        volStage = trigger.volHoldSec > 0.0005
            ? _EnvStage.hold
            : (trigger.volDecaySec > 0.0005
                  ? _EnvStage.decay
                  : _EnvStage.sustain);
      } else {
        volStage = _EnvStage.attack;
      }
    }
    if (trigger.modDelaySec <= 0.0005) {
      if (trigger.modAttackSec <= 0.0005) {
        modLevel = 1.0;
        modStage = trigger.modHoldSec > 0.0005
            ? _EnvStage.hold
            : (trigger.modDecaySec > 0.0005
                  ? _EnvStage.decay
                  : _EnvStage.sustain);
      } else {
        modStage = _EnvStage.attack;
      }
    }
  }

  void triggerRelease({double? overrideReleaseSec}) {
    if (volStage == _EnvStage.release ||
        volStage == _EnvStage.choke ||
        volStage == _EnvStage.off) {
      return;
    }
    if (overrideReleaseSec != null) {
      customReleaseSec = overrideReleaseSec;
    }
    volReleaseStartLevel =
        (volStage == _EnvStage.delay ||
            (volStage == _EnvStage.attack && volLevel < 0.1))
        ? math.max(volLevel, 1.0)
        : volLevel;
    volStage = _EnvStage.release;
    volStageTime = 0.0;

    modReleaseStartLevel = modLevel;
    modStage = _EnvStage.release;
    modStageTime = 0.0;
  }

  void triggerChoke() {
    if (volStage == _EnvStage.choke || volStage == _EnvStage.off) return;
    volReleaseStartLevel = volLevel;
    volStage = _EnvStage.choke;
    volStageTime = 0.0;
  }
}

class _IsolateSynthState {
  final int outputSampleRate;
  final Map<int, Int16List> samplePcmMap = {};
  final List<_ActiveSynthVoice> voices = [];
  double pitchBendMultiplier = 1.0;
  int modWheelCents = 0;

  _IsolateSynthState(this.outputSampleRate);
}

@pragma('vm:entry-point')
void _handleSynthCommand(_IsolateSynthState state, Object? command) {
  if (command is! Map<String, Object?>) return;
  final type = command['type'] as String?;

  switch (type) {
    case 'registerSample':
      final id = command['id']! as int;
      final pcmBytes = command['pcm']! as Uint8List;
      final aligned =
          pcmBytes.offsetInBytes.isEven && pcmBytes.lengthInBytes.isEven
          ? Int16List.view(
              pcmBytes.buffer,
              pcmBytes.offsetInBytes,
              pcmBytes.lengthInBytes ~/ 2,
            )
          : Int16List.sublistView(ByteData.sublistView(pcmBytes));
      state.samplePcmMap[id] = aligned;

    case 'noteOn':
      final trig = command['trigger']! as RealtimeVoiceTrigger;
      final leftPcm = state.samplePcmMap[trig.leftSampleId];
      if (leftPcm == null || leftPcm.isEmpty) return;
      final rightPcm = trig.rightSampleId != null
          ? state.samplePcmMap[trig.rightSampleId!]
          : null;

      // Exclusive class / choke group handling
      final chokeGroup = trig.offByGroup ?? trig.exclusiveClass;
      if (chokeGroup != null && chokeGroup > 0) {
        for (final v in state.voices) {
          if (v.trigger.exclusiveClass == chokeGroup) {
            v.triggerChoke();
          }
        }
      }

      // Cap polyphony at 128 active voices (steal oldest released or quietest voice)
      if (state.voices.length >= 128) {
        state.voices.removeAt(0);
      }

      final voice = _ActiveSynthVoice(
        trigger: trig,
        leftPcm: leftPcm,
        rightPcm: rightPcm,
      )
        ..pitchBendMultiplier = state.pitchBendMultiplier
        ..modWheelCents = state.modWheelCents;
      state.voices.add(voice);

    case 'noteOffKey':
      final key = command['key']! as int;
      final releaseSec = command['releaseSec'] as double?;
      for (final v in state.voices) {
        if (v.trigger.key == key) {
          v.triggerRelease(overrideReleaseSec: releaseSec);
        }
      }

    case 'releaseVoiceId':
      final voiceId = command['voiceId']! as int;
      final releaseSec = command['releaseSec'] as double?;
      for (final v in state.voices) {
        if (v.trigger.voiceId == voiceId) {
          v.triggerRelease(overrideReleaseSec: releaseSec);
        }
      }

    case 'stopVoiceId':
      final voiceId = command['voiceId']! as int;
      state.voices.removeWhere((v) => v.trigger.voiceId == voiceId);

    case 'allNotesOff':
      final releaseSec = command['releaseSec'] as double?;
      if (releaseSec != null && releaseSec <= 0.0) {
        state.voices.clear();
      } else {
        for (final v in state.voices) {
          v.triggerRelease(overrideReleaseSec: releaseSec);
        }
      }

    case 'pitchBend':
      final mult = command['multiplier']! as double;
      state.pitchBendMultiplier = mult;
      for (final v in state.voices) {
        v.pitchBendMultiplier = mult;
      }

    case 'modWheel':
      final cents = command['cents']! as int;
      state.modWheelCents = cents;
      for (final v in state.voices) {
        v.modWheelCents = cents;
      }
  }
}

@pragma('vm:entry-point')
int _generateSynthAudioChunk(
  Float32List out,
  int framesToWrite,
  _IsolateSynthState state,
  void Function(Object? event) emitToUi,
) {
  if (state.voices.isEmpty) return 0;

  final sampleCount = framesToWrite * 2;
  for (var i = 0; i < sampleCount; i++) {
    out[i] = 0.0;
  }

  final invOutRate = 1.0 / state.outputSampleRate;
  const controlBlockSize = 32;

  for (var vIdx = state.voices.length - 1; vIdx >= 0; vIdx--) {
    final v = state.voices[vIdx];
    final trig = v.trigger;
    final leftPcm = v.leftPcm;
    final rightPcm = v.rightPcm;
    final maxSampleIdx = leftPcm.length - 1;
    if (maxSampleIdx <= 0) {
      state.voices.removeAt(vIdx);
      continue;
    }

    final baseRate =
        (trig.sampleRate / state.outputSampleRate) * trig.basePitchRatio;
    final pan = v.panOverride.isNaN ? trig.pan : v.panOverride;
    final panAngle = (pan.clamp(-1.0, 1.0) + 1.0) * (math.pi * 0.25);
    final panL = math.cos(panAngle);
    final panR = math.sin(panAngle);

    var frame = 0;
    while (frame < framesToWrite) {
      final blockEnd = math.min(frame + controlBlockSize, framesToWrite);
      final blockFrames = blockEnd - frame;
      final dt = blockFrames * invOutRate;

      // 1. Step Volume Envelope (6-Stage DAHDSR)
      _stepVolEnvelope(v, dt);
      if (v.volStage == _EnvStage.off) break;

      // 2. Step Modulation Envelope (6-Stage DAHDSR)
      _stepModEnvelope(v, dt);

      // 3. Step LFOs (ModLFO & VibLFO)
      v.ageSec += dt;
      var modLfoVal = 0.0;
      if (v.ageSec >= trig.modLfoDelaySec && trig.modLfoFreqHz > 0) {
        v.modLfoPhase = (v.modLfoPhase + trig.modLfoFreqHz * dt) % 1.0;
        // Triangle LFO (-1.0 to +1.0)
        modLfoVal = 1.0 - 4.0 * (v.modLfoPhase - 0.5).abs();
      }

      var vibLfoVal = 0.0;
      if (v.ageSec >= trig.vibLfoDelaySec && trig.vibLfoFreqHz > 0) {
        v.vibLfoPhase = (v.vibLfoPhase + trig.vibLfoFreqHz * dt) % 1.0;
        vibLfoVal = 1.0 - 4.0 * (v.vibLfoPhase - 0.5).abs();
      }

      // 4. Compute modulated pitch increment
      final totalPitchCents =
          (v.modLevel * trig.modEnvToPitchCents) +
          (modLfoVal * trig.modLfoToPitchCents) +
          (vibLfoVal * (trig.vibLfoToPitchCents + v.modWheelCents));
      final pitchModMult = totalPitchCents == 0.0
          ? 1.0
          : math.pow(2.0, totalPitchCents / 1200.0).toDouble();
      final phaseStep = baseRate * v.pitchBendMultiplier * pitchModMult;

      // 5. Compute SVF Low-Pass Filter Coefficients if active
      final useFilter =
          trig.filterEnabled ||
          trig.modEnvToFilterCents != 0 ||
          trig.modLfoToFilterCents != 0;
      if (useFilter) {
        final filterCentsOffset =
            (v.modLevel * trig.modEnvToFilterCents) +
            (modLfoVal * trig.modLfoToFilterCents);
        final dynamicCutoff =
            (trig.filterCutoffHz *
                    (filterCentsOffset == 0.0
                        ? 1.0
                        : math.pow(2.0, filterCentsOffset / 1200.0)))
                .clamp(20.0, state.outputSampleRate * 0.48);
        v.svfG = math.tan(math.pi * dynamicCutoff * invOutRate);
        v.svfK = 1.0 / trig.filterResonanceQ.clamp(0.5, 25.0);
        v.svfA1 = 1.0 / (1.0 + v.svfG * (v.svfG + v.svfK));
        v.svfA2 = v.svfG * v.svfA1;
        v.svfA3 = v.svfG * v.svfA2;
      }

      // 6. Compute amplitude gain
      var lfoGain = 1.0;
      if (trig.modLfoToVolumeDb != 0.0 && modLfoVal != 0.0) {
        lfoGain = math
            .pow(10.0, (modLfoVal * trig.modLfoToVolumeDb) / 20.0)
            .toDouble();
      }
      final amp =
          v.volLevel * trig.peakVolume * v.volumeMultiplier * lfoGain * (1.0 / 32768.0);
      final gainL = amp * panL;
      final gainR = amp * panR;

      // 7. Inner sample loop
      if (v.volStage != _EnvStage.delay) {
        for (var f = frame; f < blockEnd; f++) {
          final idx = v.phase.toInt();
          if (idx >= maxSampleIdx) {
            if (trig.isLooping && trig.loopEnd > trig.loopStart) {
              final loopSpan = trig.loopEnd - trig.loopStart;
              v.phase =
                  trig.loopStart + ((v.phase - trig.loopStart) % loopSpan);
            } else {
              v.volStage = _EnvStage.off;
              break;
            }
          }

          final i0 = v.phase.toInt().clamp(0, maxSampleIdx - 1);
          final frac = v.phase - i0;
          var sL = leftPcm[i0] + frac * (leftPcm[i0 + 1] - leftPcm[i0]);
          var sR = rightPcm != null && i0 + 1 < rightPcm.length
              ? (rightPcm[i0] + frac * (rightPcm[i0 + 1] - rightPcm[i0]))
              : sL;

          if (useFilter) {
            final v3L = sL - v.ic2eqL;
            final v1L = v.svfA1 * v.ic1eqL + v.svfA2 * v3L;
            final v2L = v.ic2eqL + v.svfA2 * v.ic1eqL + v.svfA3 * v3L;
            v.ic1eqL = 2.0 * v1L - v.ic1eqL;
            v.ic2eqL = 2.0 * v2L - v.ic2eqL;
            sL = v2L;

            if (rightPcm != null) {
              final v3R = sR - v.ic2eqR;
              final v1R = v.svfA1 * v.ic1eqR + v.svfA2 * v3R;
              final v2R = v.ic2eqR + v.svfA2 * v.ic1eqR + v.svfA3 * v3R;
              v.ic1eqR = 2.0 * v1R - v.ic1eqR;
              v.ic2eqR = 2.0 * v2R - v.ic2eqR;
              sR = v2R;
            } else {
              sR = sL;
            }
          }

          final outBase = f * 2;
          out[outBase] = out[outBase] + sL * gainL;
          out[outBase + 1] = out[outBase + 1] + sR * gainR;

          v.phase += phaseStep;
          if (trig.isLooping &&
              trig.loopEnd > trig.loopStart &&
              v.phase >= trig.loopEnd) {
            v.phase =
                trig.loopStart +
                ((v.phase - trig.loopStart) % (trig.loopEnd - trig.loopStart));
          }
        }
      }

      frame = blockEnd;
    }

    if (v.volStage == _EnvStage.off) {
      state.voices.removeAt(vIdx);
    }
  }
  return framesToWrite;
}

void _stepVolEnvelope(_ActiveSynthVoice v, double dt) {
  final trig = v.trigger;
  v.volStageTime += dt;

  switch (v.volStage) {
    case _EnvStage.delay:
      v.volLevel = 0.0;
      if (v.volStageTime >= trig.volDelaySec) {
        v.volStageTime = 0.0;
        v.volStage = trig.volAttackSec > 0.0005
            ? _EnvStage.attack
            : _EnvStage.hold;
      }
    case _EnvStage.attack:
      if (trig.volAttackSec <= 0.0005) {
        v.volLevel = 1.0;
        v.volStage = _EnvStage.hold;
        v.volStageTime = 0.0;
      } else {
        v.volLevel = (v.volStageTime / trig.volAttackSec).clamp(0.0, 1.0);
        if (v.volStageTime >= trig.volAttackSec) {
          v.volLevel = 1.0;
          v.volStage = _EnvStage.hold;
          v.volStageTime = 0.0;
        }
      }
    case _EnvStage.hold:
      v.volLevel = 1.0;
      if (v.volStageTime >= trig.volHoldSec) {
        v.volStageTime = 0.0;
        v.volStage = trig.volDecaySec > 0.0005
            ? _EnvStage.decay
            : _EnvStage.sustain;
      }
    case _EnvStage.decay:
      if (trig.volDecaySec <= 0.0005) {
        v.volLevel = trig.volSustainLevel;
        v.volStage = _EnvStage.sustain;
      } else {
        final t = (v.volStageTime / trig.volDecaySec).clamp(0.0, 1.0);
        v.volLevel = 1.0 + (trig.volSustainLevel - 1.0) * t;
        if (t >= 1.0) {
          v.volLevel = trig.volSustainLevel;
          v.volStage = _EnvStage.sustain;
        }
      }
    case _EnvStage.sustain:
      v.volLevel = trig.volSustainLevel;
      if (v.volLevel <= 0.0001) {
        v.volStage = _EnvStage.off;
      }
    case _EnvStage.release:
      final relSec = v.customReleaseSec >= 0.0
          ? v.customReleaseSec
          : trig.volReleaseSec;
      if (relSec <= 0.001) {
        v.volLevel = 0.0;
        v.volStage = _EnvStage.off;
      } else {
        final t = (v.volStageTime / relSec).clamp(0.0, 1.0);
        // Exponential-like curve for natural acoustic decay
        final invT = 1.0 - t;
        v.volLevel = v.volReleaseStartLevel * (invT * invT);
        if (t >= 1.0 || v.volLevel <= 0.0001) {
          v.volLevel = 0.0;
          v.volStage = _EnvStage.off;
        }
      }
    case _EnvStage.choke:
      const chokeSec = 0.005;
      final t = (v.volStageTime / chokeSec).clamp(0.0, 1.0);
      v.volLevel = v.volReleaseStartLevel * (1.0 - t);
      if (t >= 1.0) {
        v.volLevel = 0.0;
        v.volStage = _EnvStage.off;
      }
    case _EnvStage.off:
      v.volLevel = 0.0;
  }
}

void _stepModEnvelope(_ActiveSynthVoice v, double dt) {
  final trig = v.trigger;
  v.modStageTime += dt;

  switch (v.modStage) {
    case _EnvStage.delay:
      v.modLevel = 0.0;
      if (v.modStageTime >= trig.modDelaySec) {
        v.modStageTime = 0.0;
        v.modStage = trig.modAttackSec > 0.0005
            ? _EnvStage.attack
            : _EnvStage.hold;
      }
    case _EnvStage.attack:
      if (trig.modAttackSec <= 0.0005) {
        v.modLevel = 1.0;
        v.modStage = _EnvStage.hold;
        v.modStageTime = 0.0;
      } else {
        v.modLevel = (v.modStageTime / trig.modAttackSec).clamp(0.0, 1.0);
        if (v.modStageTime >= trig.modAttackSec) {
          v.modLevel = 1.0;
          v.modStage = _EnvStage.hold;
          v.modStageTime = 0.0;
        }
      }
    case _EnvStage.hold:
      v.modLevel = 1.0;
      if (v.modStageTime >= trig.modHoldSec) {
        v.modStageTime = 0.0;
        v.modStage = trig.modDecaySec > 0.0005
            ? _EnvStage.decay
            : _EnvStage.sustain;
      }
    case _EnvStage.decay:
      if (trig.modDecaySec <= 0.0005) {
        v.modLevel = trig.modSustainLevel;
        v.modStage = _EnvStage.sustain;
      } else {
        final t = (v.modStageTime / trig.modDecaySec).clamp(0.0, 1.0);
        v.modLevel = 1.0 + (trig.modSustainLevel - 1.0) * t;
        if (t >= 1.0) {
          v.modLevel = trig.modSustainLevel;
          v.modStage = _EnvStage.sustain;
        }
      }
    case _EnvStage.sustain:
      v.modLevel = trig.modSustainLevel;
    case _EnvStage.release:
      if (trig.modReleaseSec <= 0.001) {
        v.modLevel = 0.0;
        v.modStage = _EnvStage.off;
      } else {
        final t = (v.modStageTime / trig.modReleaseSec).clamp(0.0, 1.0);
        v.modLevel = v.modReleaseStartLevel * (1.0 - t);
        if (t >= 1.0) {
          v.modLevel = 0.0;
          v.modStage = _EnvStage.off;
        }
      }
    case _EnvStage.choke || _EnvStage.off:
      v.modLevel = 0.0;
  }
}

/// Real-time worker-isolate SoundFont DSP synthesizer powered by
/// [SoLoud.setRealtimeStream] and [RealtimeStreamFeeder] (`SoLoudIsolate`).
class RealtimeSoundFontSynthesizer {
  final int sampleRate;
  final int busId;
  RealtimeStreamHandle? _stream;
  RealtimeStreamFeeder<_IsolateSynthState>? _feeder;
  SoundHandle? _playHandle;
  final Set<int> _registeredSampleIds = {};
  int _nextVoiceId = 1;

  RealtimeSoundFontSynthesizer({
    this.sampleRate = 44100,
    this.busId = 0,
  });

  bool get isRunning => _feeder != null && !_feeder!.isDisposed;

  void _ensureVoicePlaying() {
    final stream = _stream;
    if (stream == null || !SoLoud.instance.isInitialized) return;
    if (_playHandle != null &&
        SoLoud.instance.getIsValidVoiceHandle(_playHandle!)) {
      if (SoLoud.instance.getPause(_playHandle!)) {
        SoLoud.instance.setPause(_playHandle!, false);
      }
      return;
    }
    _playHandle = SoLoud.instance.playScheduled(
      stream.source,
      Duration.zero,
      busId: busId,
    );
    stream.bindActiveVoice(_playHandle);
  }

  /// Starts the real-time stream and background worker isolate feeder.
  Future<void> ensureStarted() async {
    if (!SoLoud.instance.isInitialized) return;
    if (isRunning) {
      _ensureVoicePlaying();
      return;
    }

    final stream = SoLoud.instance.setRealtimeStream(
      sampleRate: sampleRate,
      channels: Channels.stereo,
      format: BufferType.f32le,
      bufferFrames: 4096,
      historyFrames: 4096,
    );
    _stream = stream;

    _playHandle = SoLoud.instance.playScheduled(
      stream.source,
      Duration.zero,
      busId: busId,
    );
    stream.bindActiveVoice(_playHandle);

    _feeder = await stream.startFloat32Feeder<_IsolateSynthState>(
      initialState: _IsolateSynthState(sampleRate),
      onFeed: _generateSynthAudioChunk,
      onMessage: _handleSynthCommand,
      targetBufferedFrames: 2048,
      chunkFrames: 256,
      tickInterval: const Duration(milliseconds: 4),
    );
  }

  /// Registers raw 16-bit signed PCM bytes for [sampleId] in the worker isolate.
  void registerSamplePcm(int sampleId, Uint8List pcm16Bytes) {
    if (_registeredSampleIds.contains(sampleId)) return;
    _registeredSampleIds.add(sampleId);
    _feeder?.sendMessage({
      'type': 'registerSample',
      'id': sampleId,
      'pcm': pcm16Bytes,
    });
  }

  /// Triggers a polyphonic voice in the worker isolate and returns its `voiceId`.
  int triggerVoice({
    required int key,
    required int velocity,
    required SampleInfo leftSample,
    SampleInfo? rightSample,
    Zone? zone,
    Zone? presetZone,
    required double basePitchRatio,
    required double peakVolume,
    required double pan,
    required bool isLooping,
    required int loopStart,
    required int loopEnd,
    required Duration releaseDuration,
  }) {
    _ensureVoicePlaying();
    final voiceId = _nextVoiceId++;
    final volStages = VoiceCalculator.calculateVolEnvStages(
      zone: zone,
      presetZone: presetZone,
      peakVolume: 1.0,
    );
    final filterParams = VoiceCalculator.calculateFilterParams(
      zone: zone,
      presetZone: presetZone,
    );
    final exc = VoiceCalculator.resolveExclusiveClass(
      zone: zone,
      presetZone: presetZone,
    );

    final trig = RealtimeVoiceTrigger(
      voiceId: voiceId,
      key: key,
      velocity: velocity,
      leftSampleId: leftSample.id,
      rightSampleId: rightSample?.id,
      sampleRate: leftSample.sampleRate > 0 ? leftSample.sampleRate : 44100,
      basePitchRatio: basePitchRatio,
      peakVolume: peakVolume,
      pan: pan,
      isLooping: isLooping,
      loopStart: loopStart,
      loopEnd: loopEnd,
      volDelaySec: volStages.delay.inMicroseconds / 1000000.0,
      volAttackSec: volStages.attack.inMicroseconds / 1000000.0,
      volHoldSec: volStages.hold.inMicroseconds / 1000000.0,
      volDecaySec: volStages.decay.inMicroseconds / 1000000.0,
      volSustainLevel: volStages.sustainVolume,
      volReleaseSec: releaseDuration.inMicroseconds / 1000000.0,
      modDelaySec: zone?.modEnvDelay ?? presetZone?.modEnvDelay ?? 0.0,
      modAttackSec: zone?.modEnvAttack ?? presetZone?.modEnvAttack ?? 0.001,
      modHoldSec: zone?.modEnvHold ?? presetZone?.modEnvHold ?? 0.0,
      modDecaySec: zone?.modEnvDecay ?? presetZone?.modEnvDecay ?? 0.001,
      modSustainLevel: zone?.modEnvSustain ?? presetZone?.modEnvSustain ?? 1.0,
      modReleaseSec: zone?.modEnvRelease ?? presetZone?.modEnvRelease ?? 0.05,
      modEnvToPitchCents:
          (zone?.modEnvToPitch ?? 0) + (presetZone?.modEnvToPitch ?? 0),
      modEnvToFilterCents:
          (zone?.modEnvToFilterFc ?? 0) + (presetZone?.modEnvToFilterFc ?? 0),
      filterEnabled: filterParams.enabled,
      filterCutoffHz: filterParams.cutoffHz,
      filterResonanceQ: filterParams.resonanceQ,
      modLfoDelaySec: zone?.modLfoDelay ?? presetZone?.modLfoDelay ?? 0.0,
      modLfoFreqHz: zone?.modLfoFreq ?? presetZone?.modLfoFreq ?? 8.176,
      modLfoToPitchCents:
          (zone?.modLfoToPitch ?? 0) + (presetZone?.modLfoToPitch ?? 0),
      modLfoToFilterCents:
          (zone?.modLfoToFilterFc ?? 0) + (presetZone?.modLfoToFilterFc ?? 0),
      modLfoToVolumeDb:
          (zone?.modLfoToVolume ?? 0.0) + (presetZone?.modLfoToVolume ?? 0.0),
      vibLfoDelaySec: zone?.vibLfoDelay ?? presetZone?.vibLfoDelay ?? 0.0,
      vibLfoFreqHz: zone?.vibLfoFreq ?? presetZone?.vibLfoFreq ?? 8.176,
      vibLfoToPitchCents:
          (zone?.vibLfoToPitch ?? 0) + (presetZone?.vibLfoToPitch ?? 0),
      exclusiveClass: exc.exclusiveClass,
      offByGroup: exc.offByGroup,
    );

    _feeder?.sendMessage({
      'type': 'noteOn',
      'trigger': trig,
    });
    return voiceId;
  }

  /// Releases a specific voice by [voiceId].
  void releaseVoiceId(int voiceId, {Duration? customRelease}) {
    _feeder?.sendMessage({
      'type': 'releaseVoiceId',
      'voiceId': voiceId,
      'releaseSec': customRelease != null
          ? customRelease.inMicroseconds / 1000000.0
          : null,
    });
  }

  /// Immediately stops a specific voice by [voiceId].
  void stopVoiceId(int voiceId) {
    _feeder?.sendMessage({
      'type': 'stopVoiceId',
      'voiceId': voiceId,
    });
  }

  /// Releases all voices matching [key].
  void noteOffKey(int key, {Duration? releaseDuration}) {
    _feeder?.sendMessage({
      'type': 'noteOffKey',
      'key': key,
      'releaseSec': releaseDuration != null
          ? releaseDuration.inMicroseconds / 1000000.0
          : null,
    });
  }

  /// Releases or stops all active voices.
  void allNotesOff({Duration? releaseDuration}) {
    _feeder?.sendMessage({
      'type': 'allNotesOff',
      'releaseSec': releaseDuration != null
          ? releaseDuration.inMicroseconds / 1000000.0
          : null,
    });
  }

  /// Updates the pitch bend multiplier across all active voices.
  void setPitchBend(double multiplier) {
    _feeder?.sendMessage({
      'type': 'pitchBend',
      'multiplier': multiplier,
    });
  }

  /// Updates the Modulation Wheel (`CC 1`) vibrato depth in cents (`0..50` cents default).
  void setModWheelCents(int cents) {
    _feeder?.sendMessage({
      'type': 'modWheel',
      'cents': cents,
    });
  }

  /// Stops and disposes the background isolate and stream.
  Future<void> dispose() async {
    final f = _feeder;
    _feeder = null;
    if (f != null) {
      await f.dispose();
    }
    final h = _playHandle;
    _playHandle = null;
    if (h != null &&
        SoLoud.instance.isInitialized &&
        SoLoud.instance.getIsValidVoiceHandle(h)) {
      try {
        await SoLoud.instance.stop(h);
      } catch (_) {}
    }
    final s = _stream;
    _stream = null;
    if (s != null && SoLoud.instance.isInitialized) {
      try {
        await SoLoud.instance.disposeSource(s.source);
      } catch (_) {}
    }
    _registeredSampleIds.clear();
  }
}
