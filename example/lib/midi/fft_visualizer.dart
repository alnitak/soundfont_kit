import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Real-time FFT audio visualizer widget using a [CustomPainter] with gradient-colored bars.
class FftVisualizerWidget extends StatefulWidget {
  const FftVisualizerWidget({
    super.key,
    required this.isPlaying,
    this.barCount = 32,
  });

  final bool isPlaying;
  final int barCount;

  @override
  State<FftVisualizerWidget> createState() => _FftVisualizerWidgetState();
}

class _FftVisualizerWidgetState extends State<FftVisualizerWidget> {
  StreamSubscription<AudioVisualizationData>? _sub;
  late List<double> _bars;
  Timer? _decayTimer;

  @override
  void initState() {
    super.initState();
    _bars = List<double>.filled(widget.barCount, 0.0);
    _ensureVisualization();
    _sub = SoLoud.instance.audioVisualizationEvents.listen(_onAudioData);
  }

  void _ensureVisualization() {
    if (SoLoud.instance.isInitialized) {
      try {
        SoLoud.instance.setVisualizationEnabled(
          true,
          windowSize: 256,
          kind: VisualizationKind.fft,
          channel: VisualizationChannel.merged,
        );
        SoLoud.instance.setFftSmoothing(0.8);
      } catch (_) {}
    }
  }

  void _onAudioData(AudioVisualizationData data) {
    if (!mounted) return;
    final raw = data.fftData;
    if (raw == null || raw.isEmpty) return;

    final n = raw.length;
    final count = widget.barCount;
    final updated = List<double>.filled(count, 0.0);

    for (int i = 0; i < count; i++) {
      final t0 = math.pow(i / count, 2.0);
      final t1 = math.pow((i + 1) / count, 2.0);
      final startBin = (t0 * (n - 1)).floor().clamp(0, n - 1);
      final endBin = (t1 * (n - 1)).ceil().clamp(startBin + 1, n);

      double sum = 0.0;
      int binCount = 0;
      for (int b = startBin; b < endBin; b++) {
        sum += raw[b];
        binCount++;
      }
      final avg = binCount > 0 ? sum / binCount : raw[startBin];
      // Frequency boost: higher frequencies carry less energy, compensate smoothly
      final boost = 1.0 + (i / count) * 2.5;
      updated[i] = (avg * boost).clamp(0.0, 1.0);
    }

    setState(() {
      _bars = updated;
    });
  }

  @override
  void didUpdateWidget(covariant FftVisualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isPlaying && oldWidget.isPlaying) {
      _startDecay();
    }
  }

  void _startDecay() {
    _decayTimer?.cancel();
    _decayTimer = Timer.periodic(const Duration(milliseconds: 25), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      bool allZero = true;
      for (int i = 0; i < _bars.length; i++) {
        _bars[i] *= 0.82;
        if (_bars[i] > 0.005) {
          allZero = false;
        } else {
          _bars[i] = 0.0;
        }
      }
      if (allZero) {
        timer.cancel();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _decayTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
      child: CustomPaint(
        painter: _FftVisualizerPainter(bars: _bars),
        size: Size.infinite,
      ),
    );
  }
}

/// CustomPainter for FFT visualizer bars shaded with a gradient.
class _FftVisualizerPainter extends CustomPainter {
  _FftVisualizerPainter({required this.bars});

  final List<double> bars;

  static const Gradient _gradient = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      Color(0xFF6C63FF), // deep purple base
      Color(0xFF00E5FF), // cyan mid
      Color(0xFFFF2A85), // vivid pink peak
    ],
    stops: [0.0, 0.55, 1.0],
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    final count = bars.length;
    const spacing = 2.0;
    final totalSpacing = (count - 1) * spacing;
    final barWidth = (size.width - totalSpacing) / count;
    if (barWidth <= 0) return;

    final rect = Offset.zero & size;
    final activePaint = Paint()
      ..shader = _gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    final restingPaint = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    const minBarHeight = 1.5;
    final maxBarHeight = size.height;

    for (int i = 0; i < count; i++) {
      final x = i * (barWidth + spacing);
      final magnitude = bars[i].clamp(0.0, 1.0);

      if (magnitude > 0.01) {
        final h = magnitude * (maxBarHeight - minBarHeight) + minBarHeight;
        final y = size.height - h;
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, h),
          const Radius.circular(1.5),
        );
        canvas.drawRRect(rrect, activePaint);
      } else {
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - minBarHeight, barWidth, minBarHeight),
          const Radius.circular(1.5),
        );
        canvas.drawRRect(rrect, restingPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FftVisualizerPainter oldDelegate) {
    return true;
  }
}
