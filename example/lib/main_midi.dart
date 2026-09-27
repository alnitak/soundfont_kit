import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:soundfont_kit/soundfont_kit.dart';

import 'piano/piano_keyboard.dart';
import 'piano/rotary_knob.dart';

void main() async {
  Logger.root.level = kDebugMode ? Level.INFO : Level.INFO;
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

  // Initialize SoLoud audio engine
  await SoLoud.instance.init(
    bufferSize: 1024,
    devicePeriodFrames: 128,
    renderAheadFrames: 0,
  );
  SoLoud.instance.setMaxActiveVoiceCount(512);
  SoLoud.instance.setAudioDeviceIdleTimeout(null);
  SoLoud.instance.setVisualizationEnabled(
    true,
    windowSize: 256,
    kind: VisualizationKind.fft,
    channel: VisualizationChannel.merged,
  );
  SoLoud.instance.setFftSmoothing(0.8);

  runApp(const MidiPlayerDemoApp());
}

class MidiPlayerDemoApp extends StatelessWidget {
  const MidiPlayerDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SoundFont Kit — MIDI Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF12141A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF1E212B),
        ),
      ),
      home: const MidiPlayerScreen(),
    );
  }
}

class MidiPlayerScreen extends StatefulWidget {
  const MidiPlayerScreen({super.key});

  @override
  State<MidiPlayerScreen> createState() => _MidiPlayerScreenState();
}

class _MidiPlayerScreenState extends State<MidiPlayerScreen> {
  SoundFontFile? _soundFont;
  SoundFontPlayer? _sfPlayer;
  MidiPlayer? _midiPlayer;
  MidiFile? _midiFile;

  String _soundFontName = 'Loading...';
  String _midiFileName = 'Moonlight Sonata (Default)';
  bool _isLoading = false;
  bool _isDragging = false;
  double _loadProgress = 0.0;
  String _loadStatus = '';

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isLooping = false;
  double _playbackSpeed = 1.0;
  double _currentBpm = 120.0;

  Preset? _forcedPreset;
  bool _forceSinglePreset = false;
  bool _showAllChannels = false;

  double _sustain = 1.0;

  // DAW Timeline Layout constants
  static const double _kTimelineZoom = 45.0; // Pixels per second
  static const double _kTrackHeight = 72.0;
  static const double _kHeaderWidth = 250.0;
  static const double _kRulerHeight = 28.0;

  late final ScrollController _headersVerticalController;
  late final ScrollController _lanesVerticalController;
  late final ScrollController _timelineHorizontalController;
  bool _isSyncingScroll = false;

  // Real-time active keys for piano visualization
  final Set<int> _activeKeys = {};
  final Map<int, DateTime> _channelActivity = {};

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<MidiPlaybackEvent>? _eventSub;
  Timer? _uiRefreshTimer;

  // Loaded SoundFont players pool available for multi-timbral and channel instrument overrides
  final Map<String, SoundFontPlayer> _loadedSoundFontPlayers = {};

  // Bundled asset soundfonts
  final List<String> _bundledSoundFonts = [
    'assets/Celesta_minimal.sf3',
    'assets/RatAttack.sf2',
    'assets/Pac-Man-W2_.sf2.zip',
    'assets/SFX_StarWars_weapons.SF2',
    'assets/TerribleDanger.sf2',
  ];

