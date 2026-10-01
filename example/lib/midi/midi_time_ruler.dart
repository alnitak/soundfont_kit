import 'package:flutter/material.dart';

import 'midi_roll_painters.dart';

/// Top horizontal time ruler with clickable/draggable seek scrubbing.
class MidiTimeRuler extends StatelessWidget {
  const MidiTimeRuler({
    super.key,
    required this.totalDurationSeconds,
    required this.timelineWidth,
    required this.zoom,
    required this.onSeek,
    this.rulerHeight = 28.0,
  });

  final double totalDurationSeconds;
  final double timelineWidth;
  final double zoom;
  final double rulerHeight;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        onSeek(details.localPosition.dx / zoom);
      },
      onHorizontalDragUpdate: (details) {
        onSeek(details.localPosition.dx / zoom);
      },
      child: Container(
        height: rulerHeight,
        width: timelineWidth,
        color: const Color(0xFF181B24),
        child: CustomPaint(
          size: Size(timelineWidth, rulerHeight),
          painter: TimeRulerPainter(
            zoom: zoom,
            totalDurationSeconds: totalDurationSeconds,
          ),
        ),
      ),
    );
  }
}
