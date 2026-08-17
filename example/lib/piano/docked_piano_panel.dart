import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:soundfont_reader/soundfont_reader.dart';
import 'piano_keyboard.dart';
import 'rotary_knob.dart';

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
  }) : type = PlaybackTargetType.instrument,
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
      PlaybackTargetType.instrument =>
        instrument?.zones.isNotEmpty == true
            ? (instrument!.zones.first.rootKey ??
                  ((instrument!.zones.first.keyRangeMin +
                          instrument!.zones.first.keyRangeMax) ~/
                      2))
            : 60,
      PlaybackTargetType.preset =>
        preset?.zones.isNotEmpty == true
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
    final noteStr = resolvedMarkedKey != null
        ? ' • Key ${resolvedMarkedKey!}'
        : '';
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

  bool hasNativeSustain(SoundFontFile? soundFont) {
    if (type == PlaybackTargetType.instrument && instrument != null) {
      return instrument!.zones.any(
        (z) => (z.volEnvRelease != null && z.volEnvRelease! > 0),
      );
    }
    if (type == PlaybackTargetType.preset && preset != null) {
      if (preset!.zones.any(
        (z) => (z.volEnvRelease != null && z.volEnvRelease! > 0),
      )) {
        return true;
      }
      if (soundFont != null) {
        for (final pz in preset!.zones) {
          if (pz.instrumentID != null &&
              pz.instrumentID! < soundFont.instruments.length) {
            final inst = soundFont.instruments[pz.instrumentID!];
            if (inst.zones.any(
              (z) => (z.volEnvRelease != null && z.volEnvRelease! > 0),
            )) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SelectedPlaybackTarget &&
        other.type == type &&
        other.preset == preset &&
        other.instrument == instrument &&
        other.sample == sample &&
        other.markedKey == markedKey;
  }

  @override
  int get hashCode => Object.hash(type, preset, instrument, sample, markedKey);
}

/// A docked, resizable bottom panel featuring an interactive piano keyboard,
/// global volume & effects filter controls with rotary knobs, and target metadata header.
class DockedPianoPanel extends StatefulWidget {
  final SoundFontFile? soundFont;
  final SoundFontPlayer? player;
  final SelectedPlaybackTarget? selectedTarget;
  final VoidCallback? onPreviousItem;
  final VoidCallback? onNextItem;
  final double initialHeight;
  final double minHeight;
  final double maxHeight;

  const DockedPianoPanel({
    super.key,
    this.soundFont,
    required this.player,
    required this.selectedTarget,
    this.onPreviousItem,
    this.onNextItem,
    this.initialHeight = 220.0,
    this.minHeight = 140.0,
    this.maxHeight = 420.0,
  });

  @override
  State<DockedPianoPanel> createState() => _DockedPianoPanelState();
}

class _DockedPianoPanelState extends State<DockedPianoPanel> {
  late double _height;
  bool _isCollapsed = false;
  int _startOctave = 3; // Starts at C3 (MIDI 48)
  final Set<int> _activeKeys = {};
  double _globalVolume = 1.0;
  double _sustainMultiplier = 1.0;
  double _sustainTime = 0.20;
  final SoundFontGlobalFilters _filters = const SoundFontGlobalFilters();
  SoundFontFilterType _selectedFilterType = SoundFontFilterType.freeverb;

  @override
  void initState() {
    super.initState();
    _height = widget.initialHeight;
    if (widget.player != null) {
      widget.player!.sustainTime = _sustainTime;
      widget.player!.sustainMultiplier = _sustainMultiplier;
    }
    if (SoLoud.instance.isInitialized) {
      try {
        _globalVolume = SoLoud.instance.getGlobalVolume();
      } catch (_) {}
    }
  }

  @override
  void didUpdateWidget(DockedPianoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.player != oldWidget.player && widget.player != null) {
      widget.player!.sustainTime = _sustainTime;
      widget.player!.sustainMultiplier = _sustainMultiplier;
    }
    if (widget.selectedTarget != oldWidget.selectedTarget) {
      _stopAllVoices();
    }
  }

  void _stopAllVoices() {
    _activeKeys.clear();
    _safeSetState(() {});
    widget.player?.allNotesOff(
      releaseDuration: Duration.zero,
    );
    if (SoLoud.instance.isInitialized) {
      try {
        SoLoud.instance.stopAll();
      } catch (_) {}
    }
  }

  int get _startNote => _startOctave * 12 + 12; // C3 = 48, C4 = 60, etc.

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    if (WidgetsBinding.instance.buildOwner?.debugBuilding == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  void _shiftOctave(int delta) {
    _safeSetState(() {
      _startOctave = (_startOctave + delta).clamp(1, 7);
    });
  }

  void _handleNoteDown(int key, int velocity) {
    _activeKeys.add(key);
    _safeSetState(() {});
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
          player.playInstrument(
            target.instrument!,
            key: key,
            velocity: velocity,
          );
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
    _activeKeys.remove(key);
    _safeSetState(() {});
    widget.player?.noteOff(key);
  }

  void _showFilterSelectionMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 6.0,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.tune),
                          const SizedBox(width: 8),
                          Text(
                            'Global Output Audio Filters',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              _filters.deactivateAll();
                              setModalState(() {});
                              setState(() {});
                            },
                            child: const Text('Reset All'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    ...SoundFontFilterType.values.map((filterType) {
                      final isActive = _filters.isActive(filterType);
                      return CheckboxListTile(
                        value: isActive,
                        title: Text(filterType.label),
                        subtitle: Text(
                          filterType.description,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        onChanged: (val) {
                          _filters.toggle(filterType, val ?? false);
                          if (val == true) {
                            _selectedFilterType = filterType;
                          }
                          setModalState(() {});
                          setState(() {});
                        },
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = widget.selectedTarget;

    final activeFilters = SoundFontFilterType.values
        .where((t) => _filters.isActive(t))
        .toList();

    // Ensure selected filter is active if any active filters exist
    if (activeFilters.isNotEmpty &&
        !activeFilters.contains(_selectedFilterType)) {
      _selectedFilterType = activeFilters.first;
    }

    final hasNativeSus =
        target?.hasNativeSustain(widget.player?.soundFont) ?? false;

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
                _height = (_height - details.delta.dy).clamp(
                  widget.minHeight,
                  widget.maxHeight,
                );
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

                      // Sustain Time Knob (active when target has NO native sustain)
                      Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: RotaryKnob(
                          label: 'Sus',
                          value: _sustainTime,
                          min: 0.0,
                          max: 5.0,
                          defaultValue: 0.2,
                          unit: 's',
                          size: 30.0,
                          enabled: !hasNativeSus,
                          onChanged: (newSus) {
                            setState(() {
                              _sustainTime = newSus;
                            });
                            widget.player?.sustainTime = newSus;
                          },
                        ),
                      ),

                      // Sustain Multiplier Knob (active when target HAS native sustain)
                      Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: RotaryKnob(
                          label: 'Sus x',
                          value: _sustainMultiplier,
                          min: 0.0,
                          max: 10.0,
                          defaultValue: 1.0,
                          unit: 'x',
                          size: 30.0,
                          enabled: hasNativeSus,
                          onChanged: (newMult) {
                            setState(() {
                              _sustainMultiplier = newMult;
                            });
                            widget.player?.sustainMultiplier = newMult;
                          },
                        ),
                      ),

                      // Global Volume Knob
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: RotaryKnob(
                          label: 'Vol',
                          value: _globalVolume,
                          min: 0.0,
                          max: 3.0,
                          defaultValue: 1.0,
                          size: 30.0,
                          onChanged: (newVol) {
                            setState(() {
                              _globalVolume = newVol;
                            });
                            if (SoLoud.instance.isInitialized) {
                              try {
                                SoLoud.instance.setGlobalVolume(newVol);
                              } catch (_) {}
                            }
                          },
                        ),
                      ),

                      // Global Filters Button with badge
                      OutlinedButton.icon(
                        icon: const Icon(Icons.tune, size: 16),
                        label: Text(
                          activeFilters.isEmpty
                              ? 'Filters'
                              : 'FX (${activeFilters.length})',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: activeFilters.isNotEmpty
                              ? theme.colorScheme.primaryContainer
                              : null,
                          foregroundColor: activeFilters.isNotEmpty
                              ? theme.colorScheme.onPrimaryContainer
                              : null,
                        ),
                        onPressed: () => _showFilterSelectionMenu(context),
                      ),

                      const SizedBox(width: 6),

                      // Stop All Voices Button
                      IconButton.outlined(
                        icon: const Icon(Icons.stop, size: 18),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Stop All Playing Voices',
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(6),
                        ),
                        onPressed: _stopAllVoices,
                      ),

                      const SizedBox(width: 6),

                      // Octave Controls
                      IconButton.filledTonal(
                        icon: const Icon(Icons.arrow_left, size: 18),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Octave Down (Left Shift)',
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
                        tooltip: 'Octave Up (Right Shift)',
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

          // Active Filter Knobs Rack (shown if at least 1 filter is active)
          if (activeFilters.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: theme.colorScheme.surfaceContainer,
              child: Row(
                children: [
                  // Filter selector chip/tabs if multiple active
                  if (activeFilters.length > 1) ...[
                    PopupMenuButton<SoundFontFilterType>(
                      initialValue: _selectedFilterType,
                      tooltip: 'Select active filter to adjust',
                      child: Chip(
                        avatar: const Icon(Icons.settings, size: 14),
                        label: Text(_selectedFilterType.label),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      onSelected: (type) {
                        setState(() => _selectedFilterType = type);
                      },
                      itemBuilder: (context) => activeFilters.map((f) {
                        return PopupMenuItem(value: f, child: Text(f.label));
                      }).toList(),
                    ),
                    const SizedBox(width: 8),
                  ] else ...[
                    Text(
                      _selectedFilterType.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],

                  // Rotary knobs for the currently selected filter
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _filters
                            .getParameters(_selectedFilterType)
                            .map((param) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                ),
                                child: RotaryKnob(
                                  label: param.name,
                                  value: param.currentValue,
                                  min: param.min,
                                  max: param.max,
                                  defaultValue: param.defaultValue,
                                  unit: param.unit,
                                  onChanged: (newVal) {
                                    setState(() {
                                      param.setValue(newVal);
                                    });
                                  },
                                ),
                              );
                            })
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

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
                onOctaveShift: _shiftOctave,
                onPreviousItem: widget.onPreviousItem,
                onNextItem: widget.onNextItem,
                onStopAll: _stopAllVoices,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays a modal help dialog listing all physical keyboard shortcuts and piano key bindings.
void showKeyBindingsHelpDialog(BuildContext context) {
  final theme = Theme.of(context);
  showDialog(
    context: context,
    builder: (context) {
      Widget buildKbdBadge(String text) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                offset: const Offset(0, 1.5),
                blurRadius: 1,
              ),
            ],
          ),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        );
      }

      Widget buildRow(Widget shortcut, String description) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              SizedBox(
                width: 130,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: shortcut,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  description,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      }

      return AlertDialog(
        icon: const Icon(Icons.keyboard, size: 28),
        title: const Text('Keyboard Shortcuts'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Navigation & Playback',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              buildRow(buildKbdBadge('Z'), 'Previous item in list'),
              buildRow(buildKbdBadge('X'), 'Next item in list'),
              buildRow(buildKbdBadge('C'), 'Stop all playing voices'),
              buildRow(buildKbdBadge('Left Shift'), 'Shift octave down'),
              buildRow(buildKbdBadge('Right Shift'), 'Shift octave up'),
              const Divider(height: 24),
              Text(
                'Piano Keys (1 Chromatic Octave)',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              buildRow(
                Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  children: ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K']
                      .map(buildKbdBadge)
                      .toList(),
                ),
                'White keys (C, D, E, F, G, A, B, C)',
              ),
              const SizedBox(height: 4),
              buildRow(
                Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  children: ['W', 'E', 'T', 'Y', 'U']
                      .map(buildKbdBadge)
                      .toList(),
                ),
                'Black keys (C#, D#, F#, G#, A#)',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
