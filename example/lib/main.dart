import 'dart:developer' as dev;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:soundfont_reader/soundfont_reader.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:logging/logging.dart';
import 'piano/docked_piano_panel.dart';

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
  Widget build(BuildContext me) {
    return MaterialApp(
      title: 'SoundFont Reader Demo',
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

class SoundFontInspectorScreen extends StatefulWidget {
  const SoundFontInspectorScreen({super.key});

  @override
  State<SoundFontInspectorScreen> createState() =>
      _SoundFontInspectorScreenState();
}

class _SoundFontInspectorScreenState extends State<SoundFontInspectorScreen> {
  final List<String> _assetFiles = [
    'assets/Celesta (minimal).sf2',
    'assets/Celesta (minimal).sf3',
    'assets/Celesta (converted).sfz+flac.zip',
  ];

  late String _selectedAsset;
  bool _isLoading = false;
  String? _error;
  SoundFontFile? _soundFont;
  SoundFontPlayer? _player;
  SelectedPlaybackTarget? _selectedTarget;
  SampleInfo? _selectedSample;
  String? _sampleByteDetails;

  @override
  void initState() {
    super.initState();
    _selectedAsset = _assetFiles.first;
    _loadSoundFont(_selectedAsset);
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _loadSoundFont(String assetPath) async {
    _player?.dispose();
    setState(() {
      _isLoading = true;
      _error = null;
      _soundFont = null;
      _player = null;
      _selectedTarget = null;
      _selectedSample = null;
      _sampleByteDetails = null;
    });

    try {
      final sf = await SoundFontFile.fromAsset(assetPath);
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
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _inspectSampleBytes(SampleInfo sample) async {
    if (_soundFont == null) return;
    setState(() {
      _selectedSample = sample;
      _sampleByteDetails = 'Loading sample bytes...';
    });

    try {
      final bytes = await _soundFont!.getSampleBytes(sample);
      final magic = bytes.length >= 4
          ? bytes
                .sublist(0, 4)
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(' ')
          : 'None';
      setState(() {
        _sampleByteDetails =
            'Loaded ${bytes.length} bytes.\nFirst 4 Hex Bytes: [$magic]\nCompression: ${sample.compression.name}';
      });
    } catch (e) {
      setState(() {
        _sampleByteDetails = 'Error reading sample bytes: $e';
      });
    }
  }

  Future<SoundFontVoice> _playSample(SampleInfo sample) async {
    if (_player == null) {
      return SoundFontVoice(key: 60, velocity: 100, handles: []);
    }
    return await _player!.playSample(sample);
  }

  Future<SoundFontVoice> _playInstrument(Instrument instrument, {int key = 60}) async {
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
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: DropdownButton<String>(
              value: _selectedAsset,
              underline: const SizedBox(),
              items: _assetFiles.map((asset) {
                final label = asset.split('/').last;
                return DropdownMenuItem<String>(
                  value: asset,
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedAsset = val);
                  _loadSoundFont(val);
                }
              },
            ),
          ),
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

    return DefaultTabController(
      length: 3,
      child: Column(
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.tune), text: 'Presets'),
              Tab(icon: Icon(Icons.piano), text: 'Instruments'),
              Tab(icon: Icon(Icons.graphic_eq), text: 'Samples'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildPresetsTab(sf),
                _buildInstrumentsTab(sf),
                _buildSamplesTab(sf),
              ],
            ),
          ),
          DockedPianoPanel(
            player: _player,
            selectedTarget: _selectedTarget,
          ),
        ],
      ),
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
        final isSelected = _selectedTarget?.type == PlaybackTargetType.preset &&
            _selectedTarget?.preset?.name == preset.name &&
            _selectedTarget?.preset?.bank == preset.bank &&
            _selectedTarget?.preset?.program == preset.program;

        return ExpansionTile(
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
              setState(() {
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
          trailing: HoldPlayButton(
            tooltip: 'Hold to play Preset',
            onStartPlay: () {
              setState(() {
                _selectedTarget = SelectedPlaybackTarget.preset(preset);
              });
              return _playPreset(preset);
            },
          ),
          children: preset.zones.map((zone) {
            final key = zone.rootKey ??
                ((zone.keyRangeMin + zone.keyRangeMax) ~/ 2).clamp(0, 127);
            final isZoneSelected = isSelected &&
                _selectedTarget?.resolvedMarkedKey == key;
            return ListTile(
              dense: true,
              selected: isZoneSelected,
              selectedTileColor: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.15),
              onTap: () {
                setState(() {
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
                size: 20,
                tooltip: 'Hold to play Note $key',
                onStartPlay: () {
                  setState(() {
                    _selectedTarget = SelectedPlaybackTarget.preset(
                      preset,
                      markedKey: key,
                    );
                  });
                  return _playPreset(preset, key: key);
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
                _selectedTarget?.instrument?.name == inst.name;

        return ExpansionTile(
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
              setState(() {
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
          trailing: HoldPlayButton(
            tooltip: 'Hold to play Instrument',
            onStartPlay: () {
              setState(() {
                _selectedTarget = SelectedPlaybackTarget.instrument(inst);
              });
              return _playInstrument(inst);
            },
          ),
          children: inst.zones.map((zone) {
            final key = zone.rootKey ??
                ((zone.keyRangeMin + zone.keyRangeMax) ~/ 2).clamp(0, 127);
            final isZoneSelected = isSelected &&
                _selectedTarget?.resolvedMarkedKey == key;
            return ListTile(
              dense: true,
              selected: isZoneSelected,
              selectedTileColor: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.15),
              onTap: () {
                setState(() {
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
                size: 20,
                tooltip: 'Hold to play Note $key',
                onStartPlay: () {
                  setState(() {
                    _selectedTarget = SelectedPlaybackTarget.instrument(
                      inst,
                      markedKey: key,
                    );
                  });
                  return _playInstrument(inst, key: key);
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
    return Column(
      children: [
        if (_selectedSample != null && _sampleByteDetails != null)
          Card(
            margin: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sample Byte Inspection: ${_selectedSample!.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _sampleByteDetails!,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: sf.samples.length,
            itemBuilder: (context, index) {
              final sample = sf.samples[index];
              final isSelected =
                  _selectedTarget?.type == PlaybackTargetType.sample &&
                      _selectedTarget?.sample?.id == sample.id;

              return ListTile(
                selected: isSelected,
                selectedTileColor: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.2),
                onTap: () {
                  setState(() {
                    _selectedSample = sample;
                    _selectedTarget = SelectedPlaybackTarget.sample(
                      sample,
                      markedKey: sample.originalPitch,
                    );
                  });
                },
                title: Text(
                  '${sample.name} [ID: ${sample.id}]',
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                subtitle: Text(
                  'Rate: ${sample.sampleRate} Hz | '
                  'Key: ${sample.originalPitch} | '
                  'Compression: ${sample.compression.name.toUpperCase()}\n'
                  '${sample.samplePath != null ? "Path: ${sample.samplePath}" : "Offset: ${sample.byteOffset}, Length: ${(sample.byteLength / 1024).toStringAsFixed(1)} KB"}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HoldPlayButton(
                      tooltip: 'Hold to play sample',
                      onStartPlay: () {
                        setState(() {
                          _selectedSample = sample;
                          _selectedTarget = SelectedPlaybackTarget.sample(
                            sample,
                            markedKey: sample.originalPitch,
                          );
                        });
                        return _playSample(sample);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.file_download),
                      tooltip: 'Read Sample Bytes',
                      onPressed: () => _inspectSampleBytes(sample),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
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
