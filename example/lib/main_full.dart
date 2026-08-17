import 'dart:developer' as dev;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:soundfont_reader/soundfont_reader.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:logging/logging.dart';
import 'piano/docked_piano_panel.dart';
import 'piano/sample_waveform.dart';

void main() async {
  Logger.root.level = kDebugMode ? Level.ALL : Level.INFO;
  Logger.root.onRecord.listen((record) {
    dev.log(
      record.message,
      time: record.time,
      level: record.level.value,
      name: record.loggerName,
      zone: record.zone,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  });

  WidgetsFlutterBinding.ensureInitialized();

  /// Initialize the player.
  await SoLoud.instance.init();
  SoLoud.instance.setMaxActiveVoiceCount(128);

  runApp(const SoundFontReaderDemoApp());
}

class SoundFontReaderDemoApp extends StatelessWidget {
  const SoundFontReaderDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SoundFont Reader Demo',
      debugShowCheckedModeBanner: false,
      shortcuts: <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.space):
            const DoNothingIntent(),
        const SingleActivator(LogicalKeyboardKey.space, shift: true):
            const DoNothingIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const DoNothingIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const DoNothingIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const DoNothingIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const DoNothingIntent(),
        const SingleActivator(LogicalKeyboardKey.delete):
            const DoNothingIntent(),
        const SingleActivator(LogicalKeyboardKey.backspace):
            const DoNothingIntent(),
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SoundFontInspectorScreen(),
    );
  }
}

/// Represents a selectable SoundFont source (bundled asset or external file/bytes).
class SoundFontSourceEntry {
  final String id;
  final String label;
  final bool isAsset;
  final String? filePath;
  final Uint8List? fileBytes;

  SoundFontSourceEntry.asset(String path)
    : id = path,
      label = path.split('/').last,
      isAsset = true,
      filePath = path,
      fileBytes = null;

  SoundFontSourceEntry.file(String path, {String? name})
    : id = path,
      label = name ?? path.split('/').last,
      isAsset = false,
      filePath = path,
      fileBytes = null;

  SoundFontSourceEntry.bytes(
    this.fileBytes, {
    required this.id,
    required this.label,
  }) : isAsset = false,
       filePath = null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SoundFontSourceEntry &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class SoundFontInspectorScreen extends StatefulWidget {
  const SoundFontInspectorScreen({super.key});

  @override
  State<SoundFontInspectorScreen> createState() =>
      _SoundFontInspectorScreenState();
}

class _SoundFontInspectorScreenState extends State<SoundFontInspectorScreen>
    with SingleTickerProviderStateMixin {
  final List<SoundFontSourceEntry> _sources = [
    SoundFontSourceEntry.asset('assets/RatAttack.sf2'),
    SoundFontSourceEntry.asset('assets/1115_PassingJet.sf2.zip'),
    SoundFontSourceEntry.asset('assets/Celesta_minimal.sf3'),
    SoundFontSourceEntry.asset('assets/Contact.sf2'),
    SoundFontSourceEntry.asset('assets/Pac-Man-W2_.sf2.zip'),
    SoundFontSourceEntry.asset('assets/SFX_StarWars_ships.SF2.zip'),
    SoundFontSourceEntry.asset('assets/SFX_StarWars_weapons.SF2'),
  ];

  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );
  late SoundFontSourceEntry _selectedSource;
  bool _isLoading = false;
  String? _error;
  SoundFontFile? _soundFont;
  SoundFontPlayer? _player;
  SelectedPlaybackTarget? _selectedTarget;
  final Set<int> _auditionActiveKeys = {};

  bool _isPreloading = false;
  double _preloadProgress = 0.0;
  bool _isPreloaded = false;

