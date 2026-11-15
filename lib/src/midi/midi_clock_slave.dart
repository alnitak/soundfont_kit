/// Real-time MIDI Clock Slave (`0xF8`) synchronization and hardware clock simulator.
library;

import 'dart:async';
import 'dart:math' as math;

/// MIDI System Real-Time Timing Clock byte (`24` pulses per quarter note).
const int kMidiTimingClock = 0xF8;

/// MIDI System Real-Time Start byte (resets song position to 0 and starts).
const int kMidiStart = 0xFA;

/// MIDI System Real-Time Continue byte (resumes playback from current position).
const int kMidiContinue = 0xFB;

/// MIDI System Real-Time Stop byte (pauses playback).
const int kMidiStop = 0xFC;

/// MIDI System Common Song Position Pointer status byte (followed by 2 data bytes).
const int kMidiSongPositionPointer = 0xF2;

/// Number of `0xF8` Timing Clock ticks per quarter note in standard MIDI.
const int kMidiClocksPerQuarterNote = 24;

/// Event category produced by [MidiClockSlave].
enum MidiClockEventType {
  /// A `0xF8` Timing Clock pulse arrived (24 PPQ).
  clock,

  /// A `0xFA` Start message arrived.
  start,

  /// A `0xFB` Continue message arrived.
  continuePlayback,

  /// A `0xFC` Stop message arrived.
  stop,

  /// A 3-byte `0xF2 <lsb> <msb>` Song Position Pointer message completed.
  songPosition,
}

/// Snapshot emitted by [MidiClockSlave] whenever a clock or transport event occurs.
class MidiClockState {
  /// The MIDI clock/transport event that produced this state update.
  final MidiClockEventType type;

  /// Current smoothed tempo in Beats Per Minute (BPM).
  final double bpm;

  /// Unsmoothed instantaneous BPM computed from the most recent `0xF8` interval.
  final double instantaneousBpm;

  /// Whether external MIDI transport is currently running (`true` after `0xFA`/`0xFB`, `false` after `0xFC`).
  final bool isRunning;

  /// Cumulative 24-PPQ MIDI clock tick count from the start of the sequence.
  final int clockTickCount;

  /// Creates an immutable [MidiClockState].
  const MidiClockState({
    required this.type,
    required this.bpm,
    required this.instantaneousBpm,
    required this.isRunning,
    required this.clockTickCount,
  });

  /// Musical position in quarter notes (`clockTickCount / 24.0`).
  double get ppqPosition => clockTickCount / kMidiClocksPerQuarterNote;

  /// Musical position in sixteenth notes / MIDI beats (`clockTickCount / 6.0`).
  double get sixteenthNotePosition => clockTickCount / 6.0;

  @override
  String toString() =>
      'MidiClockState($type, bpm: ${bpm.toStringAsFixed(2)}, '
      'running: $isRunning, ticks: $clockTickCount)';
}

/// Pure-Dart MIDI Clock Slave receiver for `0xF8` Timing Clock, `0xFA` Start,
/// `0xFB` Continue, `0xFC` Stop, and `0xF2` Song Position Pointer messages.
///
/// Uses an exponential moving average (with rapid initial lock warmup) to smooth
/// USB/BLE/OS timing jitter into a stable BPM estimate while tracking 24-PPQ
/// transport state and song position.
class MidiClockSlave {
  /// Minimum accepted BPM when clamping instantaneous clock intervals.
  final double minBpm;

  /// Maximum accepted BPM when clamping instantaneous clock intervals.
  final double maxBpm;

  /// Smoothing factor (`(0.0, 1.0]`) applied to BPM updates after initial lock.
  /// Lower values reject more jitter; `1.0` disables smoothing.
  final double smoothing;

  /// Maximum inter-clock gap in microseconds before resetting the clock interval
  /// estimator (prevents stalls/pauses from producing artificially low BPMs).
  final int dropoutResetThresholdUs;

  /// Optional callback invoked on every clock, transport, or SPP state update.
  final void Function(MidiClockState state)? onStateChanged;

  /// Optional callback invoked whenever smoothed [bpm] is recalculated from `0xF8`.
  final void Function(double bpm)? onBpmChanged;

  /// Optional callback invoked on `0xFA`, `0xFB`, `0xFC`, or `0xF2` transport events.
  final void Function(MidiClockEventType transportType, int clockTickCount)?
  onTransportChanged;

