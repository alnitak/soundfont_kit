import 'package:flutter/material.dart';
import 'package:soundfont_reader/soundfont_reader.dart';
import 'piano_keyboard.dart';

/// Target type for playback.
enum PlaybackTargetType { preset, instrument, sample }

/// Represents the currently active SoundFont entity being auditioned.
class SelectedPlaybackTarget {
  final PlaybackTargetType type;
  final Preset? preset;
  final Instrument? instrument;
  final SampleInfo? sample;
  final int? markedKey;

  const SelectedPlaybackTarget.preset(Preset this.preset, {this.markedKey})
      : type = PlaybackTargetType.preset,
        instrument = null,
        sample = null;

  const SelectedPlaybackTarget.instrument(
    Instrument this.instrument, {
    this.markedKey,
  })  : type = PlaybackTargetType.instrument,
        preset = null,
        sample = null;

  const SelectedPlaybackTarget.sample(SampleInfo this.sample, {this.markedKey})
      : type = PlaybackTargetType.sample,
        preset = null,
        instrument = null;

  int? get resolvedMarkedKey {
    if (markedKey != null) return markedKey;
    return switch (type) {
      PlaybackTargetType.sample => sample?.originalPitch,
      PlaybackTargetType.instrument => instrument?.zones.isNotEmpty == true
          ? (instrument!.zones.first.rootKey ??
              ((instrument!.zones.first.keyRangeMin +
                      instrument!.zones.first.keyRangeMax) ~/
                  2))
          : 60,
      PlaybackTargetType.preset => preset?.zones.isNotEmpty == true
          ? (preset!.zones.first.rootKey ??
              ((preset!.zones.first.keyRangeMin +
                      preset!.zones.first.keyRangeMax) ~/
                  2))
          : 60,
    };
  }

  String get title {
    return switch (type) {
      PlaybackTargetType.preset => 'Preset: ${preset?.name ?? "Unknown"}',
      PlaybackTargetType.instrument =>
        'Instrument: ${instrument?.name ?? "Unknown"}',
      PlaybackTargetType.sample => 'Sample: ${sample?.name ?? "Unknown"}',
    };
  }

  String get subtitle {
    final noteStr = resolvedMarkedKey != null ? ' • Key ${resolvedMarkedKey!}' : '';
    return switch (type) {
      PlaybackTargetType.preset =>
        'Bank ${preset?.bank ?? 0}, Program ${preset?.program ?? 0} • ${preset?.zones.length ?? 0} Zones$noteStr',
      PlaybackTargetType.instrument =>
        '${instrument?.zones.length ?? 0} Zones mapped$noteStr',
      PlaybackTargetType.sample =>
        '${sample?.sampleRate ?? 44100} Hz • Pitch ${sample?.originalPitch ?? 60} • ${sample?.compression.name.toUpperCase()}',
    };
  }

  IconData get icon {
    return switch (type) {
      PlaybackTargetType.preset => Icons.tune,
      PlaybackTargetType.instrument => Icons.piano,
      PlaybackTargetType.sample => Icons.graphic_eq,
    };
  }

  Set<int>? get availableKeys {
    if (type == PlaybackTargetType.instrument && instrument != null) {
      final keys = <int>{};
      for (final zone in instrument!.zones) {
        for (int k = zone.keyRangeMin; k <= zone.keyRangeMax; k++) {
          keys.add(k);
        }
      }
      return keys;
    }
    if (type == PlaybackTargetType.preset && preset != null) {
      final keys = <int>{};
      for (final zone in preset!.zones) {
        for (int k = zone.keyRangeMin; k <= zone.keyRangeMax; k++) {
          keys.add(k);
        }
      }
      return keys;
    }
    return null;
  }
}

/// A docked, resizable bottom panel featuring an interactive piano keyboard
/// and target metadata header.
class DockedPianoPanel extends StatefulWidget {
  final SoundFontPlayer? player;
  final SelectedPlaybackTarget? selectedTarget;
  final double initialHeight;
  final double minHeight;
  final double maxHeight;

  const DockedPianoPanel({
    super.key,
    required this.player,
    required this.selectedTarget,
    this.initialHeight = 210.0,
    this.minHeight = 110.0,
    this.maxHeight = 380.0,
  });

  @override
  State<DockedPianoPanel> createState() => _DockedPianoPanelState();
}

class _DockedPianoPanelState extends State<DockedPianoPanel> {
  late double _height;
  bool _isCollapsed = false;
  int _startOctave = 3; // C3 (note 48)
  final Set<int> _activeKeys = {};

  @override
  void initState() {
    super.initState();
    _height = widget.initialHeight;
  }

  int get _startNote => _startOctave * 12 + 12; // C3 = 48, C4 = 60, etc.

  void _shiftOctave(int delta) {
    setState(() {
      _startOctave = (_startOctave + delta).clamp(1, 7);
    });
  }

  void _handleNoteDown(int key, int velocity) {
    setState(() => _activeKeys.add(key));
    final player = widget.player;
    final target = widget.selectedTarget;
    if (player == null || target == null) return;

    switch (target.type) {
      case PlaybackTargetType.preset:
        if (target.preset != null) {
          player.playPreset(target.preset!, key: key, velocity: velocity);
        }
        break;
      case PlaybackTargetType.instrument:
        if (target.instrument != null) {
          player.playInstrument(target.instrument!, key: key, velocity: velocity);
        }
        break;
      case PlaybackTargetType.sample:
        if (target.sample != null) {
          player.playSample(target.sample!, key: key, velocity: velocity);
        }
        break;
    }
  }

  void _handleNoteUp(int key) {
    setState(() => _activeKeys.remove(key));
    widget.player?.noteOff(key);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = widget.selectedTarget;

    if (_isCollapsed) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(top: BorderSide(color: theme.dividerColor)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              offset: const Offset(0, -2),
              blurRadius: 6,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Icon(target?.icon ?? Icons.piano, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  target?.title ?? 'No target selected',
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                tooltip: 'Expand Piano Keyboard',
                onPressed: () => setState(() => _isCollapsed = false),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            offset: const Offset(0, -3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        children: [
          // Resize handle & Header
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) {
              setState(() {
                _height = (_height - details.delta.dy)
                    .clamp(widget.minHeight, widget.maxHeight);
              });
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              color: theme.colorScheme.surfaceContainerHigh,
              child: Column(
                children: [
                  // Center drag grip
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(target?.icon ?? Icons.piano, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              target?.title ?? 'Select an item to audition',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (target != null)
                              Text(
                                target.subtitle,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),

                      // Octave Controls
                      IconButton.filledTonal(
                        icon: const Icon(Icons.arrow_left, size: 18),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Octave Down',
                        onPressed: _startOctave > 1
                            ? () => _shiftOctave(-1)
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Text(
                          'C$_startOctave',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.arrow_right, size: 18),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Octave Up',
                        onPressed: _startOctave < 7
                            ? () => _shiftOctave(1)
                            : null,
                      ),

                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                        tooltip: 'Collapse Piano',
                        onPressed: () => setState(() => _isCollapsed = true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Piano Keyboard area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
              child: PianoKeyboard(
                startNote: _startNote,
                keyCount: 37, // 3 full octaves
                activeKeys: _activeKeys,
                availableKeys: target?.availableKeys,
                markedKey: target?.resolvedMarkedKey,
                onNoteDown: _handleNoteDown,
                onNoteUp: _handleNoteUp,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
