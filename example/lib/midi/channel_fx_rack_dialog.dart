// ignore_for_file: experimental_member_use

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:soundfont_kit/soundfont_kit.dart';

import '../piano/rotary_knob.dart';

/// Modal dialog for managing per-channel VST3 Audio Effects (`Slot 1..8`)
/// and built-in DSP filters on a MIDI channel's mixing [Bus].
class ChannelFxRackDialog extends StatefulWidget {
  final int channel;
  final MidiPlayer midiPlayer;
  final String instrumentName;

  const ChannelFxRackDialog({
    super.key,
    required this.channel,
    required this.midiPlayer,
    required this.instrumentName,
  });

  @override
  State<ChannelFxRackDialog> createState() => _ChannelFxRackDialogState();
}

class _ChannelFxRackDialogState extends State<ChannelFxRackDialog> {
  late final MidiChannelState _chState;
  late final SoundFontFilterRack _rack;
  List<DiscoveredVst3Plugin> _discoveredVst3Effects = const [];
  final Map<int, String> _slotNames = {};

  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _chState = widget.midiPlayer.channels[widget.channel];
    _chState.ensureBus();
    _rack = _chState.filterRack;

    if (SoundFontVst3Manager.instance.isSupported) {
      _scanSystemVst3Effects();
    }
  }

  void _scanSystemVst3Effects() {
    try {
      final all = SoundFontVst3Manager.instance.scanStandardDirectories();
      _discoveredVst3Effects = all.where((p) => p.isEffect).toList();
    } catch (_) {
      _discoveredVst3Effects = const [];
    }
  }

  Future<void> _loadVst3EffectIntoSlot(
    int slotIndex,
    String bundlePath, {
    String? classUid,
    String? displayName,
  }) async {
    final bus = _chState.ensureBus();
    try {
      final fx = SoundFontVst3Manager.instance.loadBusEffect(
        bus: bus,
        slotIndex: slotIndex,
        bundlePath: bundlePath,
        classUid: classUid,
      );
      _slotNames[slotIndex] =
          displayName ?? p.basenameWithoutExtension(bundlePath);
      if (mounted) {
        setState(() {});
      }
      if (fx.hasEditor) {
        fx.openEditorWindow(
          title:
              'Ch ${widget.channel + 1} FX #${slotIndex + 1} — ${_slotNames[slotIndex]}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load VST3 Effect: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _browseAndLoadVst3Effect(int slotIndex) async {
    String? path;
    if (!kIsWeb && Platform.isMacOS) {
      path = await FilePicker.getDirectoryPath(
        dialogTitle:
            'Select a .vst3 Audio Effect Bundle for Slot ${slotIndex + 1}',
      );
    } else {
      final picked = await FilePicker.pickFile(
        dialogTitle:
            'Select a .vst3 Audio Effect Plugin for Slot ${slotIndex + 1}',
        type: FileType.custom,
        allowedExtensions: ['vst3'],
      );
      path = picked?.path;
    }
    if (path == null || path.isEmpty) return;
    await _loadVst3EffectIntoSlot(slotIndex, path);
  }

  @override
  Widget build(BuildContext context) {
    final bus = _chState.ensureBus();
    final builtInTypes = SoundFontFilterType.values
        .where((t) => !t.isCustomSlot)
        .toList();

    return Dialog(
      backgroundColor: const Color(0xFF1A1D27),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 640,
        height: 620,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.graphic_eq, color: Color(0xFF00E5FF), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Channel ${widget.channel + 1} FX & VST3 Rack — ${widget.instrumentName}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Clear All FX'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orangeAccent,
                  ),
                  onPressed: () {
                    for (var i = 0; i < 8; i++) {
                      SoundFontVst3Manager.instance.unloadBusEffect(bus, i);
                    }
                    _rack.deactivateAll();
                    setState(() {});
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                children: [
                  // 1. Desktop VST3 Effect Insert Slots (Slots 1..4 shown compactly, expandable to 8)
                  if (_isDesktop) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF12141A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF69F0AE).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.extension,
                                size: 15,
                                color: Color(0xFF69F0AE),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'VST3 AUDIO EFFECT INSERTS (PER-CHANNEL BUS)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                  color: Color(0xFF69F0AE),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (!SoundFontVst3Manager.instance.isSupported)
                            const Text(
                              'VST3 support requires a full app restart (Stop & Run) so enable_vst3: true in pubspec.yaml is compiled.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.amberAccent,
                              ),
                            )
                          else
                            for (var slotIdx = 0; slotIdx < 4; slotIdx++)
                              _buildVst3SlotRow(bus, slotIdx),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // 2. Built-in SoLoud Per-Channel Bus DSP Filters
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 6),
                    child: Text(
                      'BUILT-IN CHANNEL BUS DSP FILTERS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                  for (final filterType in builtInTypes)
                    _buildBuiltInFilterCard(filterType),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVst3SlotRow(dynamic bus, int slotIdx) {
    final loadedFx = SoundFontVst3Manager.instance.getBusEffect(bus, slotIdx);
    final slotType = SoundFontFilterType.fromCustomSlotIndex(slotIdx);
    final params = _rack.getParameters(slotType);
    final wetParam = params.isNotEmpty ? params.first : null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: loadedFx != null
            ? const Color(0xFF69F0AE).withValues(alpha: 0.08)
            : const Color(0xFF181B24),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: loadedFx != null
              ? const Color(0xFF69F0AE).withValues(alpha: 0.5)
              : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'SLOT ${slotIdx + 1}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loadedFx != null
                  ? (_slotNames[slotIdx] ?? 'VST3 Effect Loaded')
                  : 'Empty Insert Slot',
              style: TextStyle(
                fontSize: 12,
                fontWeight: loadedFx != null
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: loadedFx != null
                    ? const Color(0xFF69F0AE)
                    : Colors.white38,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (loadedFx != null && wetParam != null) ...[
            const Text(
              'Wet',
              style: TextStyle(fontSize: 10, color: Colors.white54),
            ),
            SizedBox(
              width: 90,
              child: Slider(
                value: wetParam.currentValue.clamp(0.0, 1.0),
                min: 0.0,
                max: 1.0,
                activeColor: const Color(0xFF69F0AE),
                onChanged: (v) {
                  setState(() {
                    wetParam.setValue(v);
                  });
                },
              ),
            ),
          ],
          if (_discoveredVst3Effects.isNotEmpty) ...[
            PopupMenuButton<DiscoveredVst3Plugin>(
              tooltip: 'Select installed system VST3 Effect',
              color: const Color(0xFF222634),
              onSelected: (plugin) {
                _loadVst3EffectIntoSlot(
                  slotIdx,
                  plugin.bundlePath,
                  classUid: plugin.classUid,
                  displayName: plugin.name,
                );
              },
              itemBuilder: (context) {
                return [
                  for (final plugin in _discoveredVst3Effects)
                    PopupMenuItem(
                      value: plugin,
                      child: Text(
                        plugin.name,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ];
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF69F0AE)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.list_alt, size: 12, color: Color(0xFF69F0AE)),
                    SizedBox(width: 3),
                    Text(
                      'Installed',
                      style: TextStyle(fontSize: 10, color: Color(0xFF69F0AE)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open, size: 12),
            label: Text(
              loadedFx != null ? 'Replace...' : 'Load .vst3...',
              style: const TextStyle(fontSize: 10),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00E5FF),
              side: const BorderSide(color: Color(0xFF00E5FF)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => _browseAndLoadVst3Effect(slotIdx),
          ),
          if (loadedFx != null) ...[
            if (loadedFx.hasEditor) ...[
              const SizedBox(width: 6),
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 12),
                label: const Text('GUI', style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => loadedFx.openEditorWindow(
                  title:
                      'Ch ${widget.channel + 1} FX #${slotIdx + 1} — ${_slotNames[slotIdx] ?? "VST3 FX"}',
                ),
              ),
            ],
            const SizedBox(width: 2),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 16,
                color: Colors.redAccent,
              ),
              visualDensity: VisualDensity.compact,
              tooltip: 'Remove VST3 Effect',
              onPressed: () {
                SoundFontVst3Manager.instance.unloadBusEffect(bus, slotIdx);
                _slotNames.remove(slotIdx);
                setState(() {});
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBuiltInFilterCard(SoundFontFilterType filterType) {
    final isActive = _rack.isActive(filterType);
    final params = isActive
        ? _rack.getParameters(filterType)
        : const <FilterParameterInfo>[];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF6C63FF).withValues(alpha: 0.12)
            : const Color(0xFF141720),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive ? const Color(0xFF6C63FF) : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            value: isActive,
            activeColor: const Color(0xFF6C63FF),
            title: Text(
              filterType.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              filterType.description,
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
            onChanged: (checked) {
              setState(() {
                _rack.toggle(filterType, checked == true);
              });
            },
          ),
          if (isActive && params.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: params.map((param) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: RotaryKnob(
                        label: param.name,
                        value: param.currentValue,
                        min: param.min,
                        max: param.max,
                        defaultValue: param.defaultValue,
                        unit: param.unit,
                        size: 32,
                        onChanged: (val) {
                          setState(() {
                            param.setValue(val);
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