  final Stopwatch _stopwatch = Stopwatch();
  final StreamController<MidiClockState> _stateController =
      StreamController<MidiClockState>.broadcast();

  double _bpm;
  double _instantaneousBpm;
  bool _isRunning = false;
  int _clockTickCount = 0;

  int? _lastClockTimestampUs;
  int _intervalCount = 0;
  double _warmupSumIntervalUs = 0.0;
  double? _smoothedIntervalUs;

  int _awaitingSppBytes = 0;
  int? _sppLsb;
  bool _disposed = false;

  /// Creates a [MidiClockSlave].
  MidiClockSlave({
    double initialBpm = 120.0,
    this.minBpm = 20.0,
    this.maxBpm = 300.0,
    double smoothing = 0.15,
    this.dropoutResetThresholdUs = 1500000,
    this.onStateChanged,
    this.onBpmChanged,
    this.onTransportChanged,
  }) : assert(minBpm > 0 && maxBpm >= minBpm),
       smoothing = smoothing.clamp(0.001, 1.0).toDouble(),
       _bpm = initialBpm.clamp(minBpm, maxBpm).toDouble(),
       _instantaneousBpm = initialBpm.clamp(minBpm, maxBpm).toDouble();

  /// Current smoothed tempo estimate in Beats Per Minute (BPM).
  double get bpm => _bpm;

  /// Latest raw instantaneous BPM computed before smoothing.
  double get instantaneousBpm => _instantaneousBpm;

  /// Whether external MIDI transport is currently running.
  bool get isRunning => _isRunning;

  /// Cumulative 24-PPQ MIDI clock tick count from the sequence origin.
  int get clockTickCount => _clockTickCount;

  /// Current musical position in quarter notes (`clockTickCount / 24.0`).
  double get ppqPosition => _clockTickCount / kMidiClocksPerQuarterNote;

  /// Broadcast stream of [MidiClockState] snapshots.
  Stream<MidiClockState> get stateStream => _stateController.stream;

  /// Feeds a single raw MIDI byte (for example from a MIDI-in plugin).
  ///
  /// If [timestampUs] is omitted, an internal monotonic [Stopwatch] is used.
  /// Per the MIDI 1.0 specification, System Real-Time bytes (`0xF8..0xFF`) may
  /// be interleaved inside multi-byte messages (such as `0xF2`) without
  /// disrupting data byte collection.
  void feedByte(int byte, {int? timestampUs}) {
    if (_disposed) return;

    final b = byte & 0xFF;

    // System Real-Time messages (0xF8..0xFF) can arrive at any time, even inside
    // multi-byte System Common / Channel messages, without cancelling them.
    if (b >= 0xF8) {
      switch (b) {
        case kMidiTimingClock:
          _handleClockPulse(timestampUs);
        case kMidiStart:
          _isRunning = true;
          _clockTickCount = 0;
          _resetEstimatorWarmup();
          _emit(MidiClockEventType.start, notifyTransport: true);
        case kMidiContinue:
          _isRunning = true;
          _resetEstimatorWarmup();
          _emit(MidiClockEventType.continuePlayback, notifyTransport: true);
        case kMidiStop:
          _isRunning = false;
          _lastClockTimestampUs = null;
          _emit(MidiClockEventType.stop, notifyTransport: true);
        default:
          // Ignore Active Sensing (0xFE), System Reset (0xFF), etc.
          break;
      }
      return;
    }

    // Any non-realtime status byte resets any in-flight Song Position Pointer.
    if (b >= 0x80) {
      if (b == kMidiSongPositionPointer) {
        _awaitingSppBytes = 2;
        _sppLsb = null;
      } else {
        _awaitingSppBytes = 0;
        _sppLsb = null;
      }
      return;
    }

    // Data byte (0x00..0x7F) for pending Song Position Pointer (`0xF2 lsb msb`).
    if (_awaitingSppBytes == 2) {
      _sppLsb = b;
      _awaitingSppBytes = 1;
    } else if (_awaitingSppBytes == 1) {
      final midiBeats = ((b & 0x7F) << 7) | ((_sppLsb ?? 0) & 0x7F);
      _awaitingSppBytes = 0;
      _sppLsb = null;
      // Each MIDI beat in SPP equals 6 MIDI clocks (one 16th note).
      _clockTickCount = midiBeats * 6;
      _emit(MidiClockEventType.songPosition, notifyTransport: true);
    }
  }

