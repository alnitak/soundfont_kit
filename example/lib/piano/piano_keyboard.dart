import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A chromatic piano keyboard widget that supports multitouch chords,
/// physical computer keyboard bindings, glissandos, and vertical touch position
/// velocity sensitivity (top = soft, bottom = loud).
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

  /// Optional callback when an octave shift key is pressed (Left Shift = -1, Right Shift = +1).
  final void Function(int deltaOctave)? onOctaveShift;

  /// Optional callback when previous item key (Arrow Up) is pressed.
  final VoidCallback? onPreviousItem;

  /// Optional callback when next item key (Arrow Down) is pressed.
  final VoidCallback? onNextItem;

  /// Optional callback when stop all key (Canc / Delete) is pressed.
  final VoidCallback? onStopAll;

  const PianoKeyboard({
    super.key,
    this.startNote = 48, // C3
    this.keyCount = 37, // ~3 octaves (C3 to C6)
    required this.onNoteDown,
    required this.onNoteUp,
    this.onOctaveShift,
    this.onPreviousItem,
    this.onNextItem,
    this.onStopAll,
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

  /// Set of physically held computer keyboard keys.
  final Set<LogicalKeyboardKey> _pressedPhysicalKeys = {};
  int? _spacePlayingNote;

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
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  /// 1-Octave QWERTY layout mapping (A=C through K=C+1):
  static final Map<LogicalKeyboardKey, ({int semitoneOffset, String label})>
  _keyBindings = {
    LogicalKeyboardKey.keyA: (semitoneOffset: 0, label: 'A'),
    LogicalKeyboardKey.keyW: (semitoneOffset: 1, label: 'W'),
    LogicalKeyboardKey.keyS: (semitoneOffset: 2, label: 'S'),
    LogicalKeyboardKey.keyE: (semitoneOffset: 3, label: 'E'),
    LogicalKeyboardKey.keyD: (semitoneOffset: 4, label: 'D'),
    LogicalKeyboardKey.keyF: (semitoneOffset: 5, label: 'F'),
    LogicalKeyboardKey.keyT: (semitoneOffset: 6, label: 'T'),
    LogicalKeyboardKey.keyG: (semitoneOffset: 7, label: 'G'),
    LogicalKeyboardKey.keyY: (semitoneOffset: 8, label: 'Y'),
    LogicalKeyboardKey.keyH: (semitoneOffset: 9, label: 'H'),
    LogicalKeyboardKey.keyU: (semitoneOffset: 10, label: 'U'),
    LogicalKeyboardKey.keyJ: (semitoneOffset: 11, label: 'J'),
    LogicalKeyboardKey.keyK: (semitoneOffset: 12, label: 'K'),
  };

  static const Map<int, String> _primaryKeyLabels = {
    0: 'A',
    1: 'W',
    2: 'S',
    3: 'E',
    4: 'D',
    5: 'F',
    6: 'T',
    7: 'G',
    8: 'Y',
    9: 'H',
    10: 'U',
    11: 'J',
    12: 'K',
  };

  static String? getKeyBindingLabel(int noteOffset) {
    return _primaryKeyLabels[noteOffset];
  }

  static bool isBlackKey(int midiNote) {
    return _isBlackNoteInOctave[midiNote % 12];
  }

  static String getNoteName(int midiNote) {
    final name = _noteNames[midiNote % 12];
    final octave = (midiNote ~/ 12) - 1;
    return '$name$octave';
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void didUpdateWidget(PianoKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.startNote != oldWidget.startNote &&
        _pressedPhysicalKeys.isNotEmpty) {
      final oldStart = oldWidget.startNote;
      final newStart = widget.startNote;
      final keysToUpdate = Set<LogicalKeyboardKey>.from(_pressedPhysicalKeys);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final key in keysToUpdate) {
          final binding = _keyBindings[key];
          if (binding != null) {
            widget.onNoteUp(oldStart + binding.semitoneOffset);
            widget.onNoteDown(newStart + binding.semitoneOffset, 100);
          }
        }
      });
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    if (_spacePlayingNote != null) {
      widget.onNoteUp(_spacePlayingNote!);
      _spacePlayingNote = null;
    }
    for (final key in _pressedPhysicalKeys) {
      final binding = _keyBindings[key];
      if (binding != null) {
        widget.onNoteUp(widget.startNote + binding.semitoneOffset);
      }
    }
    _pressedPhysicalKeys.clear();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!mounted) return false;

    // Allow system shortcuts with Command/Meta or Control (e.g. Cmd+Q, Cmd+W)
    if (HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed) {
      return false;
    }

    // Handle Space key to play/release the currently active selected target
    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        if (_spacePlayingNote == null) {
          final note = widget.markedKey ?? 60;
          _spacePlayingNote = note;
          widget.onNoteDown(note, 100);
          setState(() {});
        }
      } else if (event is KeyUpEvent) {
        if (_spacePlayingNote != null) {
          widget.onNoteUp(_spacePlayingNote!);
          _spacePlayingNote = null;
          setState(() {});
        }
      }
      return true;
    }

    // Handle octave shifting with Left Arrow / Left Shift (down) and Right Arrow / Right Shift (up)
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftLeft) {
      if (event is KeyDownEvent) {
        widget.onOctaveShift?.call(-1);
      }
      return true;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.shiftRight) {
      if (event is KeyDownEvent) {
        widget.onOctaveShift?.call(1);
      }
      return true;
    }

    // Handle Navigation & Stop shortcuts: Arrow Up (previous item), Arrow Down (next item), Canc/Delete/Backspace (stop all voices)
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (event is KeyDownEvent) {
        widget.onPreviousItem?.call();
      }
      return true;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (event is KeyDownEvent) {
        widget.onNextItem?.call();
      }
      return true;
    } else if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (event is KeyDownEvent) {
        widget.onStopAll?.call();
      }
      return true;
    }

    final binding = _keyBindings[event.logicalKey];
    if (binding == null) {
      // Absorb unused keys so macOS doesn't play the unhandled key beep
      return true;
    }

    final midiNote = widget.startNote + binding.semitoneOffset;
    if (midiNote < widget.startNote ||
        midiNote >= widget.startNote + widget.keyCount) {
      return true;
    }

    if (event is KeyDownEvent) {
      if (!_pressedPhysicalKeys.contains(event.logicalKey)) {
        _pressedPhysicalKeys.add(event.logicalKey);
        widget.onNoteDown(midiNote, 100);
        setState(() {});
      }
      return true;
    } else if (event is KeyRepeatEvent) {
      // Absorb key repeats so holding down a key does not trigger macOS alert sounds
      return true;
    } else if (event is KeyUpEvent) {
      if (_pressedPhysicalKeys.remove(event.logicalKey)) {
        widget.onNoteUp(midiNote);
        setState(() {});
      }
      return true;
    }

    return true;
  }

  bool _isPhysicalKeyPressed(int note) {
    if (_spacePlayingNote == note) return true;
    for (final key in _pressedPhysicalKeys) {
      final binding = _keyBindings[key];
      if (binding != null &&
          (widget.startNote + binding.semitoneOffset) == note) {
        return true;
      }
    }
    return false;
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
                final isPressed =
                    widget.activeKeys.contains(note) ||
                    _pointerNotes.values.contains(note) ||
                    _isPhysicalKeyPressed(note);
                final hasZone =
                    widget.availableKeys == null ||
                    widget.availableKeys!.contains(note);
                final isMarked =
                    (widget.markedKey != null && widget.markedKey == note) ||
                    (widget.markedKeys != null &&
                        widget.markedKeys!.contains(note));
                final keyLabel = getKeyBindingLabel(note - widget.startNote);

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
                      border: Border.all(color: Colors.black45, width: 1.0),
                      boxShadow: [
                        if (!isPressed)
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            offset: const Offset(0, 3),
                            blurRadius: 2,
                          ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$note',
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (note % 12 == 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2.0),
                                child: Text(
                                  getNoteName(note),
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            if (keyLabel != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 2.0),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3.5,
                                  vertical: 1.0,
                                ),
                                decoration: BoxDecoration(
                                  color: isPressed
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(3.0),
                                  border: Border.all(
                                    color: isPressed
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.grey.shade400,
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  keyLabel,
                                  style: const TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            if (isMarked)
                              Container(
                                margin: const EdgeInsets.only(
                                  top: 1.0,
                                  bottom: 2.0,
                                ),
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
                      ],
                    ),
                  ),
                );
              }),

              // Black keys foreground layer
              ...blackKeyRects.entries.map((entry) {
                final note = entry.key;
                final rect = entry.value;
                final isPressed =
                    widget.activeKeys.contains(note) ||
                    _pointerNotes.values.contains(note) ||
                    _isPhysicalKeyPressed(note);
                final hasZone =
                    widget.availableKeys == null ||
                    widget.availableKeys!.contains(note);
                final isMarked =
                    (widget.markedKey != null && widget.markedKey == note) ||
                    (widget.markedKeys != null &&
                        widget.markedKeys!.contains(note));
                final keyLabel = getKeyBindingLabel(note - widget.startNote);

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
                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$note',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600,
                            color: isPressed
                                ? Theme.of(context).colorScheme.onPrimary
                                : (hasZone ? Colors.white70 : Colors.white38),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (keyLabel != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 1.0),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2.5,
                                  vertical: 1.0,
                                ),
                                decoration: BoxDecoration(
                                  color: isPressed
                                      ? Theme.of(context).colorScheme.onPrimary
                                            .withValues(alpha: 0.9)
                                      : const Color(0xFF383838),
                                  borderRadius: BorderRadius.circular(3.0),
                                  border: Border.all(
                                    color: isPressed
                                        ? Colors.transparent
                                        : Colors.white24,
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  keyLabel,
                                  style: TextStyle(
                                    fontSize: 8.0,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                    color: isPressed
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white70,
                                  ),
                                ),
                              ),
                            if (isMarked)
                              Container(
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
                              ),
                          ],
                        ),
                      ],
                    ),
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
    final noteInfo = _hitTest(
      pos,
      whiteRects,
      blackRects,
      totalHeight,
      blackHeight,
    );
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
    final noteInfo = _hitTest(
      pos,
      whiteRects,
      blackRects,
      totalHeight,
      blackHeight,
    );
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
