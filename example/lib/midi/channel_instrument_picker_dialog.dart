// ignore_for_file: experimental_member_use

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart' show Vst3InstrumentPlugin;
import 'package:path/path.dart' as p;
import 'package:soundfont_kit/soundfont_kit.dart';

/// Modal dialog for selecting a SoundFont and instrument preset for a specific MIDI channel.
class ChannelInstrumentPickerDialog extends StatefulWidget {
  final int channel;
  final SoundFontPlayer defaultPlayer;
  final String defaultSoundFontName;
  final Map<String, SoundFontPlayer> loadedPlayers;
  final List<String> bundledSoundFonts;
  final SoundFontPlayer? currentPlayer;
  final Preset? currentPreset;
  final MidiPlayer? midiPlayer;
  final Future<SoundFontPlayer?> Function(File file) onLoadFromFile;
  final Future<SoundFontPlayer?> Function(String assetPath) onLoadFromAsset;

  const ChannelInstrumentPickerDialog({
    super.key,
    required this.channel,
    required this.defaultPlayer,
    required this.defaultSoundFontName,
    required this.loadedPlayers,
    required this.bundledSoundFonts,
    required this.currentPlayer,
    required this.currentPreset,
    this.midiPlayer,
    required this.onLoadFromFile,
    required this.onLoadFromAsset,
  });

  @override
  State<ChannelInstrumentPickerDialog> createState() =>
      _ChannelInstrumentPickerDialogState();
}

