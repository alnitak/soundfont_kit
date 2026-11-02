// ignore_for_file: experimental_member_use

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart' show Vst3InstrumentPlugin;
import 'package:path/path.dart' as p;
import 'package:soundfont_kit/soundfont_kit.dart';

/// Modal dialog for selecting or removing a Desktop VST3 Virtual Instrument
/// (`Instrument|Synth`) for either a specific MIDI channel (`0..15`) or all 16
/// MIDI channels (`channel == null`, for multi-timbral synths like HALion Sonic).
///
/// When an instrument is selected, its native VST3 GUI editor window is
/// automatically opened. When the instrument is changed or removed, its native
/// GUI editor window is automatically closed and the plugin is unloaded.
class ChannelVst3InstrumentDialog extends StatefulWidget {
  final int? channel;
  final MidiPlayer midiPlayer;

  const ChannelVst3InstrumentDialog({
    super.key,
    required this.channel,
    required this.midiPlayer,
  });

  @override
  State<ChannelVst3InstrumentDialog> createState() =>
      _ChannelVst3InstrumentDialogState();
}

class _ChannelVst3InstrumentDialogState
    extends State<ChannelVst3InstrumentDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<DiscoveredVst3Plugin> _discoveredSynths = const [];
  bool _isLoading = false;
  String _searchFilter = '';

  bool get _isGlobal => widget.channel == null;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    if (SoundFontVst3Manager.instance.isSupported) {
      _scanSystemVst3Synths();
    }
    _searchController.addListener(() {
      setState(() {
        _searchFilter = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _scanSystemVst3Synths() {
    try {
      final all = SoundFontVst3Manager.instance.scanStandardDirectories();
      _discoveredSynths = all.where((p) => p.isInstrument).toList();
    } catch (_) {
      _discoveredSynths = const [];
    }
  }

  Future<void> _loadAndActivateVst3Synth(
    String bundlePath, {
    String? classUid,
    String? displayName,
  }) async {
    setState(() {
      _isLoading = true;
    });
    final inst = SoundFontVst3Manager.instance.loadInstrument(
      bundlePath: bundlePath,
      classUid: classUid,
      autoPlay: false,
    );
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });

    if (inst != null) {
      final resolvedName =
          displayName ?? p.basenameWithoutExtension(bundlePath);
      if (_isGlobal) {
        widget.midiPlayer.setGlobalVst3Instrument(inst, name: resolvedName);
        if (inst.hasEditor) {
          inst.openEditorWindow(title: 'All 16 Channels — $resolvedName');
        }
      } else {
        widget.midiPlayer.setChannelVst3Instrument(
          widget.channel!,
          inst,
          name: resolvedName,
        );
        if (inst.hasEditor) {
          inst.openEditorWindow(
            title: 'Ch ${widget.channel! + 1} — $resolvedName',
          );
        }
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load VST3 Instrument from $bundlePath'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _browseVst3Bundle() async {
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
    await _loadAndActivateVst3Synth(path);
  }

  void _removeActiveInstrument() {
    if (_isGlobal) {
      widget.midiPlayer.setGlobalVst3Instrument(null);
    } else {
      widget.midiPlayer.setChannelVst3Instrument(widget.channel!, null);
    }
    setState(() {});
  }

  void _previewNote(Vst3InstrumentPlugin inst) {
    final previewCh = widget.channel ?? 0;
    inst.noteOn(pitch: 60, velocity: 0.85, channel: previewCh);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (!inst.isDisposed) {
        inst.noteOff(pitch: 60, channel: previewCh);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeVst3 = _isGlobal
        ? widget.midiPlayer.globalVst3Instrument
        : widget.midiPlayer.channels[widget.channel!].vst3Instrument;
    final activeVst3Name = _isGlobal
        ? widget.midiPlayer.globalVst3InstrumentName
        : widget.midiPlayer.channels[widget.channel!].vst3InstrumentName;
    final filteredSynths = _discoveredSynths.where((s) {
      if (_searchFilter.isEmpty) return true;
      return s.name.toLowerCase().contains(_searchFilter) ||
          s.subCategories.toLowerCase().contains(_searchFilter);
    }).toList();

    return Dialog(
      backgroundColor: const Color(0xFF1A1D27),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 540,
        height: 520,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.extension, color: Color(0xFF69F0AE), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isGlobal
                        ? 'All 16 Channels — Multi-Timbral VST3 Instrument'
                        : 'Channel ${widget.channel! + 1} — VST3 Virtual Instrument',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (!_isDesktop)
              const Expanded(
                child: Center(
                  child: Text(
                    'VST3 Virtual Instruments are supported on macOS, Windows, and Linux.',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
              )
            else if (!SoundFontVst3Manager.instance.isSupported)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'VST3 support requires a full app restart (Stop & Run) so enable_vst3: true in pubspec.yaml is compiled.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.amberAccent, fontSize: 13),
                    ),
                  ),
                ),
              )
            else ...[
              // Current Active VST3 Instrument Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: activeVst3 != null
                      ? const Color(0xFF69F0AE).withValues(alpha: 0.1)
                      : const Color(0xFF12141A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: activeVst3 != null
                        ? const Color(0xFF69F0AE).withValues(alpha: 0.6)
                        : Colors.white12,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      activeVst3 != null
                          ? Icons.piano
                          : Icons.piano_off_outlined,
                      size: 18,
                      color: activeVst3 != null
                          ? const Color(0xFF69F0AE)
                          : Colors.white38,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activeVst3 != null
                                ? (activeVst3Name ?? 'VST3 Instrument Active')
                                : (_isGlobal
                                      ? 'No Global Multi-Timbral VST3 Instrument Assigned'
                                      : 'No VST3 Instrument Assigned (Using SoundFont)'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: activeVst3 != null
                                  ? const Color(0xFF69F0AE)
                                  : Colors.white70,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            activeVst3 != null
                                ? (_isGlobal
                                      ? 'Serving all 16 MIDI channels (Ch 1–16). GUI closes when changed or removed.'
                                      : 'GUI opens automatically when selected and closes when changed or removed.')
                                : (_isGlobal
                                      ? 'Choose a multi-timbral VST3 synth (e.g. HALion Sonic) to serve all 16 MIDI channels.'
                                      : 'Choose an installed VST3 synth below or browse a .vst3 bundle.'),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (activeVst3 != null) ...[
                      IconButton(
                        icon: const Icon(
                          Icons.volume_up,
                          size: 18,
                          color: Color(0xFF69F0AE),
                        ),
                        tooltip: 'Preview Note (Middle C)',
                        onPressed: () => _previewNote(activeVst3),
                      ),
                      if (activeVst3.hasEditor && !activeVst3.isEditorOpen)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.open_in_new, size: 13),
                          label: const Text(
                            'Show GUI',
                            style: TextStyle(fontSize: 11),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00E5FF),
                            side: const BorderSide(color: Color(0xFF00E5FF)),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            activeVst3.openEditorWindow(
                              title: _isGlobal
                                  ? 'All 16 Channels — ${activeVst3Name ?? "VST3 Synth"}'
                                  : 'Ch ${widget.channel! + 1} — ${activeVst3Name ?? "VST3 Synth"}',
                            );
                            setState(() {});
                          },
                        ),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 14),
                        label: const Text(
                          'Remove',
                          style: TextStyle(fontSize: 11),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(
                            alpha: 0.85,
                          ),
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _removeActiveInstrument,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Search & Browse Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search installed VST3 instruments...',
                        hintStyle: const TextStyle(
                          fontSize: 12,
                          color: Colors.white38,
                        ),
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
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 15),
                    label: const Text(
                      'Browse .vst3...',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF69F0AE),
                      side: const BorderSide(color: Color(0xFF69F0AE)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onPressed: _isLoading ? null : _browseVst3Bundle,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Discovered Installed VST3 Instruments List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredSynths.isEmpty
                    ? Center(
                        child: Text(
                          _discoveredSynths.isEmpty
                              ? 'No system VST3 instruments found in standard folders.\nUse "Browse .vst3..." to load one from disk.'
                              : 'No VST3 instruments matching "$_searchFilter".',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredSynths.length,
                        itemBuilder: (context, index) {
                          final plugin = filteredSynths[index];
                          final isCurrent =
                              activeVst3 != null &&
                              activeVst3Name == plugin.name;

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? const Color(
                                      0xFF69F0AE,
                                    ).withValues(alpha: 0.15)
                                  : const Color(0xFF141720),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isCurrent
                                    ? const Color(0xFF69F0AE)
                                    : Colors.white10,
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: Icon(
                                Icons.piano,
                                size: 16,
                                color: isCurrent
                                    ? const Color(0xFF69F0AE)
                                    : Colors.white54,
                              ),
                              title: Text(
                                plugin.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isCurrent
                                      ? const Color(0xFF69F0AE)
                                      : Colors.white,
                                ),
                              ),
                              subtitle: Text(
                                '${plugin.subCategories} • ${p.basename(plugin.bundlePath)}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white38,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isCurrent
                                      ? const Color(0xFF69F0AE)
                                      : const Color(0xFF6C63FF),
                                  foregroundColor: isCurrent
                                      ? Colors.black
                                      : Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                ),
                                onPressed: () => _loadAndActivateVst3Synth(
                                  plugin.bundlePath,
                                  classUid: plugin.classUid,
                                  displayName: plugin.name,
                                ),
                                child: Text(
                                  isCurrent ? 'Reload' : 'Select',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              onTap: () => _loadAndActivateVst3Synth(
                                plugin.bundlePath,
                                classUid: plugin.classUid,
                                displayName: plugin.name,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Close',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
