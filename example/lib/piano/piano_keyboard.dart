import 'package:flutter/material.dart';

/// A chromatic piano keyboard widget that supports multitouch chords,
/// glissandos, and vertical touch position velocity sensitivity (top = soft, bottom = loud).
class PianoKeyboard extends StatefulWidget {
  /// Starting MIDI note number (e.g., 48 for C3, 60 for C4).
  final int startNote;

  /// Total number of keys to display (both white and black).
  final int keyCount;

  /// Callback when a note is pressed with calculated MIDI velocity (1..127).
  final void Function(int midiKey, int velocity) onNoteDown;

  /// Callback when a note is released.
  final void Function(int midiKey) onNoteUp;

  /// Set of MIDI keys currently highlighted / active.
  final Set<int> activeKeys;

  /// Optional set of MIDI keys that have active zones in the SoundFont.
  final Set<int>? availableKeys;

  /// Optional specific MIDI key to mark with a red circle at the bottom.
  final int? markedKey;

  /// Optional set of MIDI keys to mark with red circles at the bottom.
  final Set<int>? markedKeys;

  const PianoKeyboard({
    super.key,
    this.startNote = 48, // C3
    this.keyCount = 37, // ~3 octaves (C3 to C6)
    required this.onNoteDown,
    required this.onNoteUp,
    this.activeKeys = const {},
    this.availableKeys,
    this.markedKey,
    this.markedKeys,
  });

