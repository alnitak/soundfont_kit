import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soundfont_kit/soundfont_kit.dart';

/// A shared [CustomPainter] that renders MIDI notes as horizontal bars inside a track lane clip.
class MidiNotesCustomPainter extends CustomPainter {
  const MidiNotesCustomPainter({
    required this.notes,
    required this.clipStart,
    required this.clipDuration,
    this.noteColor = Colors.white,
  });

  final List<MidiTimelineNote> notes;
  final Duration clipStart;
  final Duration clipDuration;
  final Color noteColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty || size.width <= 0 || size.height <= 0) return;

    var minPitch = 127;
    var maxPitch = 0;
    for (final n in notes) {
      if (n.note < minPitch) minPitch = n.note;
      if (n.note > maxPitch) maxPitch = n.note;
    }
    if (minPitch > maxPitch) return;

    // Minimum span of 12 semitones (one octave) to maintain visual proportions
    final span = math.max(12, maxPitch - minPitch + 1);
    final clipDurUs = math.max(1, clipDuration.inMicroseconds);
    final clipStartUs = clipStart.inMicroseconds;

    final paint = Paint()..style = PaintingStyle.fill;

    for (final n in notes) {
      final startOffsetUs = n.start.inMicroseconds - clipStartUs;
      final durUs = n.duration.inMicroseconds;

      final x = (startOffsetUs / clipDurUs) * size.width;
      final w = math.max(2.0, (durUs / clipDurUs) * size.width) - 1;

      // Pitch mapping: higher notes near top, lower notes near bottom
      final normalizedPitch = (n.note - minPitch) / span;
      final y = size.height - (normalizedPitch * (size.height - 4.0)) - 4.0;
      final h = math.max(2.0, size.height / span).clamp(2.0, 5.0);

      // Velocity modulates opacity
      final alpha = (0.5 + 0.5 * (n.velocity / 127.0)).clamp(0.4, 1.0);
      paint.color = noteColor.withValues(alpha: alpha);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          const Radius.circular(1.0),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MidiNotesCustomPainter oldDelegate) {
    return oldDelegate.notes != notes ||
        oldDelegate.clipStart != clipStart ||
        oldDelegate.clipDuration != clipDuration ||
        oldDelegate.noteColor != noteColor;
  }
}

/// CustomPainter for rendering time increments and labels along the top ruler.
class TimeRulerPainter extends CustomPainter {
  const TimeRulerPainter({
    required this.zoom,
    required this.totalDurationSeconds,
  });

  final double zoom;
  final double totalDurationSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = const Color.fromARGB(60, 249, 2, 2)
      ..strokeWidth = 1.0;
    final majorTickPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.0;

    // Major and minor intervals based on zoom
    final majorIntervalSec = zoom >= 60 ? 5 : (zoom >= 30 ? 10 : 20);
    final minorIntervalSec = zoom >= 60 ? 1 : (zoom >= 30 ? 2 : 5);

    final totalSec = totalDurationSeconds.ceil();

    const textStyle = TextStyle(
      color: Colors.white60,
      fontSize: 9,
      fontFamily: 'monospace',
    );

    for (int s = 0; s <= totalSec; s += minorIntervalSec) {
      final x = s * zoom;
      if (x > size.width) break;

      final isMajor = s % majorIntervalSec == 0;
      if (isMajor) {
        canvas.drawLine(
          Offset(x, size.height - 10),
          Offset(x, size.height),
          majorTickPaint,
        );

        final mins = s ~/ 60;
        final secs = s % 60;
        final label = '$mins:${secs.toString().padLeft(2, "0")}';

        final tp =
            TextPainter(
                text: const TextSpan(text: '', style: textStyle),
                textDirection: TextDirection.ltr,
              )
              ..text = TextSpan(text: label, style: textStyle)
              ..layout();
        tp.paint(canvas, Offset(x + 3, 3));
      } else {
        canvas.drawLine(
          Offset(x, size.height - 5),
          Offset(x, size.height),
          tickPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant TimeRulerPainter oldDelegate) {
    return oldDelegate.zoom != zoom ||
        oldDelegate.totalDurationSeconds != totalDurationSeconds;
  }
}

/// CustomPainter for rendering vertical grid lines across track lanes.
class LaneGridPainter extends CustomPainter {
  const LaneGridPainter({required this.zoom});

  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1.0;

    final intervalSec = zoom >= 40 ? 5 : 10;
    final totalSec = (size.width / zoom).ceil();

    for (int s = 0; s <= totalSec; s += intervalSec) {
      final x = s * zoom;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant LaneGridPainter oldDelegate) {
    return oldDelegate.zoom != zoom;
  }
}

/// CustomPainter for rendering the playhead vertical line and top marker.
class PlayheadPainter extends CustomPainter {
  const PlayheadPainter({required this.x});

  final double x;

  @override
  void paint(Canvas canvas, Size size) {
    if (x < -10 || x > size.width + 10) return;

    final linePaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 1.5;

    // Vertical line
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

    // Playhead downward triangle at the top
    final headPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(x - 5, 0)
      ..lineTo(x + 5, 0)
      ..lineTo(x, 7)
      ..close();
    canvas.drawPath(path, headPaint);
  }

  @override
  bool shouldRepaint(covariant PlayheadPainter oldDelegate) {
    return oldDelegate.x != x;
  }
}