class _ChannelInstrumentPickerDialogState
    extends State<ChannelInstrumentPickerDialog> {
  late String _selectedSoundFontKey;
  late SoundFontPlayer _selectedPlayer;
  Preset? _selectedPreset;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  String _searchFilter = '';
  List<DiscoveredVst3Plugin> _discoveredVst3Synths = const [];

  @override
  void initState() {
    super.initState();
    if (widget.currentPlayer != null) {
      _selectedPlayer = widget.currentPlayer!;
      _selectedSoundFontKey =
          _findKeyForPlayer(widget.currentPlayer!) ??
          (widget.currentPlayer!.soundFont.name ?? 'Custom SoundFont');
    } else {
      _selectedPlayer = widget.defaultPlayer;
      _selectedSoundFontKey = widget.defaultSoundFontName;
    }

    _selectedPreset =
        widget.currentPreset ??
        (_selectedPlayer.soundFont.presets.isNotEmpty
            ? _selectedPlayer.soundFont.presets.first
            : null);

    if (SoundFontVst3Manager.instance.isSupported) {
      _scanSystemVst3Synths();
    }

    _searchController.addListener(() {
      setState(() {
        _searchFilter = _searchController.text.trim().toLowerCase();
      });
    });
  }

  void _scanSystemVst3Synths() {
    try {
      final all = SoundFontVst3Manager.instance.scanStandardDirectories();
      _discoveredVst3Synths = all.where((p) => p.isInstrument).toList();
    } catch (_) {
      _discoveredVst3Synths = const [];
    }
  }

  String? _findKeyForPlayer(SoundFontPlayer player) {
    for (final entry in widget.loadedPlayers.entries) {
      if (identical(entry.value, player)) return entry.key;
    }
    return null;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickSoundFontFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['sf2', 'sf3', 'sfz', 'zip'],
    );
    if (picked != null && picked.path != null) {
      setState(() {
        _isLoading = true;
      });
      final player = await widget.onLoadFromFile(File(picked.path!));
      if (player != null && mounted) {
        setState(() {
          _selectedPlayer = player;
          _selectedSoundFontKey = p.basename(picked.path!);
          _selectedPreset = player.soundFont.presets.isNotEmpty
              ? player.soundFont.presets.first
              : null;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickBundledSoundFont(String assetPath) async {
    setState(() {
      _isLoading = true;
    });
    final player = await widget.onLoadFromAsset(assetPath);
    if (player != null && mounted) {
      setState(() {
        _selectedPlayer = player;
        _selectedSoundFontKey = p.basename(assetPath);
        _selectedPreset = player.soundFont.presets.isNotEmpty
            ? player.soundFont.presets.first
            : null;
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _previewPreset(Preset preset) {
    _selectedPlayer.playPreset(preset, key: 60, velocity: 100).then((voice) {
      Future.delayed(const Duration(milliseconds: 650), () {
        voice.release();
      });
    });
  }

  Future<void> _loadVst3InstrumentFromPath(
    String path, {
    String? classUid,
    String? displayName,
  }) async {
    if (widget.midiPlayer == null) return;
    setState(() {
      _isLoading = true;
    });
    final inst = SoundFontVst3Manager.instance.loadInstrument(
      bundlePath: path,
      classUid: classUid,
      autoPlay: false,
    );
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
    if (inst != null) {
      final existing = widget.midiPlayer!.channels[widget.channel].vst3Instrument;
      if (existing != null && !identical(existing, inst)) {
        SoundFontVst3Manager.instance.unloadInstrument(existing);
      }
      widget.midiPlayer!.setChannelVst3Instrument(
        widget.channel,
        inst,
        name: displayName ?? p.basenameWithoutExtension(path),
      );
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load VST3 Instrument from $path'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _pickVst3Instrument() async {
    if (widget.midiPlayer == null) return;
    String? path;
    if (!kIsWeb && Platform.isMacOS) {
      path = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select a .vst3 Virtual Instrument Bundle',
      );
    } else {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Select a .vst3 Virtual Instrument Plugin',
        type: FileType.custom,
        allowedExtensions: ['vst3'],
      );
      path = picked?.path;
    }
    if (path == null || path.isEmpty) return;
    await _loadVst3InstrumentFromPath(path);
  }

  void _previewVst3Note(Vst3InstrumentPlugin inst) {
    inst.noteOn(pitch: 60, velocity: 0.85, channel: widget.channel);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (!inst.isDisposed) {
        inst.noteOff(pitch: 60, channel: widget.channel);
      }
    });
  }

  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  @override
  Widget build(BuildContext context) {
    final presets = _selectedPlayer.soundFont.presets.where((p) {
      if (_searchFilter.isEmpty) return true;
      final nameMatches = p.name.toLowerCase().contains(_searchFilter);
      final progMatches =
          '${p.program}'.contains(_searchFilter) ||
          '${p.bank}'.contains(_searchFilter);
      return nameMatches || progMatches;
    }).toList();

    return Dialog(
      backgroundColor: const Color(0xFF1A1D27),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 580,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.album_outlined,
                  color: Color(0xFF00E5FF),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Select SoundFont & Instrument for Channel ${widget.channel + 1}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // SoundFont selection section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF12141A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SOUNDFONT SOURCE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Dropdown of currently loaded SoundFonts
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedSoundFontKey,
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1E212B),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: widget.defaultSoundFontName,
                                child: Text(
                                  '${widget.defaultSoundFontName} (Default)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              for (final entry in widget.loadedPlayers.entries)
                                if (entry.key != widget.defaultSoundFontName)
                                  DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(
                                      entry.key,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                            ],
                            onChanged: (newKey) {
                              if (newKey == null) return;
                              setState(() {
                                _selectedSoundFontKey = newKey;
                                _selectedPlayer =
                                    newKey == widget.defaultSoundFontName
                                    ? widget.defaultPlayer
                                    : widget.loadedPlayers[newKey]!;
                                _selectedPreset =
                                    _selectedPlayer.soundFont.presets.isNotEmpty
                                    ? _selectedPlayer.soundFont.presets.first
                                    : null;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Add new SoundFont from file button
                      OutlinedButton.icon(
                        icon: const Icon(Icons.file_open_outlined, size: 14),
                        label: const Text(
                          'Open SF2...',
                          style: TextStyle(fontSize: 11),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00E5FF),
                          side: const BorderSide(color: Color(0xFF00E5FF)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        onPressed: _isLoading ? null : _pickSoundFontFile,
                      ),
                      const SizedBox(width: 6),
                      // Bundled SoundFonts PopupMenu
                      PopupMenuButton<String>(
                        tooltip: 'Bundled SoundFonts',
                        icon: const Icon(
                          Icons.library_music_outlined,
                          size: 16,
                          color: Colors.white70,
                        ),
                        color: const Color(0xFF222634),
                        onSelected: _pickBundledSoundFont,
                        itemBuilder: (context) {
                          return [
                            for (final asset in widget.bundledSoundFonts)
                              PopupMenuItem(
                                value: asset,
                                child: Text(
                                  p.basename(asset),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ];
                        },
                      ),
                    ],
                  ),
                  if (_isDesktop && widget.midiPlayer != null) ...[
                    const Divider(height: 16, color: Colors.white12),
                    if (!SoundFontVst3Manager.instance.isSupported)
                      const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: Colors.amberAccent,
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'VST3 support requires a full app restart (Stop & Run) so enable_vst3: true in pubspec.yaml is compiled.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.amberAccent,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Builder(
                        builder: (context) {
                          final chState =
                              widget.midiPlayer!.channels[widget.channel];
                          final activeVst3 = chState.vst3Instrument;
                          return Row(
                            children: [
                              const Icon(
                                Icons.extension,
                                size: 15,
                                color: Color(0xFF69F0AE),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  activeVst3 != null
                                      ? 'VST3 Synth: ${chState.vst3InstrumentName ?? "Loaded"}'
                                      : 'Desktop VST3 Virtual Instrument (Optional)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: activeVst3 != null
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: activeVst3 != null
                                        ? const Color(0xFF69F0AE)
                                        : Colors.white60,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_discoveredVst3Synths.isNotEmpty) ...[
                                PopupMenuButton<DiscoveredVst3Plugin>(
                                  tooltip: 'Select installed system VST3 Synth',
                                  color: const Color(0xFF222634),
                                  onSelected: (plugin) {
                                    _loadVst3InstrumentFromPath(
                                      plugin.bundlePath,
                                      classUid: plugin.classUid,
                                      displayName: plugin.name,
                                    );
                                  },
                                  itemBuilder: (context) {
                                    return [
                                      for (final plugin in _discoveredVst3Synths)
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: const Color(0xFF69F0AE),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.list_alt,
                                          size: 13,
                                          color: Color(0xFF69F0AE),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Installed (${_discoveredVst3Synths.length})',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF69F0AE),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              OutlinedButton.icon(
                                icon: const Icon(Icons.piano, size: 13),
                                label: Text(
                                  activeVst3 != null
                                      ? 'Replace .vst3...'
                                      : 'Load .vst3 Synth...',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF69F0AE),
                                  side: const BorderSide(
                                    color: Color(0xFF69F0AE),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                ),
                                onPressed:
                                    _isLoading ? null : _pickVst3Instrument,
                              ),
                              if (activeVst3 != null) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                    Icons.volume_up,
                                    size: 16,
                                    color: Color(0xFF69F0AE),
                                  ),
                                  tooltip: 'Preview VST3 Synth (Middle C)',
                                  onPressed: () => _previewVst3Note(activeVst3),
                                ),
                                if (activeVst3.hasEditor)
                                  ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.open_in_new,
                                      size: 13,
                                    ),
                                    label: const Text(
                                      'VST3 GUI',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6C63FF),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                    ),
                                    onPressed: () =>
                                        activeVst3.openEditorWindow(
                                          title:
                                              'Ch ${widget.channel + 1} — ${chState.vst3InstrumentName ?? "VST3 Synth"}',
                                        ),
                                  ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                    color: Colors.redAccent,
                                  ),
                                  tooltip: 'Unload VST3 Instrument',
                                  onPressed: () {
                                    widget.midiPlayer!.setChannelVst3Instrument(
                                      widget.channel,
                                      null,
                                    );
                                    SoundFontVst3Manager.instance
                                        .unloadInstrument(activeVst3);
                                    setState(() {});
                                  },
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Presets search bar
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search presets by name or program/bank...',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 16,
                  color: Colors.white54,
                ),
                suffixIcon: _searchFilter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 14),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF12141A),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Presets List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : presets.isEmpty
                  ? const Center(
                      child: Text(
                        'No presets matching filter',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      itemCount: presets.length,
                      itemBuilder: (context, idx) {
                        final pItem = presets[idx];
                        final isSelected =
                            _selectedPreset != null &&
                            _selectedPreset!.bank == pItem.bank &&
                            _selectedPreset!.program == pItem.program;

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(
                                    0xFF6C63FF,
                                  ).withValues(alpha: 0.25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF6C63FF)
                                  : Colors.transparent,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 0,
                            ),
                            title: Text(
                              pItem.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white70,
                              ),
                            ),
                            subtitle: Text(
                              'Bank: ${pItem.bank} | Program: ${pItem.program}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white38,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.volume_up,
                                size: 16,
                                color: Color(0xFF00E5FF),
                              ),
                              tooltip: 'Preview (Middle C)',
                              onPressed: () => _previewPreset(pItem),
                            ),
                            onTap: () {
                              setState(() {
                                _selectedPreset = pItem;
                              });
                            },
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Reset to Default button
                TextButton.icon(
                  icon: const Icon(Icons.restart_alt, size: 14),
                  label: const Text('Reset to Default'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orangeAccent,
                  ),
                  onPressed: () {
                    final activeVst3 = widget
                        .midiPlayer
                        ?.channels[widget.channel]
                        .vst3Instrument;
                    if (activeVst3 != null) {
                      widget.midiPlayer?.setChannelVst3Instrument(
                        widget.channel,
                        null,
                      );
                      SoundFontVst3Manager.instance.unloadInstrument(
                        activeVst3,
                      );
                    }
                    Navigator.of(context).pop((null, null, true));
                  },
                ),
                const Spacer(),
                TextButton(
                  child: const Text(
                    'Close',
                    style: TextStyle(color: Colors.white60),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Apply SoundFont Preset'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _selectedPreset != null
                      ? () {
                          final activeVst3 = widget
                              .midiPlayer
                              ?.channels[widget.channel]
                              .vst3Instrument;
                          if (activeVst3 != null) {
                            widget.midiPlayer?.setChannelVst3Instrument(
                              widget.channel,
                              null,
                            );
                            SoundFontVst3Manager.instance.unloadInstrument(
                              activeVst3,
                            );
                          }
                          Navigator.of(
                            context,
                          ).pop((_selectedPlayer, _selectedPreset, false));
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