  @override
  State<PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends State<PianoKeyboard> {
  /// Maps pointer ID -> current MIDI note being played by that pointer.
  final Map<int, int> _pointerNotes = {};

  static const List<bool> _isBlackNoteInOctave = [
    false, // C
    true, // C#
    false, // D
    true, // D#
    false, // E
    false, // F
    true, // F#
    false, // G
    true, // G#
    false, // A
    true, // A#
    false, // B
  ];

  static const List<String> _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  static bool isBlackKey(int midiNote) {
    return _isBlackNoteInOctave[midiNote % 12];
  }

  static String getNoteName(int midiNote) {
    final name = _noteNames[midiNote % 12];
    final octave = (midiNote ~/ 12) - 1;
    return '$name$octave';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final totalWidth = constraints.maxWidth;

        // Count white keys in range
        final whiteKeyNotes = <int>[];
        for (int i = 0; i < widget.keyCount; i++) {
          final note = widget.startNote + i;
          if (!isBlackKey(note)) {
            whiteKeyNotes.add(note);
          }
        }

        if (whiteKeyNotes.isEmpty) return const SizedBox();

        final whiteKeyWidth = totalWidth / whiteKeyNotes.length;
        final blackKeyWidth = whiteKeyWidth * 0.62;
        final blackKeyHeight = totalHeight * 0.60;

        // Compute geometry for white and black keys
        final whiteKeyRects = <int, Rect>{};
        final blackKeyRects = <int, Rect>{};

        double currentWhiteX = 0;
        for (final note in whiteKeyNotes) {
          whiteKeyRects[note] = Rect.fromLTWH(
            currentWhiteX,
            0,
            whiteKeyWidth,
            totalHeight,
          );
          currentWhiteX += whiteKeyWidth;
        }

        for (int i = 0; i < widget.keyCount; i++) {
          final note = widget.startNote + i;
          if (isBlackKey(note)) {
            // Find preceding white key
            final prevWhite = note - 1;
            if (whiteKeyRects.containsKey(prevWhite)) {
              final prevRect = whiteKeyRects[prevWhite]!;
              final blackX = prevRect.right - (blackKeyWidth / 2);
              blackKeyRects[note] = Rect.fromLTWH(
                blackX,
                0,
                blackKeyWidth,
                blackKeyHeight,
              );
            }
          }
        }

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _handlePointerDown(
            event,
            whiteKeyRects,
            blackKeyRects,
            totalHeight,
            blackKeyHeight,
          ),
          onPointerMove: (event) => _handlePointerMove(
            event,
            whiteKeyRects,
            blackKeyRects,
            totalHeight,
            blackKeyHeight,
          ),
          onPointerUp: (event) => _handlePointerUp(event),
          onPointerCancel: (event) => _handlePointerUp(event),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // White keys background layer
              ...whiteKeyNotes.map((note) {
                final rect = whiteKeyRects[note]!;
                final isPressed = widget.activeKeys.contains(note) ||
                    _pointerNotes.values.contains(note);
                final hasZone = widget.availableKeys == null ||
                    widget.availableKeys!.contains(note);
                final isMarked = (widget.markedKey != null && widget.markedKey == note) ||
                    (widget.markedKeys != null && widget.markedKeys!.contains(note));

                return Positioned(
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.0),
                    decoration: BoxDecoration(
                      color: isPressed
                          ? Theme.of(context).colorScheme.primaryContainer
                          : (hasZone ? Colors.white : Colors.grey.shade300),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(5.0),
                      ),
                      border: Border.all(
                        color: Colors.black45,
                        width: 1.0,
                      ),
                      boxShadow: [
                        if (!isPressed)
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            offset: const Offset(0, 3),
                            blurRadius: 2,
                          ),
                      ],
                    ),
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.only(bottom: 3.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (note % 12 == 0)
                          Text(
                            getNoteName(note),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isPressed
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer
                                  : Colors.black54,
                            ),
                          ),
                        if (isMarked)
                          Container(
                            margin: const EdgeInsets.only(top: 1.0, bottom: 2.0),
                            width: 7.0,
                            height: 7.0,
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.5),
                                  blurRadius: 3,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),

              // Black keys foreground layer
              ...blackKeyRects.entries.map((entry) {
                final note = entry.key;
                final rect = entry.value;
                final isPressed = widget.activeKeys.contains(note) ||
                    _pointerNotes.values.contains(note);
                final hasZone = widget.availableKeys == null ||
                    widget.availableKeys!.contains(note);
                final isMarked = (widget.markedKey != null && widget.markedKey == note) ||
                    (widget.markedKeys != null && widget.markedKeys!.contains(note));

                return Positioned(
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isPressed
                          ? Theme.of(context).colorScheme.primary
                          : (hasZone
                              ? const Color(0xFF222222)
                              : const Color(0xFF555555)),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(4.0),
                      ),
                      border: Border.all(
                        color: isPressed
                            ? Theme.of(context).colorScheme.primary
                            : Colors.black87,
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          offset: const Offset(1, 2),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: isMarked
                        ? Container(
                            width: 6.0,
                            height: 6.0,
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.6),
                                  blurRadius: 3,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          )
                        : null,
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _handlePointerDown(
    PointerDownEvent event,
    Map<int, Rect> whiteRects,
    Map<int, Rect> blackRects,
    double totalHeight,
    double blackHeight,
  ) {
    final pos = event.localPosition;
    final noteInfo = _hitTest(pos, whiteRects, blackRects, totalHeight, blackHeight);
    if (noteInfo != null) {
      final note = noteInfo.note;
      final velocity = noteInfo.velocity;
      _pointerNotes[event.pointer] = note;
      widget.onNoteDown(note, velocity);
      setState(() {});
    }
  }

  void _handlePointerMove(
    PointerMoveEvent event,
    Map<int, Rect> whiteRects,
    Map<int, Rect> blackRects,
    double totalHeight,
    double blackHeight,
  ) {
    final pos = event.localPosition;
    final noteInfo = _hitTest(pos, whiteRects, blackRects, totalHeight, blackHeight);
    final previousNote = _pointerNotes[event.pointer];

    if (noteInfo == null) {
      if (previousNote != null) {
        _pointerNotes.remove(event.pointer);
        widget.onNoteUp(previousNote);
        setState(() {});
      }
    } else if (noteInfo.note != previousNote) {
      if (previousNote != null) {
        widget.onNoteUp(previousNote);
      }
      _pointerNotes[event.pointer] = noteInfo.note;
      widget.onNoteDown(noteInfo.note, noteInfo.velocity);
      setState(() {});
    }
  }

  void _handlePointerUp(PointerEvent event) {
    final note = _pointerNotes.remove(event.pointer);
    if (note != null) {
      widget.onNoteUp(note);
      setState(() {});
    }
  }

  ({int note, int velocity})? _hitTest(
    Offset pos,
    Map<int, Rect> whiteRects,
    Map<int, Rect> blackRects,
    double totalHeight,
    double blackHeight,
  ) {
    // 1. Check black keys first (top priority layer)
    for (final entry in blackRects.entries) {
      final rect = entry.value;
      if (rect.contains(pos)) {
        // Vertical ratio: 0.0 at top -> 1.0 at bottom of black key
        final yNorm = (pos.dy / rect.height).clamp(0.0, 1.0);
        final velocity = (25 + (102 * yNorm)).round().clamp(1, 127);
        return (note: entry.key, velocity: velocity);
      }
    }

    // 2. Check white keys
    for (final entry in whiteRects.entries) {
      final rect = entry.value;
      if (rect.contains(pos)) {
        // Vertical ratio: 0.0 at top -> 1.0 at bottom of white key
        final yNorm = (pos.dy / rect.height).clamp(0.0, 1.0);
        final velocity = (25 + (102 * yNorm)).round().clamp(1, 127);
        return (note: entry.key, velocity: velocity);
      }
    }

    return null;
  }
}