  @override
  void initState() {
    super.initState();
    _tabController.addListener(_handleTabChanged);
    _selectedSource = _sources.first;
    _loadSoundFontEntry(_selectedSource);
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    final sf = _soundFont;
    if (sf == null) return;
    final tabIndex = _tabController.index;
    if (tabIndex == 0 &&
        _selectedTarget?.type != PlaybackTargetType.preset &&
        sf.presets.isNotEmpty) {
      _player?.stopMixerOutput();
      setState(() {
        _auditionActiveKeys.clear();
        _selectedTarget = SelectedPlaybackTarget.preset(sf.presets.first);
      });
    } else if (tabIndex == 1 &&
        _selectedTarget?.type != PlaybackTargetType.instrument &&
        sf.instruments.isNotEmpty) {
      _player?.stopMixerOutput();
      setState(() {
        _auditionActiveKeys.clear();
        _selectedTarget = SelectedPlaybackTarget.instrument(
          sf.instruments.first,
        );
      });
    } else if (tabIndex == 2 &&
        _selectedTarget?.type != PlaybackTargetType.sample &&
        sf.samples.isNotEmpty) {
      _player?.stopMixerOutput();
      setState(() {
        _auditionActiveKeys.clear();
        _selectedTarget = SelectedPlaybackTarget.sample(
          sf.samples.first,
          markedKey: sf.samples.first.originalPitch,
        );
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _player?.dispose();
    super.dispose();
  }

  void _selectPreviousItem() {
    final sf = _soundFont;
    if (sf == null) return;
    final tabIndex = _tabController.index;
    _player?.stopMixerOutput();

    switch (tabIndex) {
      case 0:
        if (sf.presets.isEmpty) return;
        final currentIndex =
            _selectedTarget?.type == PlaybackTargetType.preset &&
                _selectedTarget?.preset != null
            ? sf.presets.indexWhere(
                (p) =>
                    p.bank == _selectedTarget!.preset!.bank &&
                    p.program == _selectedTarget!.preset!.program &&
                    p.name == _selectedTarget!.preset!.name,
              )
            : 0;
        final prevIndex = (currentIndex <= 0)
            ? sf.presets.length - 1
            : currentIndex - 1;
        setState(() {
          _selectedTarget = SelectedPlaybackTarget.preset(
            sf.presets[prevIndex],
          );
        });
        break;
      case 1:
        if (sf.instruments.isEmpty) return;
        final currentIndex =
            _selectedTarget?.type == PlaybackTargetType.instrument &&
                _selectedTarget?.instrument != null
            ? sf.instruments.indexWhere(
                (i) =>
                    i.id == _selectedTarget!.instrument!.id ||
                    i.name == _selectedTarget!.instrument!.name,
              )
            : 0;
        final prevIndex = (currentIndex <= 0)
            ? sf.instruments.length - 1
            : currentIndex - 1;
        setState(() {
          _selectedTarget = SelectedPlaybackTarget.instrument(
            sf.instruments[prevIndex],
          );
        });
        break;
      case 2:
        if (sf.samples.isEmpty) return;
        final currentIndex =
            _selectedTarget?.type == PlaybackTargetType.sample &&
                _selectedTarget?.sample != null
            ? sf.samples.indexWhere((s) => s.id == _selectedTarget!.sample!.id)
            : 0;
        final prevIndex = (currentIndex <= 0)
            ? sf.samples.length - 1
            : currentIndex - 1;
        setState(() {
          _selectedTarget = SelectedPlaybackTarget.sample(
            sf.samples[prevIndex],
            markedKey: sf.samples[prevIndex].originalPitch,
          );
        });
        break;
    }
  }

  void _selectNextItem() {
    final sf = _soundFont;
    if (sf == null) return;
    final tabIndex = _tabController.index;
    _player?.stopMixerOutput();

    switch (tabIndex) {
      case 0:
        if (sf.presets.isEmpty) return;
        final currentIndex =
            _selectedTarget?.type == PlaybackTargetType.preset &&
                _selectedTarget?.preset != null
            ? sf.presets.indexWhere(
                (p) =>
                    p.bank == _selectedTarget!.preset!.bank &&
                    p.program == _selectedTarget!.preset!.program &&
                    p.name == _selectedTarget!.preset!.name,
              )
            : -1;
        final nextIndex = (currentIndex + 1) % sf.presets.length;
        setState(() {
          _selectedTarget = SelectedPlaybackTarget.preset(
            sf.presets[nextIndex],
          );
        });
        break;
      case 1:
        if (sf.instruments.isEmpty) return;
        final currentIndex =
            _selectedTarget?.type == PlaybackTargetType.instrument &&
                _selectedTarget?.instrument != null
            ? sf.instruments.indexWhere(
                (i) =>
                    i.id == _selectedTarget!.instrument!.id ||
                    i.name == _selectedTarget!.instrument!.name,
              )
            : -1;
        final nextIndex = (currentIndex + 1) % sf.instruments.length;
        setState(() {
          _selectedTarget = SelectedPlaybackTarget.instrument(
            sf.instruments[nextIndex],
          );
        });
        break;
      case 2:
        if (sf.samples.isEmpty) return;
        final currentIndex =
            _selectedTarget?.type == PlaybackTargetType.sample &&
                _selectedTarget?.sample != null
            ? sf.samples.indexWhere((s) => s.id == _selectedTarget!.sample!.id)
            : -1;
        final nextIndex = (currentIndex + 1) % sf.samples.length;
        setState(() {
          _selectedTarget = SelectedPlaybackTarget.sample(
            sf.samples[nextIndex],
            markedKey: sf.samples[nextIndex].originalPitch,
          );
        });
        break;
    }
  }

  Future<void> _startPreloadingAll() async {
    if (_player == null || _isPreloading || _isPreloaded) return;
    setState(() {
      _isPreloading = true;
      _preloadProgress = 0.0;
    });

    try {
      await _player!.preloadAll(
        onProgress: (progress, loaded, total) {
          if (mounted) {
            setState(() {
              _preloadProgress = progress;
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _isPreloading = false;
          _isPreloaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPreloading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error preloading samples: $e')));
      }
    }
  }

  Future<void> _loadSoundFontEntry(
    SoundFontSourceEntry entry, {
    bool askPreload = false,
  }) async {
    _player?.dispose();
    setState(() {
      _selectedSource = entry;
      _isLoading = true;
      _error = null;
      _soundFont = null;
      _player = null;
      _selectedTarget = null;
      _isPreloading = false;
      _preloadProgress = 0.0;
      _isPreloaded = false;
    });

    try {
      SoundFontFile sf;
      if (entry.isAsset) {
        sf = await SoundFontFile.fromAsset(entry.filePath!);
      } else if (entry.filePath != null) {
        sf = await SoundFontFile.fromFile(entry.filePath!);
      } else if (entry.fileBytes != null) {
        sf = await SoundFontFile.fromBytes(
          entry.fileBytes!,
          basePath: entry.label,
        );
      } else {
        throw Exception('Invalid SoundFont source configuration.');
      }

      final player = sf.createPlayer();
      SelectedPlaybackTarget? target;
      if (sf.presets.isNotEmpty) {
        target = SelectedPlaybackTarget.preset(sf.presets.first);
      } else if (sf.instruments.isNotEmpty) {
        target = SelectedPlaybackTarget.instrument(sf.instruments.first);
      } else if (sf.samples.isNotEmpty) {
        target = SelectedPlaybackTarget.sample(sf.samples.first);
      }

      setState(() {
        _soundFont = sf;
        _player = player;
        _selectedTarget = target;
        _isLoading = false;
      });

      if (askPreload && mounted && sf.samples.isNotEmpty) {
        final shouldPreload = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Preload SoundFont Samples?'),
            content: Text(
              'This SoundFont contains ${sf.samples.length} sample definitions.\n\n'
              '• Preload All: Loads and buffers all samples into RAM upfront for zero-latency playback.\n'
              '• Stream On-Demand: Streams samples on the fly as notes are played.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stream On-Demand'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Preload All'),
              ),
            ],
          ),
        );
        if (shouldPreload == true && mounted) {
          _startPreloadingAll();
        }
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickExternalSoundFont() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: [
          'sf2',
          'sf3',
          'sfz',
          'zip',
          'gz',
          'bz2',
          'tar',
          'tgz',
          'tbz2',
          'xz',
        ],
      );

      if (file == null) return;

      final name = file.name;
      final path = file.path;

      SoundFontSourceEntry entry;
      if (path != null && path.isNotEmpty) {
        entry = SoundFontSourceEntry.file(path, name: name);
      } else {
        final bytes = await file.readAsBytes();
        entry = SoundFontSourceEntry.bytes(
          bytes,
          id: 'custom_$name',
          label: name,
        );
      }

      final existingIndex = _sources.indexWhere((s) => s.id == entry.id);
      if (existingIndex >= 0) {
        _selectedSource = _sources[existingIndex];
      } else {
        _sources.add(entry);
        _selectedSource = entry;
      }

      await _loadSoundFontEntry(_selectedSource, askPreload: true);
    } catch (e) {
      setState(() {
        _error = 'Error picking file: $e';
      });
    }
  }

  Future<void> _pickExternalSfzFolder() async {
    try {
      final dirPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select Folder containing .sfz and audio files',
      );

      if (dirPath == null || dirPath.isEmpty) return;

      final dir = Directory(dirPath);
      if (!dir.existsSync()) return;

      // Find all .sfz files inside the chosen directory
      final sfzFiles = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.sfz'))
          .toList();

      if (sfzFiles.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No .sfz files found inside "$dirPath"')),
          );
        }
        return;
      }

      File targetFile = sfzFiles.first;
      if (sfzFiles.length > 1 && mounted) {
        final chosen = await showDialog<File>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Select SFZ File'),
            children: sfzFiles
                .map(
                  (f) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, f),
                    child: Text(p.basename(f.path)),
                  ),
                )
                .toList(),
          ),
        );
        if (chosen != null) targetFile = chosen;
      }

      final name = p.basename(targetFile.path);
      final entry = SoundFontSourceEntry.file(targetFile.path, name: name);

      final existingIndex = _sources.indexWhere((s) => s.id == entry.id);
      if (existingIndex >= 0) {
        _selectedSource = _sources[existingIndex];
      } else {
        _sources.add(entry);
        _selectedSource = entry;
      }

      await _loadSoundFontEntry(_selectedSource, askPreload: true);
    } catch (e) {
      setState(() {
        _error = 'Error selecting folder: $e';
      });
    }
  }

  Future<SoundFontVoice> _playSample(SampleInfo sample, {int? key}) async {
    final effectiveKey =
        key ?? (sample.originalPitch > 0 ? sample.originalPitch : 60);
    if (_player == null) {
      return SoundFontVoice(key: effectiveKey, velocity: 100, handles: []);
    }
    return await _player!.playSample(sample, key: effectiveKey);
  }

  Future<SoundFontVoice> _playInstrument(
    Instrument instrument, {
    int key = 60,
  }) async {
    if (_player == null) {
      return SoundFontVoice(key: key, velocity: 100, handles: []);
    }
    return await _player!.playInstrument(instrument, key: key, velocity: 100);
  }

  Future<SoundFontVoice> _playPreset(Preset preset, {int key = 60}) async {
    if (_player == null) {
      return SoundFontVoice(key: key, velocity: 100, handles: []);
    }
    return await _player!.playPreset(preset, key: key, velocity: 100);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SoundFont Reader Inspector'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: 'Open SoundFont File or Folder',
            onSelected: (val) {
              if (val == 'file') {
                _pickExternalSoundFont();
              } else if (val == 'folder') {
                _pickExternalSfzFolder();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'file',
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file, size: 20),
                    SizedBox(width: 8),
                    Text('Open File (.sf2, .sf3, .zip, .tar...)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'folder',
                child: Row(
                  children: [
                    Icon(Icons.folder_open, size: 20),
                    SizedBox(width: 8),
                    Text('Open SFZ Folder'),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: DropdownButton<SoundFontSourceEntry>(
              value: _selectedSource,
              underline: const SizedBox(),
              items: _sources.map((src) {
                return DropdownMenuItem<SoundFontSourceEntry>(
                  value: src,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        src.isAsset
                            ? Icons.library_music
                            : Icons.insert_drive_file,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        src.label,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  _loadSoundFontEntry(val);
                }
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Keyboard Shortcuts Help',
            onPressed: () => showKeyBindingsHelpDialog(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Parsing SoundFont File...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 16),
              Text(
                'Error Loading SoundFont',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      );
    }

    final sf = _soundFont;
    if (sf == null) return const SizedBox();

    return Column(
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Chip(
                avatar: const Icon(Icons.music_note, size: 18),
                label: Text('Format: ${sf.format.name.toUpperCase()}'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sf.name ?? 'Unnamed SoundFont',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (sf.comment != null && sf.comment!.isNotEmpty)
                      Text(
                        sf.comment!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (_isPreloading)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: _preloadProgress > 0 ? _preloadProgress : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(_preloadProgress * 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              else if (_isPreloaded)
                const Chip(
                  avatar: Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Colors.greenAccent,
                  ),
                  label: Text('Preloaded'),
                )
              else
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.bolt, size: 18),
                  label: Text('Preload (${sf.samples.length})'),
                  onPressed: _startPreloadingAll,
                ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.tune), text: 'Presets'),
            Tab(icon: Icon(Icons.piano), text: 'Instruments'),
            Tab(icon: Icon(Icons.graphic_eq), text: 'Samples'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPresetsTab(sf),
              _buildInstrumentsTab(sf),
              _buildSamplesTab(sf),
            ],
          ),
        ),
        DockedPianoPanel(
          soundFont: sf,
          player: _player,
          selectedTarget: _selectedTarget,
          externalActiveKeys: _auditionActiveKeys,
          onPreviousItem: _selectPreviousItem,
          onNextItem: _selectNextItem,
        ),
      ],
    );
  }

  Widget _buildPresetsTab(SoundFontFile sf) {
    if (sf.presets.isEmpty) {
      return const Center(child: Text('No presets defined'));
    }
    return ListView.builder(
      itemCount: sf.presets.length,
      itemBuilder: (context, index) {
        final preset = sf.presets[index];
        final isSelected =
            _selectedTarget?.type == PlaybackTargetType.preset &&
            _selectedTarget?.preset?.name == preset.name &&
            _selectedTarget?.preset?.bank == preset.bank &&
            _selectedTarget?.preset?.program == preset.program;

        return ExpansionTile(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primaryContainer.withValues(alpha: 0.12),
          collapsedBackgroundColor: isSelected
              ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.22)
              : null,
          shape: isSelected
              ? RoundedRectangleBorder(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          collapsedShape: isSelected
              ? RoundedRectangleBorder(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          onExpansionChanged: (expanded) {
            if (expanded) {
              _player?.stopMixerOutput();
              setState(() {
                _auditionActiveKeys.clear();
                _selectedTarget = SelectedPlaybackTarget.preset(preset);
              });
            }
          },
          title: Text(
            '${preset.name} (Bank ${preset.bank}, Program ${preset.program})',
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          subtitle: Text('${preset.zones.length} Zones'),
          trailing: preset.zones.isNotEmpty
              ? null
              : HoldPlayButton(
                  key: ValueKey('play_preset_${preset.bank}_${preset.program}'),
                  tooltip: 'Hold to play Preset',
                  onStartPlay: () async {
                    await _player?.stopMixerOutput();
                    final key = preset.zones.isNotEmpty
                        ? (preset.zones.first.rootKey ?? 60)
                        : 60;
                    setState(() {
                      _selectedTarget = SelectedPlaybackTarget.preset(preset);
                      _auditionActiveKeys.clear();
                      _auditionActiveKeys.add(key);
                    });
                    return _playPreset(preset);
                  },
                  onStopPlay: (voice) async {
                    setState(() {
                      _auditionActiveKeys.clear();
                    });
                    await voice.release();
                  },
                ),
          children: preset.zones.map((zone) {
            final key =
                zone.rootKey ??
                ((zone.keyRangeMin + zone.keyRangeMax) ~/ 2).clamp(0, 127);
            final isZoneSelected =
                isSelected && _selectedTarget?.resolvedMarkedKey == key;
            return ListTile(
              dense: true,
              selected: isZoneSelected,
              selectedTileColor: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.15),
              onTap: () {
                _player?.stopMixerOutput();
                setState(() {
                  _auditionActiveKeys.clear();
                  _selectedTarget = SelectedPlaybackTarget.preset(
                    preset,
                    markedKey: key,
                  );
                });
              },
              leading: const Icon(Icons.layers, size: 18),
              title: Text(
                'Key Range: ${zone.keyRangeMin}..${zone.keyRangeMax} | Vel: ${zone.velRangeMin}..${zone.velRangeMax}',
              ),
              subtitle: Text(
                'RootKey: ${zone.rootKey ?? "-"} | Pan: ${zone.pan ?? 0.0} | Attenuation: ${zone.attenuation ?? 0.0} dB',
              ),
              trailing: HoldPlayButton(
                key: ValueKey('play_preset_${preset.bank}_${preset.program}_zone_$key'),
                size: 20,
                tooltip: 'Hold to play Note $key',
                onStartPlay: () async {
                  await _player?.stopMixerOutput();
                  setState(() {
                    _selectedTarget = SelectedPlaybackTarget.preset(
                      preset,
                      markedKey: key,
                    );
                    _auditionActiveKeys.clear();
                    _auditionActiveKeys.add(key);
                  });
                  return _playPreset(preset, key: key);
                },
                onStopPlay: (voice) async {
                  setState(() {
                    _auditionActiveKeys.remove(key);
                  });
                  await voice.release();
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildInstrumentsTab(SoundFontFile sf) {
    if (sf.instruments.isEmpty) {
      return const Center(child: Text('No instruments defined'));
    }
    return ListView.builder(
      itemCount: sf.instruments.length,
      itemBuilder: (context, index) {
        final inst = sf.instruments[index];
        final isSelected =
            _selectedTarget?.type == PlaybackTargetType.instrument &&
            (_selectedTarget?.instrument?.id == inst.id ||
                _selectedTarget?.instrument?.name == inst.name);

        return ExpansionTile(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primaryContainer.withValues(alpha: 0.12),
          collapsedBackgroundColor: isSelected
              ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.22)
              : null,
          shape: isSelected
              ? RoundedRectangleBorder(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          collapsedShape: isSelected
              ? RoundedRectangleBorder(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          onExpansionChanged: (expanded) {
            if (expanded) {
              _player?.stopMixerOutput();
              setState(() {
                _auditionActiveKeys.clear();
                _selectedTarget = SelectedPlaybackTarget.instrument(inst);
              });
            }
          },
          title: Text(
            inst.name,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          subtitle: Text('${inst.zones.length} Zones'),
          trailing: inst.zones.isNotEmpty
              ? null
              : HoldPlayButton(
                  key: ValueKey('play_inst_${inst.id}_${inst.name}'),
                  tooltip: 'Hold to play Instrument',
                  onStartPlay: () async {
                    await _player?.stopMixerOutput();
                    final key = inst.zones.isNotEmpty
                        ? (inst.zones.first.rootKey ?? 60)
                        : 60;
                    setState(() {
                      _selectedTarget = SelectedPlaybackTarget.instrument(inst);
                      _auditionActiveKeys.clear();
                      _auditionActiveKeys.add(key);
                    });
                    return _playInstrument(inst);
                  },
                  onStopPlay: (voice) async {
                    setState(() {
                      _auditionActiveKeys.clear();
                    });
                    await voice.release();
                  },
                ),
          children: inst.zones.map((zone) {
            final key =
                zone.rootKey ??
                ((zone.keyRangeMin + zone.keyRangeMax) ~/ 2).clamp(0, 127);
            final isZoneSelected =
                isSelected && _selectedTarget?.resolvedMarkedKey == key;
            return ListTile(
              dense: true,
              selected: isZoneSelected,
              selectedTileColor: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.15),
              onTap: () {
                _player?.stopMixerOutput();
                setState(() {
                  _auditionActiveKeys.clear();
                  _selectedTarget = SelectedPlaybackTarget.instrument(
                    inst,
                    markedKey: key,
                  );
                });
              },
              leading: const Icon(Icons.graphic_eq, size: 18),
              title: Text(
                'Sample ID: ${zone.sampleID ?? "-"} (${zone.sampleRef?.name ?? "N/A"})',
              ),
              subtitle: Text(
                'Key: ${zone.keyRangeMin}..${zone.keyRangeMax} | RootKey: ${zone.rootKey ?? "-"}',
              ),
              trailing: HoldPlayButton(
                key: ValueKey('play_inst_${inst.id}_zone_$key'),
                size: 20,
                tooltip: 'Hold to play Note $key',
                onStartPlay: () async {
                  await _player?.stopMixerOutput();
                  setState(() {
                    _selectedTarget = SelectedPlaybackTarget.instrument(
                      inst,
                      markedKey: key,
                    );
                    _auditionActiveKeys.clear();
                    _auditionActiveKeys.add(key);
                  });
                  return _playInstrument(inst, key: key);
                },
                onStopPlay: (voice) async {
                  setState(() {
                    _auditionActiveKeys.remove(key);
                  });
                  await voice.release();
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildSamplesTab(SoundFontFile sf) {
    if (sf.samples.isEmpty) {
      return const Center(child: Text('No samples defined'));
    }
    return ListView.builder(
      itemCount: sf.samples.length,
      itemBuilder: (context, index) {
        final sample = sf.samples[index];
        final isSelected =
            _selectedTarget?.type == PlaybackTargetType.sample &&
            _selectedTarget?.sample?.id == sample.id;

        return ListTile(
          selected: isSelected,
          selectedTileColor: Theme.of(
            context,
          ).colorScheme.primaryContainer.withValues(alpha: 0.2),
          onTap: () {
            _player?.stopMixerOutput();
            setState(() {
              _auditionActiveKeys.clear();
              _selectedTarget = SelectedPlaybackTarget.sample(
                sample,
                markedKey: sample.originalPitch,
              );
            });
          },
          title: Text(
            '${sample.name} [ID: ${sample.id}]',
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          subtitle: Text(
            'Rate: ${sample.sampleRate} Hz | '
            'Key: ${sample.originalPitch} | '
            'Compression: ${sample.compression.name.toUpperCase()}\n'
            '${sample.samplePath != null ? "Path: ${sample.samplePath}" : "Offset: ${sample.byteOffset}, Length: ${(sample.byteLength / 1024).toStringAsFixed(1)} KB"}\n'
            'channels: ${sample.channels} | '
            '${sample.isLeft
                ? "Left"
                : sample.isRight
                ? "Right"
                : sample.isMono
                ? "Mono"
                : "Stereo"} | Loop: ${sample.loopStart} - ${sample.loopEnd}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SampleWaveform(
                key: ValueKey('sample_waveform_${sample.id}'),
                soundFont: sf,
                sample: sample,
                player: _player,
                width: 220,
                height: 50,
              ),
              const SizedBox(width: 8),
              HoldPlayButton(
                key: ValueKey('play_sample_${sample.id}'),
                tooltip: 'Hold to play sample',
                onStartPlay: () async {
                  await _player?.stopMixerOutput();
                  final key =
                      sample.originalPitch > 0 ? sample.originalPitch : 60;
                  setState(() {
                    _selectedTarget = SelectedPlaybackTarget.sample(
                      sample,
                      markedKey: sample.originalPitch,
                    );
                    _auditionActiveKeys.clear();
                    _auditionActiveKeys.add(key);
                  });
                  return _playSample(sample, key: key);
                },
                onStopPlay: (voice) async {
                  final key =
                      sample.originalPitch > 0 ? sample.originalPitch : 60;
                  setState(() {
                    _auditionActiveKeys.remove(key);
                  });
                  await voice.release();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A button that plays sound on press/down and releases/stops when pointer is up or cancelled.
class HoldPlayButton extends StatefulWidget {
  final Future<SoundFontVoice> Function() onStartPlay;
  final Future<void> Function(SoundFontVoice voice)? onStopPlay;
  final String? tooltip;
  final double size;

  const HoldPlayButton({
    super.key,
    required this.onStartPlay,
    this.onStopPlay,
    this.tooltip,
    this.size = 24.0,
  });

  @override
  State<HoldPlayButton> createState() => _HoldPlayButtonState();
}

class _HoldPlayButtonState extends State<HoldPlayButton> {
  bool _isPlaying = false;
  SoundFontVoice? _activeVoice;

  Future<void> _start() async {
    if (_isPlaying) return;
    setState(() => _isPlaying = true);
    try {
      final voice = await widget.onStartPlay();
      if (!mounted || !_isPlaying) {
        // User already released before asynchronous start finished
        if (widget.onStopPlay != null) {
          await widget.onStopPlay!(voice);
        } else {
          await voice.release();
        }
        _activeVoice = null;
      } else {
        _activeVoice = voice;
      }
    } catch (_) {
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  Future<void> _stop() async {
    if (!_isPlaying) return;
    setState(() => _isPlaying = false);
    final voice = _activeVoice;
    _activeVoice = null;
    if (voice != null) {
      if (widget.onStopPlay != null) {
        await widget.onStopPlay!(voice);
      } else {
        await voice.release();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _isPlaying
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: widget.tooltip ?? 'Hold to play',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _start(),
        onTapUp: (_) => _stop(),
        onTapCancel: () => _stop(),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(
            _isPlaying ? Icons.volume_up : Icons.play_arrow,
            color: color,
            size: widget.size,
          ),
        ),
      ),
    );
  }
}