  /// Feeds a sequence of raw MIDI bytes (for example a packet from a MIDI input port).
  void feedBytes(Iterable<int> bytes, {int? timestampUs}) {
    for (final byte in bytes) {
      feedByte(byte, timestampUs: timestampUs);
    }
  }

  void _handleClockPulse(int? timestampUs) {
    final ts = timestampUs ?? (_stopwatch..start()).elapsedMicroseconds;

    if (_lastClockTimestampUs != null) {
      final deltaUs = ts - _lastClockTimestampUs!;
      if (deltaUs > 0 && deltaUs <= dropoutResetThresholdUs) {
        final rawBpm = 60000000.0 / (deltaUs * kMidiClocksPerQuarterNote);
        _instantaneousBpm = rawBpm.clamp(minBpm, maxBpm).toDouble();

        // Smooth inter-clock period in microseconds first to avoid Jensen's
        // inequality bias (1/t) under symmetric timing jitter.
        final minIntervalUs = 60000000.0 / (maxBpm * kMidiClocksPerQuarterNote);
        final maxIntervalUs = 60000000.0 / (minBpm * kMidiClocksPerQuarterNote);
        final clampedIntervalUs =
            deltaUs.toDouble().clamp(minIntervalUs, maxIntervalUs).toDouble();

        if (_intervalCount < 3) {
          _warmupSumIntervalUs += clampedIntervalUs;
          _smoothedIntervalUs = _warmupSumIntervalUs / (_intervalCount + 1);
        } else {
          final prev = _smoothedIntervalUs ?? clampedIntervalUs;
          _smoothedIntervalUs = prev + smoothing * (clampedIntervalUs - prev);
        }
        _bpm = (60000000.0 / (_smoothedIntervalUs! * kMidiClocksPerQuarterNote))
            .clamp(minBpm, maxBpm)
            .toDouble();
        _intervalCount++;
        onBpmChanged?.call(_bpm);
      } else if (deltaUs > dropoutResetThresholdUs) {
        _intervalCount = 0;
        _warmupSumIntervalUs = 0.0;
        _smoothedIntervalUs = null;
      }
    }

    _lastClockTimestampUs = ts;
    if (_isRunning) {
      _clockTickCount++;
    }
    _emit(MidiClockEventType.clock);
  }

  void _resetEstimatorWarmup() {
    _lastClockTimestampUs = null;
    _intervalCount = 0;
    _warmupSumIntervalUs = 0.0;
    _smoothedIntervalUs = null;
  }

  void _emit(MidiClockEventType type, {bool notifyTransport = false}) {
    if (notifyTransport) {
      onTransportChanged?.call(type, _clockTickCount);
    }
    final state = MidiClockState(
      type: type,
      bpm: _bpm,
      instantaneousBpm: _instantaneousBpm,
      isRunning: _isRunning,
      clockTickCount: _clockTickCount,
    );
    onStateChanged?.call(state);
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  /// Resets transport running state, tick counter, and interval estimator.
  void reset({double? bpm}) {
    _isRunning = false;
    _clockTickCount = 0;
    _awaitingSppBytes = 0;
    _sppLsb = null;
    _resetEstimatorWarmup();
    if (bpm != null) {
      final clamped = bpm.clamp(minBpm, maxBpm).toDouble();
      _bpm = clamped;
      _instantaneousBpm = clamped;
    }
  }

  /// Releases resources and closes [stateStream].
  Future<void> dispose() async {
    _disposed = true;
    await _stateController.close();
  }
}

/// Software simulator that acts as an external MIDI Clock master device,
/// generating `0xFA`, `0xF8` (24 PPQ), `0xFB`, `0xFC`, and `0xF2` messages.
///
/// Useful for testing and demonstrating [MidiClockSlave] and `MidiPlayer` slave
/// sync without physical MIDI hardware.
class MidiClockSimulator {
  /// Callback invoked for each generated raw MIDI byte and its microsecond timestamp.
  final void Function(int byte, int timestampUs) onSendByte;

  /// Optional symmetric timing jitter amplitude in milliseconds (for testing PLL smoothing).
  final double jitterMs;

  final Stopwatch _stopwatch = Stopwatch();
  final math.Random _rng;
  Timer? _timer;