  @override
  void initState() {
    super.initState();
    _headersVerticalController = ScrollController();
    _lanesVerticalController = ScrollController();
    _timelineHorizontalController = ScrollController();

    _headersVerticalController.addListener(() {
      _syncVerticalScroll(_headersVerticalController, _lanesVerticalController);
    });
    _lanesVerticalController.addListener(() {
      _syncVerticalScroll(_lanesVerticalController, _headersVerticalController);
    });

    _initDefaultAssets();

    // UI pulse timer for channel activity LEDs
    _uiRefreshTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) {
        final now = DateTime.now();
        bool hasRecent = false;
        _channelActivity.removeWhere((_, time) {
          final isOld = now.difference(time).inMilliseconds > 300;
          if (!isOld) hasRecent = true;
          return isOld;
        });
        if (hasRecent || _activeKeys.isNotEmpty) {
          setState(() {});
        }
      }
    });
  }

  void _syncVerticalScroll(ScrollController source, ScrollController target) {
    if (_isSyncingScroll) return;
    if (!target.hasClients || !source.hasClients) return;
    _isSyncingScroll = true;
    target.jumpTo(source.offset.clamp(0.0, target.position.maxScrollExtent));
    _isSyncingScroll = false;
  }

  void _autoScrollTimelineIfNeeded() {
    if (!_isPlaying || !_timelineHorizontalController.hasClients) return;
    final currentX = (_position.inMicroseconds / 1000000.0) * _kTimelineZoom;
    final scrollOffset = _timelineHorizontalController.offset;
    final viewportWidth =
        _timelineHorizontalController.position.viewportDimension;

    if (currentX > scrollOffset + viewportWidth * 0.85 ||
        currentX < scrollOffset) {
      final targetOffset = math.max(0.0, currentX - viewportWidth * 0.2);
      _timelineHorizontalController.animateTo(
        targetOffset.clamp(
          0.0,
          _timelineHorizontalController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    _posSub?.cancel();
    _eventSub?.cancel();
    _midiPlayer?.dispose();
    _headersVerticalController.dispose();
    _lanesVerticalController.dispose();
    _timelineHorizontalController.dispose();
    for (final p in _loadedSoundFontPlayers.values) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _initDefaultAssets() async {
    setState(() {
      _isLoading = true;
      _loadStatus = 'Loading default SoundFont and MIDI...';
    });

    try {
      // 1. Load default SoundFont
      await _loadSoundFontFromAsset('assets/Celesta_minimal.sf3');

      // 2. Load bundled Moonlight Sonata MIDI
      await _loadMidiFromAsset('assets/Piano Sonata n14 op27 - Moonlight.mid');
    } catch (e) {
      dev.log('Error loading default assets: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSoundFontFromAsset(String assetPath) async {
    final sf = await SoundFontFile.fromAsset(assetPath);
    await _applySoundFont(sf, p.basename(assetPath));
  }

  Future<void> _loadSoundFontFromFile(File file) async {
    final sf = await SoundFontFile.fromFile(file.path);
    await _applySoundFont(sf, p.basename(file.path));
  }

  Future<SoundFontPlayer?> _loadSoundFontPlayerFromFile(File file) async {
    final name = p.basename(file.path);
    if (_loadedSoundFontPlayers.containsKey(name)) {
      return _loadedSoundFontPlayers[name];
    }
    try {
      final sf = await SoundFontFile.fromFile(file.path);
      final player = sf.createPlayer(
        options: const SoundFontPlayerOptions(
          joinStereoChannels: true,
          cacheAudioSources: true,
        ),
      );
      player.sustain = _sustain;
      _loadedSoundFontPlayers[name] = player;
      return player;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load SoundFont: $e')));
      }
      return null;
    }
  }

  Future<SoundFontPlayer?> _loadSoundFontPlayerFromAsset(
    String assetPath,
  ) async {
    final name = p.basename(assetPath);
    if (_loadedSoundFontPlayers.containsKey(name)) {
      return _loadedSoundFontPlayers[name];
    }
    try {
      final sf = await SoundFontFile.fromAsset(assetPath);
      final player = sf.createPlayer(
        options: const SoundFontPlayerOptions(
          joinStereoChannels: true,
          cacheAudioSources: true,
        ),
      );
      player.sustain = _sustain;
      _loadedSoundFontPlayers[name] = player;
      return player;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load bundled SoundFont: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _applySoundFont(SoundFontFile sf, String name) async {
    final player = sf.createPlayer(
      options: const SoundFontPlayerOptions(
        joinStereoChannels: true,
        cacheAudioSources: true,
      ),
    );
    player.sustain = _sustain;

    _soundFont = sf;
    _sfPlayer = player;
    _soundFontName = name;
    _loadedSoundFontPlayers[name] = player;
    _forcedPreset = sf.presets.isNotEmpty ? sf.presets.first : null;

    if (_midiFile != null) {
      await _attachMidiPlayer();
    }
  }

  Future<void> _loadMidiFromAsset(String assetPath) async {
    final midi = await MidiReader.fromAsset(assetPath);
    _midiFile = midi;
    _midiFileName = p.basename(assetPath);
    await _attachMidiPlayer();
  }

  Future<void> _loadMidiFromFile(File file) async {
    final midi = await MidiReader.fromFile(file);
    _midiFile = midi;
    _midiFileName = p.basename(file.path);
    await _attachMidiPlayer();
  }

  Future<void> _attachMidiPlayer() async {
    if (_sfPlayer == null || _midiFile == null) return;

    _posSub?.cancel();
    _eventSub?.cancel();
    await _midiPlayer?.dispose();

    final mPlayer = MidiPlayer(player: _sfPlayer!);
    _midiPlayer = mPlayer;

    setState(() {
      _isLoading = true;
      _loadStatus = 'Preloading song samples...';
      _loadProgress = 0.0;
    });

    await mPlayer.load(
      _midiFile!,
      autoPreload: true,
      onPreloadProgress: (progress, loaded, total) {
        if (mounted) {
          setState(() {
            _loadProgress = progress;
            _loadStatus =
                'Preloading samples: $loaded / $total (${(progress * 100).toInt()}%)';
          });
        }
      },
    );

    _duration = mPlayer.duration;
    _position = Duration.zero;
    _isPlaying = false;
    _activeKeys.clear();

    _posSub = mPlayer.positionStream.listen((pos) {
      if (mounted) {
        setState(() {
          _position = pos;
        });
        _autoScrollTimelineIfNeeded();
      }
    });

    _eventSub = mPlayer.eventStream.listen((event) {
      if (!mounted) return;
      if (event.type == MidiPlaybackEventType.noteOn) {
        _activeKeys.add(event.note);
        _channelActivity[event.channel] = DateTime.now();
      } else if (event.type == MidiPlaybackEventType.noteOff) {
        _activeKeys.remove(event.note);
      } else if (event.type == MidiPlaybackEventType.tempoChange) {
        if (event.bpm != null) {
          _currentBpm = event.bpm!;
        }
      } else if (event.type == MidiPlaybackEventType.seek) {
        _activeKeys.clear();
        _channelActivity.clear();
        setState(() {});
      } else if (event.type == MidiPlaybackEventType.stateChange) {
        _isPlaying = mPlayer.isPlaying;
        if (!_isPlaying) {
          _activeKeys.clear();
          _channelActivity.clear();
        }
      }
    });

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickSoundFont() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['sf2', 'sf3', 'sfz', 'zip'],
    );
    if (file != null && file.path != null) {
      setState(() {
        _isLoading = true;
        _loadStatus = 'Loading SoundFont...';
      });
      await _loadSoundFontFromFile(File(file.path!));
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickMidiFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['mid', 'midi'],
    );
    if (file != null && file.path != null) {
      await _loadMidiFromFile(File(file.path!));
    }
  }

  Future<void> _handleDroppedFiles(List<XFile> files) async {
    if (files.isEmpty) return;

    final soundFontExts = {
      '.sf2',
      '.sf3',
      '.sfz',
      '.zip',
      '.gz',
      '.bz2',
      '.tar',
      '.tgz',
      '.tbz2',
      '.xz',
    };
    final midiExts = {'.mid', '.midi'};

    XFile? droppedSf;
    XFile? droppedMidi;

    for (final file in files) {
      final ext = p.extension(file.name).toLowerCase();
      if (soundFontExts.contains(ext) ||
          file.name.toLowerCase().endsWith('.sf2.zip')) {
        droppedSf = file;
      } else if (midiExts.contains(ext)) {
        droppedMidi = file;
      }
    }

    if (droppedSf == null && droppedMidi == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unsupported file format: "${files.map((f) => f.name).join(', ')}". Please drop SoundFont (.sf2, .sf3, .sfz) or MIDI (.mid, .midi) files.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Load dropped SoundFont first if present
    final sfFile = droppedSf;
    if (sfFile != null) {
      setState(() {
        _isLoading = true;
        _loadStatus = 'Loading SoundFont: ${sfFile.name}...';
      });
      if (sfFile.path.isNotEmpty) {
        await _loadSoundFontFromFile(File(sfFile.path));
      } else {
        final bytes = await sfFile.readAsBytes();
        final sf = await SoundFontFile.fromBytes(bytes);
        await _applySoundFont(sf, sfFile.name);
      }
    }

    // Load dropped MIDI file if present
    final midiTarget = droppedMidi;
    if (midiTarget != null) {
      setState(() {
        _isLoading = true;
        _loadStatus = 'Loading MIDI: ${midiTarget.name}...';
      });
      if (midiTarget.path.isNotEmpty) {
        await _loadMidiFromFile(File(midiTarget.path));
      } else {
        final bytes = await midiTarget.readAsBytes();
        final midi = MidiReader.fromBytes(bytes);
        _midiFile = midi;
        _midiFileName = midiTarget.name;
        await _attachMidiPlayer();
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 100;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.$ms';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.piano, color: Color(0xFF00E5FF)),
            SizedBox(width: 10),
            Text(
              'SoundFont Kit — MIDI Player',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF181B24),
        elevation: 2,
        actions: [
          // Bundled SoundFont quick selector
          PopupMenuButton<String>(
            tooltip: 'Load sample SoundFont',
            icon: const Icon(Icons.library_music_outlined),
            onSelected: (asset) async {
              setState(() {
                _isLoading = true;
                _loadStatus = 'Loading ${p.basename(asset)}...';
              });
              await _loadSoundFontFromAsset(asset);
              if (mounted) setState(() => _isLoading = false);
            },
            itemBuilder: (context) => _bundledSoundFonts.map((asset) {
              return PopupMenuItem(
                value: asset,
                child: Text(p.basename(asset)),
              );
            }).toList(),
          ),
          IconButton(
            tooltip: 'Pick SoundFont File (.sf2/.sf3/.sfz)',
            icon: const Icon(Icons.folder_open),
            onPressed: _pickSoundFont,
          ),
          IconButton(
            tooltip: 'Pick MIDI File (.mid/.midi)',
            icon: const Icon(Icons.audio_file),
            onPressed: _pickMidiFile,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: DropTarget(
        onDragEntered: (detail) => setState(() => _isDragging = true),
        onDragExited: (detail) => setState(() => _isDragging = false),
        onDragDone: (detail) async {
          setState(() => _isDragging = false);
          if (detail.files.isNotEmpty) {
            await _handleDroppedFiles(detail.files);
          }
        },
        child: Stack(
          children: [
            _isLoading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          color: Color(0xFF6C63FF),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _loadStatus,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white70,
                          ),
                        ),
                        if (_loadProgress > 0) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: 240,
                            child: LinearProgressIndicator(
                              value: _loadProgress,
                              backgroundColor: Colors.white10,
                              color: const Color(0xFF00E5FF),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Top Meta & Config Card
                      _buildHeaderCard(),

                      // Middle: 16-Channel Mixer Panel
                      Expanded(child: _buildChannelMixerPanel()),

                      // Transport Controls & Timeline Scrub
                      _buildTransportControls(),

                      // Docked Real-Time Visualizer Piano
                      _buildVisualizerPiano(),
                    ],
                  ),
            if (_isDragging)
              Container(
                color: Colors.black.withValues(alpha: 0.8),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 36,
                      vertical: 28,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E212B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF00E5FF),
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x6600E5FF),
                          blurRadius: 24,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.album_outlined,
                              size: 44,
                              color: Color(0xFF6C63FF),
                            ),
                            SizedBox(width: 16),
                            Icon(
                              Icons.music_note,
                              size: 44,
                              color: Color(0xFF00E5FF),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Drop SoundFont or MIDI File Here',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Supports .sf2, .sf3, .sfz, .zip and .mid, .midi',
                          style: TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1E212B),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // SoundFont Badge
              Expanded(
                child: _buildInfoChip(
                  icon: Icons.album_outlined,
                  label: 'SoundFont',
                  value: _soundFontName,
                  color: const Color(0xFF6C63FF),
                ),
              ),
              const SizedBox(width: 12),
              // MIDI File Badge
              Expanded(
                child: _buildInfoChip(
                  icon: Icons.music_note_outlined,
                  label: 'MIDI File',
                  value: _midiFileName,
                  color: const Color(0xFF00E5FF),
                ),
              ),
              const SizedBox(width: 12),
              // Tempo & Duration Badge
              _buildInfoChip(
                icon: Icons.speed,
                label: 'BPM / Duration',
                value:
                    '${_currentBpm.toStringAsFixed(0)} BPM | ${_formatDuration(_duration)}',
                color: Colors.amberAccent,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Playback mode toggle
              const Text(
                'Mode:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('General MIDI (Multi-Timbral)'),
                selected: !_forceSinglePreset,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _forceSinglePreset = false;
                      _midiPlayer?.forcedPresetOverride = null;
                    });
                  }
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Force Single Preset'),
                selected: _forceSinglePreset,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _forceSinglePreset = true;
                      _midiPlayer?.forcedPresetOverride = _forcedPreset;
                    });
                  }
                },
              ),
              const SizedBox(width: 12),
              if (_forceSinglePreset && _soundFont != null) ...[
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141720),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Preset>(
                        value: _forcedPreset,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1E212B),
                        items: _soundFont!.presets.map((p) {
                          return DropdownMenuItem(
                            value: p,
                            child: Text(
                              '[B:${p.bank} P:${p.program}] ${p.name}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (preset) {
                          setState(() {
                            _forcedPreset = preset;
                            _midiPlayer?.forcedPresetOverride = preset;
                          });
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141720),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _seekToSeconds(double seconds) {
    if (_midiPlayer == null || _duration <= Duration.zero) return;
    final maxSec = _duration.inMicroseconds / 1000000.0;
    final clamped = seconds.clamp(0.0, maxSec);
    final targetMicros = (clamped * 1000000.0).round();
    setState(() {
      _activeKeys.clear();
      _channelActivity.clear();
    });
    _midiPlayer?.seek(Duration(microseconds: targetMicros));
  }

  Widget _buildChannelMixerPanel() {
    if (_midiPlayer == null) {
      return const Center(child: Text('No MIDI loaded.'));
    }

    final usedList = (_midiPlayer!.usedChannels.toList()..sort());
    final activeChannels = _showAllChannels
        ? List.generate(16, (i) => i)
        : (usedList.isNotEmpty ? usedList : [0]);

    final totalDurationSeconds = math.max(
      1.0,
      _duration.inMicroseconds / 1000000.0,
    );
    final timelineWidth = math.max(
      800.0,
      totalDurationSeconds * _kTimelineZoom,
    );

    return Container(
      decoration: const BoxDecoration(color: Color(0xFF13151B)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left: Fixed-width Track Headers Column
          SizedBox(
            width: _kHeaderWidth,
            child: Column(
              children: [
                SizedBox(
                  height: _kRulerHeight,
                  child: _buildTracksHeaderCorner(
                    activeChannels.length,
                    usedList.length,
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: Colors.white12),
                Expanded(
                  child: ListView.builder(
                    controller: _headersVerticalController,
                    itemCount: activeChannels.length,
                    itemExtent: _kTrackHeight,
                    padding: EdgeInsets.zero,
                    physics: const ClampingScrollPhysics(),
                    itemBuilder: (context, index) {
                      return _buildTrackHeader(activeChannels[index]);
                    },
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1, color: Colors.white12),
          // Right: Horizontally Scrollable Timeline (Ruler + Track Lanes + Playhead)
          Expanded(
            child: SingleChildScrollView(
              controller: _timelineHorizontalController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: timelineWidth,
                child: Stack(
                  children: [
                    Column(
                      children: [
                        // Top: Time Ruler
                        SizedBox(
                          height: _kRulerHeight,
                          child: _buildTimeRuler(
                            totalDurationSeconds,
                            timelineWidth,
                          ),
                        ),
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.white12,
                        ),
                        // Track Lanes
                        Expanded(
                          child: ListView.builder(
                            controller: _lanesVerticalController,
                            itemCount: activeChannels.length,
                            itemExtent: _kTrackHeight,
                            padding: EdgeInsets.zero,
                            physics: const ClampingScrollPhysics(),
                            itemBuilder: (context, index) {
                              return _buildTrackLane(
                                activeChannels[index],
                                timelineWidth,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    // Playhead overlay extending from top of Time Ruler down through all track lanes
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _buildPlayheadOverlay(timelineWidth),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTracksHeaderCorner(int activeCount, int usedCount) {
    return Container(
      color: const Color(0xFF181B24),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const Icon(Icons.tune_outlined, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          Text(
            'TRACKS ($activeCount)',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: Colors.white70,
            ),
          ),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () {
              setState(() {
                _showAllChannels = !_showAllChannels;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _showAllChannels
                    ? const Color(0xFF6C63FF).withValues(alpha: 0.25)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _showAllChannels
                      ? const Color(0xFF6C63FF)
                      : Colors.white24,
                  width: 0.8,
                ),
              ),
              child: Text(
                _showAllChannels ? 'Used ($usedCount)' : 'All 16',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: _showAllChannels
                      ? const Color(0xFF00E5FF)
                      : Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openChannelInstrumentPicker(int chIndex) async {
    if (_midiPlayer == null || _sfPlayer == null) return;

    final chState = _midiPlayer!.channels[chIndex];
    final result = await showDialog<(SoundFontPlayer?, Preset?, bool)>(
      context: context,
      builder: (context) {
        return _ChannelInstrumentPickerDialog(
          channel: chIndex,
          defaultPlayer: _sfPlayer!,
          defaultSoundFontName: _soundFontName,
          loadedPlayers: _loadedSoundFontPlayers,
          bundledSoundFonts: _bundledSoundFonts,
          currentPlayer: chState.customPlayer,
          currentPreset: chState.presetOverride,
          onLoadFromFile: _loadSoundFontPlayerFromFile,
          onLoadFromAsset: _loadSoundFontPlayerFromAsset,
        );
      },
    );

    if (result != null) {
      final (player, preset, isReset) = result;
      if (isReset) {
        _midiPlayer!.clearChannelOverride(chIndex);
      } else if (player != null && preset != null) {
        _midiPlayer!.setChannelSoundFont(
          chIndex,
          customPlayer: player,
          preset: preset,
        );
        await _midiPlayer!.preloadChannelPreset(chIndex);
      }
      setState(() {});
    }
  }

  Widget _buildTrackHeader(int chIndex) {
    final chState = _midiPlayer!.channels[chIndex];
    final isDrums = chIndex == 9;
    final isActive = _channelActivity.containsKey(chIndex);
    final hasOverride = chState.presetOverride != null;

    final instrumentName = _midiPlayer!.getSuggestedInstrumentName(chIndex);

    return Container(
      height: _kTrackHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chState.isMuted
            ? const Color(0xFF14161E)
            : (isActive ? const Color(0xFF222838) : const Color(0xFF1A1D27)),
        border: Border(
          bottom: const BorderSide(color: Colors.white10, width: 1),
          left: BorderSide(
            color: isActive
                ? const Color(0xFF00E5FF)
                : (hasOverride
                      ? const Color(0xFF6C63FF)
                      : (chState.isSolo
                            ? Colors.amberAccent
                            : Colors.transparent)),
            width: 3,
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: LED, CH Name, CUSTOM chip, Mute, Solo
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? const Color(0xFF00E5FF)
                      : (chState.isMuted ? Colors.red : Colors.white24),
                  boxShadow: isActive
                      ? [
                          const BoxShadow(
                            color: Color(0xFF00E5FF),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'CH ${chIndex + 1}${isDrums ? " 🥁" : ""}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: isDrums ? Colors.orangeAccent : Colors.white,
                ),
              ),
              if (hasOverride) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text(
                    'MOD',
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              // Mute Button
              InkWell(
                onTap: () {
                  setState(() {
                    _midiPlayer!.setChannelMute(chIndex, !chState.isMuted);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: chState.isMuted ? Colors.red : Colors.white10,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'M',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: chState.isMuted ? Colors.white : Colors.white60,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Solo Button
              InkWell(
                onTap: () {
                  setState(() {
                    _midiPlayer!.setChannelSolo(chIndex, !chState.isSolo);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: chState.isSolo ? Colors.amber : Colors.white10,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'S',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: chState.isSolo ? Colors.black : Colors.white60,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          // Middle Row: Instrument Button
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => _openChannelInstrumentPicker(chIndex),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: hasOverride
                    ? const Color(0xFF6C63FF).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: hasOverride
                      ? const Color(0xFF00E5FF).withValues(alpha: 0.4)
                      : Colors.white10,
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      instrumentName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: hasOverride
                            ? const Color(0xFF00E5FF)
                            : Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.tune,
                    size: 11,
                    color: hasOverride
                        ? const Color(0xFF00E5FF)
                        : Colors.white38,
                  ),
                ],
              ),
            ),
          ),
          // Bottom Row: Compact Volume Slider
          SizedBox(
            height: 18,
            child: Row(
              children: [
                const Icon(Icons.volume_down, size: 10, color: Colors.white38),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 4,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 6,
                      ),
                    ),
                    child: Slider(
                      value: chState.volume,
                      onChanged: (val) {
                        setState(() {
                          _midiPlayer!.setChannelVolume(chIndex, val);
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackLane(int chIndex, double timelineWidth) {
    final notes = _midiPlayer?.getChannelNotes(chIndex) ?? const [];
    final instrumentName =
        _midiPlayer?.getSuggestedInstrumentName(chIndex) ??
        'Channel ${chIndex + 1}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        _seekToSeconds(details.localPosition.dx / _kTimelineZoom);
      },
      child: Container(
        height: _kTrackHeight,
        width: timelineWidth,
        decoration: const BoxDecoration(
          color: Color(0xFF13151B),
          border: Border(bottom: BorderSide(color: Colors.white10, width: 1)),
        ),
        child: Stack(
          children: [
            // Subtle beat grid
            Positioned.fill(
              child: CustomPaint(
                painter: _LaneGridPainter(zoom: _kTimelineZoom),
              ),
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
                  final clipLeft = clipStartSec * _kTimelineZoom;
                  final clipWidth = math.max(
                    20.0,
                    (clipEndSec - clipStartSec) * _kTimelineZoom,
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

  Widget _buildTimeRuler(double totalDurationSeconds, double timelineWidth) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        _seekToSeconds(details.localPosition.dx / _kTimelineZoom);
      },
      onHorizontalDragUpdate: (details) {
        _seekToSeconds(details.localPosition.dx / _kTimelineZoom);
      },
      child: Container(
        height: _kRulerHeight,
        width: timelineWidth,
        color: const Color(0xFF181B24),
        child: CustomPaint(
          size: Size(timelineWidth, _kRulerHeight),
          painter: _TimeRulerPainter(
            zoom: _kTimelineZoom,
            totalDurationSeconds: totalDurationSeconds,
          ),
        ),
      ),
    );
  }

  Widget _buildPlayheadOverlay(double timelineWidth) {
    final playheadX = (_position.inMicroseconds / 1000000.0) * _kTimelineZoom;

    return CustomPaint(
      size: Size(timelineWidth, double.infinity),
      painter: _PlayheadPainter(x: playheadX),
    );
  }

  Widget _buildTransportControls() {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF181B24),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        children: [
          // Scrub Slider + Timestamps
          Row(
            children: [
              SizedBox(
                width: 50,
                child: Text(
                  _formatDuration(_position),
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Colors.white70,
                  ),
                ),
              ),
              Expanded(
                child: Slider(
                  value: progress,
                  activeColor: const Color(0xFF6C63FF),
                  inactiveColor: Colors.white12,
                  onChangeStart: (_) {
                    setState(() {
                      _activeKeys.clear();
                      _channelActivity.clear();
                    });
                  },
                  onChanged: (val) {
                    if (_duration > Duration.zero) {
                      final targetMs = (val * _duration.inMilliseconds).round();
                      setState(() {
                        _activeKeys.clear();
                        _channelActivity.clear();
                      });
                      _midiPlayer?.seek(Duration(milliseconds: targetMs));
                    }
                  },
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Main Transport Buttons + Visualizer + Speed Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Stop
              IconButton(
                icon: const Icon(Icons.stop),
                iconSize: 28,
                tooltip: 'Stop',
                onPressed: () {
                  setState(() {
                    _isPlaying = false;
                    _activeKeys.clear();
                    _channelActivity.clear();
                  });
                  _midiPlayer?.stop();
                },
              ),
              const SizedBox(width: 8),
              // Play / Pause
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF6C63FF),
                ),
                child: IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  iconSize: 32,
                  color: Colors.white,
                  tooltip: _isPlaying ? 'Pause' : 'Play',
                  onPressed: () {
                    if (_isPlaying) {
                      setState(() {
                        _isPlaying = false;
                        _activeKeys.clear();
                        _channelActivity.clear();
                      });
                      _midiPlayer?.pause();
                    } else {
                      _midiPlayer?.play();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Loop
              IconButton(
                icon: Icon(
                  Icons.repeat,
                  color: _isLooping ? const Color(0xFF00E5FF) : Colors.white38,
                ),
                iconSize: 24,
                tooltip: 'Toggle Loop',
                onPressed: () {
                  setState(() {
                    _isLooping = !_isLooping;
                    _midiPlayer?.looping = _isLooping;
                  });
                },
              ),
              const SizedBox(width: 8),
              // Sustain Knob (unified for all SoundFonts)
              Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: RotaryKnob(
                  label: 'Sus',
                  value: _sustain,
                  min: 0.0,
                  max: 4.0,
                  defaultValue: 1.0,
                  unit: 'x',
                  size: 30.0,
                  enabled: true,
                  onChanged: (newSus) {
                    setState(() {
                      _sustain = newSus;
                    });
                    _sfPlayer?.sustain = newSus;
                    for (final p in _loadedSoundFontPlayers.values) {
                      p.sustain = newSus;
                    }
                  },
                ),
              ),
              // Centered FFT Visualizer between Sustain and Speed
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: SizedBox(
                      height: 64,
                      child: FftVisualizerWidget(isPlaying: _isPlaying),
                    ),
                  ),
                ),
              ),
              // Playback Speed Selector
              const Icon(Icons.speed, size: 16, color: Colors.white60),
              const SizedBox(width: 6),
              Text(
                'Speed: ${_playbackSpeed.toStringAsFixed(1)}x',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              SizedBox(
                width: 140,
                child: Slider(
                  value: _playbackSpeed,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  activeColor: Colors.amberAccent,
                  onChanged: (val) {
                    setState(() {
                      _playbackSpeed = val;
                      _midiPlayer?.speedMultiplier = val;
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVisualizerPiano() {
    return Container(
      height: 110,
      decoration: const BoxDecoration(
        color: Color(0xFF101218),
        border: Border(top: BorderSide(color: Colors.white24)),
      ),
      child: PianoKeyboard(
        startNote: 36, // C2
        keyCount: 49, // 4 octaves
        activeKeys: _activeKeys,
        onNoteDown: (note, vel) {
          if (_sfPlayer != null) {
            final preset =
                _forcedPreset ??
                (_soundFont != null && _soundFont!.presets.isNotEmpty
                    ? _soundFont!.presets.first
                    : null);
            if (preset != null) {
              _sfPlayer!.playPreset(preset, key: note, velocity: vel);
            }
          }
        },
        onNoteUp: (note) {
          _sfPlayer?.noteOff(note);
        },
      ),
    );
  }
}

/// Modal dialog for selecting a SoundFont and instrument preset for a specific MIDI channel.
class _ChannelInstrumentPickerDialog extends StatefulWidget {
  final int channel;
  final SoundFontPlayer defaultPlayer;
  final String defaultSoundFontName;
  final Map<String, SoundFontPlayer> loadedPlayers;
  final List<String> bundledSoundFonts;
  final SoundFontPlayer? currentPlayer;
  final Preset? currentPreset;
  final Future<SoundFontPlayer?> Function(File file) onLoadFromFile;
  final Future<SoundFontPlayer?> Function(String assetPath) onLoadFromAsset;

  const _ChannelInstrumentPickerDialog({
    required this.channel,
    required this.defaultPlayer,
    required this.defaultSoundFontName,
    required this.loadedPlayers,
    required this.bundledSoundFonts,
    required this.currentPlayer,
    required this.currentPreset,
    required this.onLoadFromFile,
    required this.onLoadFromAsset,
  });

  @override
  State<_ChannelInstrumentPickerDialog> createState() =>
      _ChannelInstrumentPickerDialogState();
}

class _ChannelInstrumentPickerDialogState
    extends State<_ChannelInstrumentPickerDialog> {
  late String _selectedSoundFontKey;
  late SoundFontPlayer _selectedPlayer;
  Preset? _selectedPreset;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  String _searchFilter = '';

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

    _searchController.addListener(() {
      setState(() {
        _searchFilter = _searchController.text.trim().toLowerCase();
      });
    });
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
                  Icons.music_note,
                  color: Color(0xFF00E5FF),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Assign Instrument — Channel ${widget.channel + 1}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 20,
                    color: Colors.white54,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(color: Colors.white12, height: 16),
            const SizedBox(height: 4),

            // SoundFont Selection Section
            Row(
              children: [
                const Text(
                  'SoundFont:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141720),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value:
                            widget.loadedPlayers.containsKey(
                              _selectedSoundFontKey,
                            )
                            ? _selectedSoundFontKey
                            : widget.loadedPlayers.keys.firstOrNull,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1E212B),
                        items: widget.loadedPlayers.entries.map((e) {
                          final sf = e.value.soundFont;
                          return DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              '${e.key} (${sf.format.name.toUpperCase()} • ${sf.presets.length} presets)',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (newKey) {
                          if (newKey != null &&
                              widget.loadedPlayers.containsKey(newKey)) {
                            final player = widget.loadedPlayers[newKey]!;
                            setState(() {
                              _selectedSoundFontKey = newKey;
                              _selectedPlayer = player;
                              _selectedPreset =
                                  player.soundFont.presets.isNotEmpty
                                  ? player.soundFont.presets.first
                                  : null;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.folder_open, size: 14),
                  label: const Text(
                    'From File...',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF282F45),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  onPressed: _pickSoundFontFile,
                ),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  tooltip: 'Load Bundled SoundFont',
                  icon: const Icon(
                    Icons.library_music,
                    size: 18,
                    color: Colors.white70,
                  ),
                  color: const Color(0xFF1E212B),
                  onSelected: _pickBundledSoundFont,
                  itemBuilder: (context) {
                    return widget.bundledSoundFonts.map((asset) {
                      return PopupMenuItem(
                        value: asset,
                        child: Text(
                          p.basename(asset),
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Search Bar for Presets
            TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 13, color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search preset by name, bank or program...',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: Colors.white38,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear,
                          size: 16,
                          color: Colors.white38,
                        ),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF141720),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Presets List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : presets.isEmpty
                  ? Center(
                      child: Text(
                        _selectedPlayer.soundFont.presets.isEmpty
                            ? 'No presets available in this SoundFont.'
                            : 'No presets match "$_searchFilter"',
                        style: const TextStyle(color: Colors.white38),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF141720),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: ListView.separated(
                        itemCount: presets.length,
                        separatorBuilder: (context, index) =>
                            const Divider(color: Colors.white10, height: 1),
                        itemBuilder: (context, index) {
                          final preset = presets[index];
                          final isSelected = _selectedPreset == preset;

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedPreset = preset;
                              });
                              _previewPreset(preset);
                            },
                            child: Container(
                              color: isSelected
                                  ? const Color(0xFF6C63FF).withAlpha(50)
                                  : Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(
                                              0xFF00E5FF,
                                            ).withAlpha(40)
                                          : Colors.white10,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '[B:${preset.bank} P:${preset.program}]',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? const Color(0xFF00E5FF)
                                            : Colors.white70,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      preset.name,
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
                                  ),
                                  IconButton(
                                    tooltip: 'Audition preset note (C4)',
                                    icon: const Icon(
                                      Icons.volume_up,
                                      size: 18,
                                      color: Color(0xFF00E5FF),
                                    ),
                                    onPressed: () => _previewPreset(preset),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle,
                                      size: 18,
                                      color: Color(0xFF00E5FF),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
            const SizedBox(height: 12),

            // Actions Footer
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(
                    Icons.refresh,
                    size: 16,
                    color: Colors.orangeAccent,
                  ),
                  label: const Text(
                    'Reset to Default MIDI Song Preset',
                    style: TextStyle(fontSize: 11, color: Colors.orangeAccent),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop((null, null, true));
                  },
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  label: Text('Apply to Channel ${widget.channel + 1}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _selectedPreset != null
                      ? () {
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

/// A shared [CustomPainter] that renders MIDI notes as horizontal bars inside a track lane clip.
class MidiNotesCustomPainter extends CustomPainter {
  const MidiNotesCustomPainter({
    required this.notes,
    required this.clipStart,
    required this.clipDuration,
    this.noteColor = Colors.white,
  });

  final List<MidiTimelineNote> notes;
  final Duration clipStart;
  final Duration clipDuration;
  final Color noteColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty || size.width <= 0 || size.height <= 0) return;

    var minPitch = 127;
    var maxPitch = 0;
    for (final n in notes) {
      if (n.note < minPitch) minPitch = n.note;
      if (n.note > maxPitch) maxPitch = n.note;
    }
    if (minPitch > maxPitch) return;

    // Minimum span of 12 semitones (one octave) to maintain visual proportions
    final span = math.max(12, maxPitch - minPitch + 1);
    final clipDurUs = math.max(1, clipDuration.inMicroseconds);
    final clipStartUs = clipStart.inMicroseconds;

    final paint = Paint()..style = PaintingStyle.fill;

    for (final n in notes) {
      final startOffsetUs = n.start.inMicroseconds - clipStartUs;
      final durUs = n.duration.inMicroseconds;

      final x = (startOffsetUs / clipDurUs) * size.width;
      final w = math.max(2.0, (durUs / clipDurUs) * size.width) - 1;

      // Pitch mapping: higher notes near top, lower notes near bottom
      final normalizedPitch = (n.note - minPitch) / span;
      final y = size.height - (normalizedPitch * (size.height - 4.0)) - 4.0;
      final h = math.max(2.0, size.height / span).clamp(2.0, 5.0);

      // Velocity modulates opacity
      final alpha = (0.5 + 0.5 * (n.velocity / 127.0)).clamp(0.4, 1.0);
      paint.color = noteColor.withValues(alpha: alpha);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          const Radius.circular(1.0),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MidiNotesCustomPainter oldDelegate) {
    return oldDelegate.notes != notes ||
        oldDelegate.clipStart != clipStart ||
        oldDelegate.clipDuration != clipDuration ||
        oldDelegate.noteColor != noteColor;
  }
}

class _TimeRulerPainter extends CustomPainter {
  const _TimeRulerPainter({
    required this.zoom,
    required this.totalDurationSeconds,
  });

  final double zoom;
  final double totalDurationSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = const Color.fromARGB(60, 249, 2, 2)
      ..strokeWidth = 1.0;
    final majorTickPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.0;

    // Major and minor intervals based on zoom
    final majorIntervalSec = zoom >= 60 ? 5 : (zoom >= 30 ? 10 : 20);
    final minorIntervalSec = zoom >= 60 ? 1 : (zoom >= 30 ? 2 : 5);

    final totalSec = totalDurationSeconds.ceil();

    const textStyle = TextStyle(
      color: Colors.white60,
      fontSize: 9,
      fontFamily: 'monospace',
    );

    for (int s = 0; s <= totalSec; s += minorIntervalSec) {
      final x = s * zoom;
      if (x > size.width) break;

      final isMajor = s % majorIntervalSec == 0;
      if (isMajor) {
        canvas.drawLine(
          Offset(x, size.height - 10),
          Offset(x, size.height),
          majorTickPaint,
        );

        final mins = s ~/ 60;
        final secs = s % 60;
        final label = '$mins:${secs.toString().padLeft(2, "0")}';

        final tp =
            TextPainter(
                text: const TextSpan(text: '', style: textStyle),
                textDirection: TextDirection.ltr,
              )
              ..text = TextSpan(text: label, style: textStyle)
              ..layout();
        tp.paint(canvas, Offset(x + 3, 3));
      } else {
        canvas.drawLine(
          Offset(x, size.height - 5),
          Offset(x, size.height),
          tickPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimeRulerPainter oldDelegate) {
    return oldDelegate.zoom != zoom ||
        oldDelegate.totalDurationSeconds != totalDurationSeconds;
  }
}

class _LaneGridPainter extends CustomPainter {
  const _LaneGridPainter({required this.zoom});

  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1.0;

    final intervalSec = zoom >= 40 ? 5 : 10;
    final totalSec = (size.width / zoom).ceil();

    for (int s = 0; s <= totalSec; s += intervalSec) {
      final x = s * zoom;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LaneGridPainter oldDelegate) {
    return oldDelegate.zoom != zoom;
  }
}

class _PlayheadPainter extends CustomPainter {
  const _PlayheadPainter({required this.x});

  final double x;

  @override
  void paint(Canvas canvas, Size size) {
    if (x < -10 || x > size.width + 10) return;

    final linePaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 1.5;

    // Vertical line
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

    // Playhead downward triangle at the top
    final headPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(x - 5, 0)
      ..lineTo(x + 5, 0)
      ..lineTo(x, 7)
      ..close();
    canvas.drawPath(path, headPaint);
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter oldDelegate) {
    return oldDelegate.x != x;
  }
}

/// Real-time FFT audio visualizer widget using a [CustomPainter] with gradient-colored bars.
class FftVisualizerWidget extends StatefulWidget {
  const FftVisualizerWidget({
    super.key,
    required this.isPlaying,
    this.barCount = 32,
  });

  final bool isPlaying;
  final int barCount;

  @override
  State<FftVisualizerWidget> createState() => _FftVisualizerWidgetState();
}

class _FftVisualizerWidgetState extends State<FftVisualizerWidget> {
  StreamSubscription<AudioVisualizationData>? _sub;
  late List<double> _bars;
  Timer? _decayTimer;

  @override
  void initState() {
    super.initState();
    _bars = List<double>.filled(widget.barCount, 0.0);
    _ensureVisualization();
    _sub = SoLoud.instance.audioVisualizationEvents.listen(_onAudioData);
  }

  void _ensureVisualization() {
    if (SoLoud.instance.isInitialized) {
      try {
        SoLoud.instance.setVisualizationEnabled(
          true,
          windowSize: 256,
          kind: VisualizationKind.fft,
          channel: VisualizationChannel.merged,
        );
        SoLoud.instance.setFftSmoothing(0.8);
      } catch (_) {}
    }
  }

  void _onAudioData(AudioVisualizationData data) {
    if (!mounted) return;
    final raw = data.fftData;
    if (raw == null || raw.isEmpty) return;

    final n = raw.length;
    final count = widget.barCount;
    final updated = List<double>.filled(count, 0.0);

    for (int i = 0; i < count; i++) {
      final t0 = math.pow(i / count, 2.0);
      final t1 = math.pow((i + 1) / count, 2.0);
      final startBin = (t0 * (n - 1)).floor().clamp(0, n - 1);
      final endBin = (t1 * (n - 1)).ceil().clamp(startBin + 1, n);

      double sum = 0.0;
      int binCount = 0;
      for (int b = startBin; b < endBin; b++) {
        sum += raw[b];
        binCount++;
      }
      final avg = binCount > 0 ? sum / binCount : raw[startBin];
      // Frequency boost: higher frequencies carry less energy, compensate smoothly
      final boost = 1.0 + (i / count) * 2.5;
      updated[i] = (avg * boost).clamp(0.0, 1.0);
    }

    setState(() {
      _bars = updated;
    });
  }

  @override
  void didUpdateWidget(covariant FftVisualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isPlaying && oldWidget.isPlaying) {
      _startDecay();
    }
  }

  void _startDecay() {
    _decayTimer?.cancel();
    _decayTimer = Timer.periodic(const Duration(milliseconds: 25), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      bool allZero = true;
      for (int i = 0; i < _bars.length; i++) {
        _bars[i] *= 0.82;
        if (_bars[i] > 0.005) {
          allZero = false;
        } else {
          _bars[i] = 0.0;
        }
      }
      if (allZero) {
        timer.cancel();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _decayTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
      child: CustomPaint(
        painter: _FftVisualizerPainter(bars: _bars),
        size: Size.infinite,
      ),
    );
  }
}

/// CustomPainter for FFT visualizer bars shaded with a gradient.
class _FftVisualizerPainter extends CustomPainter {
  _FftVisualizerPainter({required this.bars});

  final List<double> bars;

  static const Gradient _gradient = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      Color(0xFF6C63FF), // deep purple base
      Color(0xFF00E5FF), // cyan mid
      Color(0xFFFF2A85), // vivid pink peak
    ],
    stops: [0.0, 0.55, 1.0],
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    final count = bars.length;
    const spacing = 2.0;
    final totalSpacing = (count - 1) * spacing;
    final barWidth = (size.width - totalSpacing) / count;
    if (barWidth <= 0) return;

    final rect = Offset.zero & size;
    final activePaint = Paint()
      ..shader = _gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    final restingPaint = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    const minBarHeight = 1.5;
    final maxBarHeight = size.height;

    for (int i = 0; i < count; i++) {
      final x = i * (barWidth + spacing);
      final magnitude = bars[i].clamp(0.0, 1.0);

      if (magnitude > 0.01) {
        final h = magnitude * (maxBarHeight - minBarHeight) + minBarHeight;
        final y = size.height - h;
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, h),
          const Radius.circular(1.5),
        );
        canvas.drawRRect(rrect, activePaint);
      } else {
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - minBarHeight, barWidth, minBarHeight),
          const Radius.circular(1.5),
        );
        canvas.drawRRect(rrect, restingPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FftVisualizerPainter oldDelegate) {
    return true;
  }
}
