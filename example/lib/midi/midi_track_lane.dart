import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soundfont_kit/soundfont_kit.dart';

import 'midi_roll_painters.dart';

/// Single track lane widget along the DAW timeline displaying notes inside a clip container.
class MidiTrackLane extends StatelessWidget {
  const MidiTrackLane({
    super.key,
    required this.chIndex,
    required this.timelineWidth,
    required this.zoom,
    required this.notes,
    required this.instrumentName,
    required this.onSeek,
    this.trackHeight = 72.0,
  });

  final int chIndex;
  final double timelineWidth;
  final double zoom;
  final double trackHeight;
  final List<MidiTimelineNote> notes;
  final String instrumentName;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        onSeek(details.localPosition.dx / zoom);
      },
      child: Container(
        height: trackHeight,
        width: timelineWidth,
        decoration: const BoxDecoration(
          color: Color(0xFF13151B),
          border: Border(bottom: BorderSide(color: Colors.white10, width: 1)),
        ),
        child: Stack(
          children: [
            // Subtle beat grid
            Positioned.fill(
              child: CustomPaint(painter: LaneGridPainter(zoom: zoom)),
            ),
            // MIDI Clip region (DAW green container)
            if (notes.isNotEmpty) ...[
              Builder(
                builder: (context) {
                  final firstNote = notes.first;
                  final lastNote = notes.reduce(
                    (a, b) => a.end > b.end ? a : b,
                  );
                  final clipStartSec =
                      firstNote.start.inMicroseconds / 1000000.0;
                  final clipEndSec = lastNote.end.inMicroseconds / 1000000.0;
                  final clipLeft = clipStartSec * zoom;
                  final clipWidth = math.max(
                    20.0,
                    (clipEndSec - clipStartSec) * zoom,
                  );

                  return Positioned(
                    left: clipLeft - 1.0,
                    width: clipWidth + 2.0,
                    top: 5,
                    bottom: 5,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF163E20), // Dark green DAW clip
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF2E8540),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Top clip title bar
                          Container(
                            height: 14,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            color: const Color(0xFF236830),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '$instrumentName - CH ${chIndex + 1}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFC8E6C9),
                              ),
                            ),
                          ),
                          // Notes area rendered with shared CustomPainter
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: CustomPaint(
                                size: Size.infinite,
                                painter: MidiNotesCustomPainter(
                                  notes: notes,
                                  clipStart: firstNote.start,
                                  clipDuration: lastNote.end - firstNote.start,
                                  noteColor: const Color(0xFFE8F5E9),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