  double _bpm;
  int _pulseIntervalUs;
  int _nextPulseUs = 0;
  int _lastEmittedTs = -1;
  bool _isRunning = false;
  bool _disposed = false;

  /// Creates a [MidiClockSimulator] running at [bpm].
  MidiClockSimulator({
    required this.onSendByte,
    double bpm = 120.0,
    this.jitterMs = 0.0,
    int? randomSeed,
  }) : _rng = math.Random(randomSeed),
       _bpm = bpm.clamp(20.0, 300.0).toDouble(),
       _pulseIntervalUs = _computeIntervalUs(bpm.clamp(20.0, 300.0).toDouble());

  static int _computeIntervalUs(double bpm) =>
      (60000000.0 / (bpm * kMidiClocksPerQuarterNote)).round();

  /// Current simulated master tempo in BPM.
  double get bpm => _bpm;

  /// Updates the simulated master tempo on the fly without resetting phase.
  set bpm(double value) {
    final clamped = value.clamp(20.0, 300.0).toDouble();
    _bpm = clamped;
    _pulseIntervalUs = _computeIntervalUs(clamped);
    if (_isRunning) {
      final nowUs = _stopwatch.elapsedMicroseconds;
      if (_nextPulseUs > nowUs + _pulseIntervalUs) {
        _nextPulseUs = nowUs + _pulseIntervalUs;
      }
    }
  }

  /// Whether the simulated clock is actively emitting `0xF8` pulses.
  bool get isRunning => _isRunning;

  /// Sends `0xFA` (Start) and starts emitting 24-PPQ `0xF8` timing clock pulses.
  void start() {
    if (_disposed) return;
    _stopwatch
      ..reset()
      ..start();
    _lastEmittedTs = -1;
    _isRunning = true;
    _sendNow(kMidiStart, applyJitter: false);
    _nextPulseUs = 0;
    _startTimer();
  }

  /// Sends `0xFB` (Continue) and resumes emitting `0xF8` timing clock pulses.
  void continuePlayback() {
    if (_disposed) return;
    if (!_stopwatch.isRunning) {
      _stopwatch.start();
    }
    _isRunning = true;
    _sendNow(kMidiContinue, applyJitter: false);
    _nextPulseUs = _stopwatch.elapsedMicroseconds;
    _startTimer();
  }

  /// Stops emitting `0xF8` pulses and sends `0xFC` (Stop).
  void stop() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    if (_isRunning) {
      _isRunning = false;
      _sendNow(kMidiStop, applyJitter: false);
    }
  }

  /// Sends a 3-byte `0xF2` Song Position Pointer for [sixteenthNotes] MIDI beats.
  void sendSongPosition(int sixteenthNotes) {
    if (_disposed) return;
    final clamped = sixteenthNotes.clamp(0, 16383);
    final lsb = clamped & 0x7F;
    final msb = (clamped >> 7) & 0x7F;
    _sendNow(kMidiSongPositionPointer, applyJitter: false);
    _sendNow(lsb, applyJitter: false);
    _sendNow(msb, applyJitter: false);
  }

  void _startTimer() {
    _timer?.cancel();
    _onTimerTick();
    _timer = Timer.periodic(
      const Duration(milliseconds: 2),
      (_) => _onTimerTick(),
    );
  }

  void _onTimerTick() {
    if (!_isRunning || _disposed) return;
    final nowUs = _stopwatch.elapsedMicroseconds;
    var emitted = 0;
    while (_nextPulseUs <= nowUs && emitted < 4) {
      _sendNow(kMidiTimingClock, applyJitter: jitterMs > 0);
      _nextPulseUs += _pulseIntervalUs;
      emitted++;
    }
    if (_nextPulseUs <= nowUs) {
      _nextPulseUs = nowUs + _pulseIntervalUs;
    }
  }

  void _sendNow(int byte, {required bool applyJitter}) {
    if (!_stopwatch.isRunning) {
      _stopwatch.start();
    }
    final rawTs = _stopwatch.elapsedMicroseconds;
    final jitterUs = applyJitter
        ? ((_rng.nextDouble() * 2.0 - 1.0) * jitterMs * 1000.0).round()
        : 0;
    final ts = math.max(_lastEmittedTs + 1, math.max(0, rawTs + jitterUs));
    _lastEmittedTs = ts;
    onSendByte(byte, ts);
  }

  /// Stops the simulator timer and releases resources.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _stopwatch.stop();
  }
}
