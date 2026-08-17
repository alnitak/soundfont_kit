import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:soundfont_reader/soundfont_reader.dart';

/// A widget that displays the audio waveform for a [SampleInfo] from a [SoundFontFile],
/// reading the audio data using `SoLoud.instance.readSamplesFromMem` or `readSamplesFromFile`.
class SampleWaveform extends StatefulWidget {
  final SoundFontFile soundFont;
  final SampleInfo sample;
  final SoundFontPlayer? player;
  final double width;
  final double height;
  final Color? waveColor;
  final Color? backgroundColor;

  const SampleWaveform({
    super.key,
    required this.soundFont,
    required this.sample,
    this.player,
    this.width = 140,
    this.height = 36,
    this.waveColor,
    this.backgroundColor,
  });

  @override
  State<SampleWaveform> createState() => _SampleWaveformState();
}

class _SampleWaveformState extends State<SampleWaveform>
    with SingleTickerProviderStateMixin {
  static final Map<String, Float32List> _cache = {};

  Float32List? _samples;
  bool _isLoading = false;
  String? _cacheKey;
  late final Ticker _ticker;
  final ValueNotifier<double?> _playheadNotifier = ValueNotifier<double?>(null);

  @override
  void initState() {
    super.initState();
    _loadWaveform();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _playheadNotifier.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!mounted || !SoLoud.instance.isInitialized) return;

    final player = widget.player;
    SoundHandle? activeHandle;

    if (player != null) {
      final handles = player.getActiveHandlesForSample(widget.sample);
      if (handles.isNotEmpty) {
        activeHandle = handles.last;
      }
    }

    if (activeHandle != null &&
        SoLoud.instance.getIsValidVoiceHandle(activeHandle)) {
      try {
        final pos = SoLoud.instance.getPosition(activeHandle);
        final sampleCount = widget.sample.sampleCount > 0
            ? widget.sample.sampleCount
            : (widget.sample.byteLength > 0 ? widget.sample.byteLength ~/ 2 : 0);
        final sampleRate = widget.sample.sampleRate > 0
            ? widget.sample.sampleRate
            : 44100;
        final totalMicros = (sampleCount / sampleRate * 1000000).toInt();

        if (totalMicros > 0) {
          final progress =
              (pos.inMicroseconds / totalMicros).clamp(0.0, 1.0);
          if (_playheadNotifier.value != progress) {
            _playheadNotifier.value = progress;
          }
          return;
        }
      } catch (_) {}
    }

    if (_playheadNotifier.value != null) {
      _playheadNotifier.value = null;
    }
  }

  @override
  void didUpdateWidget(SampleWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sample.id != widget.sample.id ||
        oldWidget.sample.samplePath != widget.sample.samplePath ||
        oldWidget.soundFont != widget.soundFont ||
        oldWidget.width != widget.width) {
      _loadWaveform();
    }
  }

  String get _currentKey =>
      '${widget.soundFont.name ?? ""}_${widget.sample.id}_${widget.sample.samplePath ?? ""}_${widget.width.toInt()}';

  Future<void> _loadWaveform() async {
    final key = _currentKey;
    _cacheKey = key;

    if (_cache.containsKey(key)) {
      setState(() {
        _samples = _cache[key];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _samples = null;
    });

    try {
      final numSamplesNeeded = widget.width.toInt().clamp(10, 2000);
      Float32List? data;

      // 1. Try reading directly from file if local path exists on non-web
      if (!kIsWeb &&
          widget.sample.samplePath != null &&
          widget.sample.samplePath!.isNotEmpty) {
        final path = widget.sample.samplePath!;
        if (File(path).existsSync()) {
          try {
            final decoded = await SoLoud.instance.readSamplesFromFile(
              path,
              numSamplesNeeded,
              average: false,
            );
            if (decoded.isNotEmpty) {
              data = Float32List.fromList(decoded);
            }
          } catch (_) {
            data = null;
          }
        }
      }

      // 2. Otherwise read from sample byte buffer
      if (data == null) {
        final rawBytes = await widget.soundFont.getSampleBytes(widget.sample);
        if (rawBytes.isNotEmpty) {
          final isPcm = switch (widget.sample.compression) {
            SampleCompression.pcm8 ||
            SampleCompression.pcm16 ||
            SampleCompression.pcm24 ||
            SampleCompression.pcm32 ||
            SampleCompression.pcmFloat32 => true,
            _ => false,
          };

          if (isPcm) {
            // Fast, pure Dart downsampling with zero FFI / WASM heap sharing issues
            data = _extractPcmWaveform(
              rawBytes,
              widget.sample.compression,
              widget.sample.channels,
              numSamplesNeeded,
            );
          } else {
            // For OGG, FLAC, WAV compressed formats, decode via SoLoud
            final decoded = await SoLoud.instance.readSamplesFromMem(
              rawBytes,
              numSamplesNeeded,
              average: false,
            );
            if (decoded.isNotEmpty) {
              // Explicitly clone from WASM linear memory into Dart GC heap
              data = Float32List.fromList(decoded);
            }
          }
        }
      }

      if (_cacheKey == key && mounted) {
        if (data != null && data.isNotEmpty) {
          _cache[key] = data;
        }
        setState(() {
          _samples = data;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (_cacheKey == key && mounted) {
        setState(() {
          _isLoading = false;
          _samples = Float32List(0);
        });
      }
    }
  }

  /// High-performance pure Dart downsampler for PCM audio data.
  /// Bypasses FFI/WASM linear memory entirely to ensure 100% stable rendering across web and desktop.
  static Float32List _extractPcmWaveform(
    Uint8List rawBytes,
    SampleCompression compression,
    int channels,
    int numPoints,
  ) {
    if (rawBytes.isEmpty || numPoints <= 0) return Float32List(0);

    final numChannels = channels > 0 ? channels : 1;
    final ByteData byteData = ByteData.sublistView(rawBytes);

    switch (compression) {
      case SampleCompression.pcm16:
        final totalSamples = rawBytes.lengthInBytes ~/ (2 * numChannels);
        if (totalSamples <= 0) return Float32List(0);

        final result = Float32List(numPoints);
        final samplesPerPoint = totalSamples / numPoints;

        for (int p = 0; p < numPoints; p++) {
          final start = (p * samplesPerPoint).toInt();
          final end = ((p + 1) * samplesPerPoint).toInt().clamp(start + 1, totalSamples);
          double maxAmp = 0.0;

          for (int s = start; s < end; s++) {
            final byteOffset = s * 2 * numChannels;
            if (byteOffset + 1 < rawBytes.lengthInBytes) {
              final val = byteData.getInt16(byteOffset, Endian.little).abs() / 32768.0;
              if (val > maxAmp) maxAmp = val;
            }
          }
          result[p] = maxAmp;
        }
        return result;

      case SampleCompression.pcm8:
        final totalSamples = rawBytes.lengthInBytes ~/ numChannels;
        if (totalSamples <= 0) return Float32List(0);

        final result = Float32List(numPoints);
        final samplesPerPoint = totalSamples / numPoints;

        for (int p = 0; p < numPoints; p++) {
          final start = (p * samplesPerPoint).toInt();
          final end = ((p + 1) * samplesPerPoint).toInt().clamp(start + 1, totalSamples);
          double maxAmp = 0.0;

          for (int s = start; s < end; s++) {
            final byteOffset = s * numChannels;
            if (byteOffset < rawBytes.lengthInBytes) {
              final val = (rawBytes[byteOffset] - 128).abs() / 128.0;
              if (val > maxAmp) maxAmp = val;
            }
          }
          result[p] = maxAmp;
        }
        return result;

      case SampleCompression.pcmFloat32:
        final totalSamples = rawBytes.lengthInBytes ~/ (4 * numChannels);
        if (totalSamples <= 0) return Float32List(0);

        final result = Float32List(numPoints);
        final samplesPerPoint = totalSamples / numPoints;

        for (int p = 0; p < numPoints; p++) {
          final start = (p * samplesPerPoint).toInt();
          final end = ((p + 1) * samplesPerPoint).toInt().clamp(start + 1, totalSamples);
          double maxAmp = 0.0;

          for (int s = start; s < end; s++) {
            final byteOffset = s * 4 * numChannels;
            if (byteOffset + 3 < rawBytes.lengthInBytes) {
              final val = byteData.getFloat32(byteOffset, Endian.little).abs();
              if (val > maxAmp) maxAmp = val;
            }
          }
          result[p] = maxAmp;
        }
        return result;

      default:
        return Float32List(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waveColor = widget.waveColor ?? theme.colorScheme.primary;
    final bgColor =
        widget.backgroundColor ??
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _isLoading
          ? Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: waveColor.withValues(alpha: 0.6),
                ),
              ),
            )
          : CustomPaint(
              size: Size(widget.width, widget.height),
              painter: _WaveformPainter(
                samples: _samples ?? Float32List(0),
                color: waveColor,
                sample: widget.sample,
              ),
              foregroundPainter: _PlayheadPainter(
                notifier: _playheadNotifier,
              ),
            ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Float32List samples;
  final Color color;
  final SampleInfo sample;

  const _WaveformPainter({
    required this.samples,
    required this.color,
    required this.sample,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    // Draw center zero-crossing baseline
    final basePaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), basePaint);

    if (samples.isNotEmpty) {
      // Find peak amplitude for normalization
      double peak = 0.0;
      for (int i = 0; i < samples.length; i++) {
        final absVal = samples[i].abs();
        if (absVal > peak) peak = absVal;
      }

      final scale = peak > 0.001 ? (1.0 / peak) : 1.0;

      final paint = Paint()
        ..color = color
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = (size.width / samples.length).clamp(1.0, 3.0);

      final stepX = size.width / (samples.length > 1 ? samples.length - 1 : 1);

      for (int i = 0; i < samples.length; i++) {
        final x = i * stepX;
        final normalizedAmp = (samples[i].abs() * scale).clamp(0.0, 1.0);
        final halfHeight = normalizedAmp * (size.height / 2 - 2);

        if (halfHeight > 0.5) {
          canvas.drawLine(
            Offset(x, centerY - halfHeight),
            Offset(x, centerY + halfHeight),
            paint,
          );
        }
      }
    }

    // Draw 1px yellow vertical lines for loop start and loop end positions
    if (sample.loopEnd > sample.loopStart) {
      final totalFrames = sample.sampleCount > 0
          ? sample.sampleCount
          : (sample.loopEnd > 0 ? sample.loopEnd : 0);

      if (totalFrames > 0) {
        final startX = (sample.loopStart / totalFrames * size.width).clamp(
          0.0,
          size.width,
        );
        final endX = (sample.loopEnd / totalFrames * size.width).clamp(
          0.0,
          size.width,
        );

        final loopPaint = Paint()
          ..color = Colors.yellow
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

        canvas.drawLine(
          Offset(startX, 0),
          Offset(startX, size.height),
          loopPaint,
        );

        canvas.drawLine(Offset(endX, 0), Offset(endX, size.height), loopPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.color != color ||
        oldDelegate.sample.loopStart != sample.loopStart ||
        oldDelegate.sample.loopEnd != sample.loopEnd ||
        oldDelegate.sample.sampleCount != sample.sampleCount;
  }
}

/// A dedicated painter that draws only the animated red playhead line on top of the waveform.
/// Uses [Listenable] repaint notifications so widget rebuilds and waveform recalculations are skipped.
class _PlayheadPainter extends CustomPainter {
  final ValueNotifier<double?> notifier;

  _PlayheadPainter({required this.notifier}) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    final progress = notifier.value;
    if (progress == null) return;

    final playheadX = (progress * size.width).clamp(0.0, size.width);
    final playheadPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      playheadPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter oldDelegate) {
    return oldDelegate.notifier != notifier;
  }
}
