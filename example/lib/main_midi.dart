import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:soundfont_kit/soundfont_kit.dart';

import 'midi/midi.dart';
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
  int _transpose = 0;
  Duration? _loopStart;
  Duration? _loopEnd;

  String? _currentChord;
  MidiLyricSpan? _currentLyric;

  double _modWheelValue = 0.0;
  double _pitchBendValue = 0.0;
  bool _sostenutoPedalOn = false;
  bool _softPedalOn = false;

  StreamSubscription<String?>? _chordSub;
  StreamSubscription<MidiLyricSpan>? _lyricSub;

  // DAW Timeline Layout constants
  static const double _kTimelineZoom = 45.0; // Pixels per second
  static const double _kTrackHeight = 72.0;
  static const double _kHeaderWidth = 250.0;
  static const double _kRulerHeight = 28.0;

  late final ScrollController _headersVerticalController;
  late final ScrollController _lanesVerticalController;
  late final ScrollController _timelineHorizontalController;
  bool _isSyncingScroll = false;
  bool _isAutoScrolling = false;

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

  void _autoScrollTimelineIfNeeded({bool jump = false}) {
    if (!_timelineHorizontalController.hasClients) return;
    final isPlaying = _midiPlayer?.isPlaying ?? false;
    if (!isPlaying && !jump) return;
    if (_isAutoScrolling && !jump) return;

    final currentX = (_position.inMicroseconds / 1000000.0) * _kTimelineZoom;
    final scrollOffset = _timelineHorizontalController.offset;
    final viewportWidth =
        _timelineHorizontalController.position.viewportDimension;
    if (viewportWidth <= 0) return;

    final maxScroll = _timelineHorizontalController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    if (currentX > scrollOffset + viewportWidth * 0.85 ||
        currentX < scrollOffset ||
        jump) {
      final targetOffset = math.max(0.0, currentX - viewportWidth * 0.2);
      final clampedTarget = targetOffset.clamp(0.0, maxScroll);

      if ((clampedTarget - scrollOffset).abs() > 2.0) {
        if (jump) {
          _timelineHorizontalController.jumpTo(clampedTarget);
        } else {
          _isAutoScrolling = true;
          _timelineHorizontalController
              .animateTo(
                clampedTarget,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
              )
              .catchError((_) {})
              .whenComplete(() {
                _isAutoScrolling = false;
              });
        }
      }
    }
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    _posSub?.cancel();
    _eventSub?.cancel();
    _chordSub?.cancel();
    _lyricSub?.cancel();
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
    _chordSub?.cancel();
    _lyricSub?.cancel();
    await _midiPlayer?.dispose();

    final mPlayer = MidiPlayer(player: _sfPlayer!);
    mPlayer.transpose = _transpose;
    mPlayer.speedMultiplier = _playbackSpeed;
    mPlayer.looping = _isLooping;
    if (_loopStart != null && _loopEnd != null) {
      mPlayer.setLoopRange(_loopStart!, _loopEnd!);
    }
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
    _currentChord = null;
    _currentLyric = null;

    _posSub = mPlayer.positionStream.listen((pos) {
      if (mounted) {
        setState(() {
          _position = pos;
        });
        _autoScrollTimelineIfNeeded();
      }
    });

    _chordSub = mPlayer.chordStream.listen((chord) {
      if (mounted && _currentChord != chord) {
        setState(() {
          _currentChord = chord;
        });
      }
    });

    _lyricSub = mPlayer.lyricStream.listen((lyric) {
      if (mounted) {
        setState(() {
          _currentLyric = lyric;
        });
      }
    });

    _eventSub = mPlayer.eventStream.listen((event) {
      if (!mounted) return;
      if (event.type == MidiPlaybackEventType.noteOn) {
        _activeKeys.add(event.note);
        _channelActivity[event.channel] = DateTime.now();
      } else if (event.type == MidiPlaybackEventType.noteOff) {
        _activeKeys.remove(event.note);
      } else if (event.type == MidiPlaybackEventType.controlChange) {
        if (event.controller == 1) {
          _modWheelValue = (event.value ?? 0) / 127.0;
        } else if (event.controller == 66) {
          _sostenutoPedalOn = (event.value ?? 0) >= 64;
        } else if (event.controller == 67) {
          _softPedalOn = (event.value ?? 0) >= 64;
        }
      } else if (event.type == MidiPlaybackEventType.pitchBend) {
        _pitchBendValue = ((event.value ?? 8192) - 8192) / 8192.0;
      } else if (event.type == MidiPlaybackEventType.tempoChange) {
        if (event.bpm != null) {
          _currentBpm = event.bpm!;
        }
      } else if (event.type == MidiPlaybackEventType.seek) {
        _activeKeys.clear();
        _channelActivity.clear();
        _currentChord = null;
        _currentLyric = null;
        _pitchBendValue = 0.0;
        _modWheelValue = 0.0;
        _sostenutoPedalOn = false;
        _softPedalOn = false;
        setState(() {});
      } else if (event.type == MidiPlaybackEventType.stateChange) {
        setState(() {
          _isPlaying = mPlayer.isPlaying;
          if (!_isPlaying) {
            _activeKeys.clear();
            _channelActivity.clear();
            _currentChord = null;
            _pitchBendValue = 0.0;
            _modWheelValue = 0.0;
            _sostenutoPedalOn = false;
            _softPedalOn = false;
          }
        });
      }
    });

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _setLoopStart() {
    setState(() {
      _loopStart = _position;
      if (_loopEnd != null) {
        if (_loopStart! >= _loopEnd!) {
          _loopEnd = null;
          _midiPlayer?.clearLoopRange();
        } else {
          _midiPlayer?.setLoopRange(_loopStart!, _loopEnd!);
        }
      }
    });
  }

  void _setLoopEnd() {
    setState(() {
      _loopEnd = _position;
      if (_loopStart != null) {
        if (_loopEnd! <= _loopStart!) {
          _loopStart = null;
          _midiPlayer?.clearLoopRange();
        } else {
          _midiPlayer?.setLoopRange(_loopStart!, _loopEnd!);
        }
      }
    });
  }

  void _clearLoopRange() {
    setState(() {
      _loopStart = null;
      _loopEnd = null;
      _midiPlayer?.clearLoopRange();
    });
  }

  void _setTranspose(int newTranspose) {
    final clamped = newTranspose.clamp(-12, 12);
    setState(() {
      _transpose = clamped;
      _midiPlayer?.transpose = clamped;
    });
  }

  Future<void> _pickSoundFont() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['sf2', 'sf3', 'sfz', 'zip'],
    );
    if (file != null) {
      setState(() {
        _isLoading = true;
        _loadStatus = 'Loading SoundFont: ${file.name}...';
        _loadProgress = 0.0;
      });
      try {
        if (!kIsWeb && file.path != null && file.path!.isNotEmpty) {
          await _loadSoundFontFromFile(File(file.path!));
        } else {
          final bytes = await file.readAsBytes();
          final sf = await SoundFontFile.fromBytes(bytes);
          await _applySoundFont(sf, file.name);
        }
      } catch (e, st) {
        dev.log('Error loading picked SoundFont: $e\n$st');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load SoundFont: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _pickMidiFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['mid', 'midi'],
    );
    if (file != null) {
      setState(() {
        _isLoading = true;
        _loadStatus = 'Loading MIDI: ${file.name}...';
        _loadProgress = 0.0;
      });
      try {
        if (!kIsWeb && file.path != null && file.path!.isNotEmpty) {
          await _loadMidiFromFile(File(file.path!));
        } else {
          final bytes = await file.readAsBytes();
          final midi = MidiReader.fromBytes(bytes);
          _midiFile = midi;
          _midiFileName = file.name;
          await _attachMidiPlayer();
        }
      } catch (e, st) {
        dev.log('Error loading picked MIDI: $e\n$st');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load MIDI: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
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

    try {
      // Load dropped SoundFont first if present
      final sfFile = droppedSf;
      if (sfFile != null) {
        setState(() {
          _isLoading = true;
          _loadStatus = 'Loading SoundFont: ${sfFile.name}...';
          _loadProgress = 0.0;
        });
        if (!kIsWeb && sfFile.path.isNotEmpty) {
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
          _loadProgress = 0.0;
        });
        if (!kIsWeb && midiTarget.path.isNotEmpty) {
          await _loadMidiFromFile(File(midiTarget.path));
        } else {
          final bytes = await midiTarget.readAsBytes();
          final midi = MidiReader.fromBytes(bytes);
          _midiFile = midi;
          _midiFileName = midiTarget.name;
          await _attachMidiPlayer();
        }
      }
    } catch (e, st) {
      dev.log('Error loading dropped files: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load dropped file: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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

                      // Synchronized Karaoke Lyrics & Rehearsal Markers Banner
                      if ((_midiPlayer?.timeline?.hasLyrics ?? false) ||
                          _currentLyric != null)
                        _buildKaraokeBanner(),

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
              const SizedBox(width: 10),
              // MIDI File Badge
              Expanded(
                child: _buildInfoChip(
                  icon: Icons.music_note_outlined,
                  label: 'MIDI File',
                  value: _midiFileName,
                  color: const Color(0xFF00E5FF),
                ),
              ),
              const SizedBox(width: 10),
              // Tempo & Duration Badge
              _buildInfoChip(
                icon: Icons.speed,
                label: 'BPM / Duration',
                value:
                    '${_currentBpm.toStringAsFixed(0)} BPM | ${_formatDuration(_duration)}',
                color: Colors.amberAccent,
              ),
              const SizedBox(width: 10),
              // Detected Chord Badge
              _buildChordChip(),
              const SizedBox(width: 10),
              // Expressive MIDI Controllers
              _buildControllersCluster(),
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

  Widget _buildChordChip() {
    final chord = _currentChord;
    final hasChord = chord != null && chord.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141720),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasChord ? const Color(0xFF00E5FF) : Colors.white12,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_note,
            size: 18,
            color: hasChord ? const Color(0xFF00E5FF) : Colors.white38,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Detected Chord',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white54,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hasChord ? chord : '—',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: hasChord ? const Color(0xFF00E5FF) : Colors.white38,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControllersCluster() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141720),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'MIDI Controllers',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white54,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildControllerLed(
                label: 'MOD',
                isActive: _modWheelValue > 0.05,
                activeColor: const Color(0xFF00E5FF),
                tooltip:
                    'CC 1 Modulation Wheel (Amplitude Modulator Filter): ${(_modWheelValue * 100).toInt()}%',
              ),
              const SizedBox(width: 6),
              _buildControllerLed(
                label: 'BEND',
                isActive: _pitchBendValue.abs() > 0.05,
                activeColor: Colors.amberAccent,
                tooltip:
                    'Pitch Bend Wheel: ${_pitchBendValue >= 0 ? "+" : ""}${(_pitchBendValue * 100).toInt()}%',
              ),
              const SizedBox(width: 6),
              _buildControllerLed(
                label: 'SOST',
                isActive: _sostenutoPedalOn,
                activeColor: const Color(0xFFE040FB),
                tooltip: 'CC 66 Sostenuto Pedal',
              ),
              const SizedBox(width: 6),
              _buildControllerLed(
                label: 'SOFT',
                isActive: _softPedalOn,
                activeColor: const Color(0xFF69F0AE),
                tooltip: 'CC 67 Soft Pedal (Una Corda)',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControllerLed({
    required String label,
    required bool isActive,
    required Color activeColor,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withAlpha(50)
              : Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? activeColor : Colors.white24,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isActive ? activeColor : Colors.white38,
          ),
        ),
      ),
    );
  }

  Widget _buildKaraokeBanner() {
    final span = _currentLyric;
    final text =
        span?.text ??
        (_midiPlayer?.timeline?.hasLyrics == true
            ? '♪ (Awaiting lyrics) ♪'
            : '');
    final type = span?.type;
    final isMarker =
        type == MidiLyricType.marker || type == MidiLyricType.cuePoint;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF141720),
        border: Border(
          top: BorderSide(color: Colors.white10),
          bottom: BorderSide(color: Colors.white10),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isMarker ? Icons.bookmark : Icons.mic_external_on,
            size: 16,
            color: isMarker ? Colors.amberAccent : const Color(0xFF00E5FF),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
                color: isMarker ? Colors.amberAccent : Colors.white,
                shadows: [
                  Shadow(
                    color: isMarker
                        ? Colors.amberAccent.withAlpha(120)
                        : const Color(0xFF00E5FF).withAlpha(140),
                    blurRadius: 8,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
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
    final newPos = Duration(microseconds: targetMicros);
    setState(() {
      _position = newPos;
      _activeKeys.clear();
      _channelActivity.clear();
    });
    _midiPlayer?.seek(newPos);
    _autoScrollTimelineIfNeeded(jump: true);
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
    return MidiTracksHeaderCorner(
      activeCount: activeCount,
      usedCount: usedCount,
      showAllChannels: _showAllChannels,
      onToggleShowAllChannels: () {
        setState(() {
          _showAllChannels = !_showAllChannels;
        });
      },
    );
  }

  Future<void> _openChannelInstrumentPicker(int chIndex) async {
    if (_midiPlayer == null || _sfPlayer == null) return;

    final chState = _midiPlayer!.channels[chIndex];
    final result = await showDialog<(SoundFontPlayer?, Preset?, bool)>(
      context: context,
      builder: (context) {
        return ChannelInstrumentPickerDialog(
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
    final isActive = _channelActivity.containsKey(chIndex);
    final instrumentName = _midiPlayer!.getSuggestedInstrumentName(chIndex);

    return MidiTrackHeader(
      chIndex: chIndex,
      chState: chState,
      instrumentName: instrumentName,
      isActive: isActive,
      trackHeight: _kTrackHeight,
      onMuteToggled: () {
        setState(() {
          _midiPlayer!.setChannelMute(chIndex, !chState.isMuted);
        });
      },
      onSoloToggled: () {
        setState(() {
          _midiPlayer!.setChannelSolo(chIndex, !chState.isSolo);
        });
      },
      onVolumeChanged: (val) {
        setState(() {
          _midiPlayer!.setChannelVolume(chIndex, val);
        });
      },
      onOpenInstrumentPicker: () => _openChannelInstrumentPicker(chIndex),
    );
  }

  Widget _buildTrackLane(int chIndex, double timelineWidth) {
    final notes = _midiPlayer?.getChannelNotes(chIndex) ?? const [];
    final instrumentName =
        _midiPlayer?.getSuggestedInstrumentName(chIndex) ??
        'Channel ${chIndex + 1}';

    return MidiTrackLane(
      chIndex: chIndex,
      timelineWidth: timelineWidth,
      zoom: _kTimelineZoom,
      trackHeight: _kTrackHeight,
      notes: notes,
      instrumentName: instrumentName,
      onSeek: _seekToSeconds,
    );
  }

  Widget _buildTimeRuler(double totalDurationSeconds, double timelineWidth) {
    return MidiTimeRuler(
      totalDurationSeconds: totalDurationSeconds,
      timelineWidth: timelineWidth,
      zoom: _kTimelineZoom,
      rulerHeight: _kRulerHeight,
      onSeek: _seekToSeconds,
    );
  }

  Widget _buildPlayheadOverlay(double timelineWidth) {
    final playheadX = (_position.inMicroseconds / 1000000.0) * _kTimelineZoom;

    return CustomPaint(
      size: Size(timelineWidth, double.infinity),
      painter: PlayheadPainter(x: playheadX),
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
          // A-B Loop Range Status Banner (if active)
          if (_loopStart != null || _loopEnd != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.repeat, size: 12, color: Color(0xFF00E5FF)),
                  const SizedBox(width: 4),
                  Text(
                    'A-B Loop: ${_loopStart != null ? _formatDuration(_loopStart!) : "Start"} ➔ ${_loopEnd != null ? _formatDuration(_loopEnd!) : "End"}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _clearLoopRange,
                    borderRadius: BorderRadius.circular(10),
                    child: const Tooltip(
                      message: 'Clear A-B loop range',
                      child: Icon(
                        Icons.cancel,
                        size: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                    _currentChord = null;
                    _currentLyric = null;
                    _pitchBendValue = 0.0;
                    _modWheelValue = 0.0;
                    _sostenutoPedalOn = false;
                    _softPedalOn = false;
                  });
                  _midiPlayer?.stop();
                  _isAutoScrolling = false;
                  if (_timelineHorizontalController.hasClients) {
                    _timelineHorizontalController.jumpTo(0.0);
                  }
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
                      setState(() {
                        _isPlaying = true;
                      });
                      _midiPlayer?.play();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Loop Toggle
              IconButton(
                icon: Icon(
                  Icons.repeat,
                  color: _isLooping ? const Color(0xFF00E5FF) : Colors.white38,
                ),
                iconSize: 24,
                tooltip: 'Toggle Full Song Loop',
                onPressed: () {
                  setState(() {
                    _isLooping = !_isLooping;
                    _midiPlayer?.looping = _isLooping;
                  });
                },
              ),
              const SizedBox(width: 4),
              // A-B Looping controls
              _buildLoopControls(),
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
                    constraints: const BoxConstraints(maxWidth: 450),
                    child: SizedBox(
                      height: 64,
                      child: FftVisualizerWidget(isPlaying: _isPlaying),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Transpose Stepper Controls
              _buildTransposeControls(),
              const SizedBox(width: 12),
              // Playback Speed Selector
              const Icon(Icons.speed, size: 16, color: Colors.white60),
              const SizedBox(width: 6),
              Text(
                'Speed: ${_playbackSpeed.toStringAsFixed(1)}x',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              SizedBox(
                width: 110,
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

  Widget _buildLoopControls() {
    final hasA = _loopStart != null;
    final hasB = _loopEnd != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Button A
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: _setLoopStart,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: hasA
                  ? const Color(0xFF00E5FF).withAlpha(40)
                  : Colors.white10,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: hasA ? const Color(0xFF00E5FF) : Colors.white24,
              ),
            ),
            child: Text(
              hasA ? 'A: ${_formatDuration(_loopStart!)}' : 'Set A',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: hasA ? const Color(0xFF00E5FF) : Colors.white60,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Button B
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: _setLoopEnd,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: hasB
                  ? const Color(0xFF00E5FF).withAlpha(40)
                  : Colors.white10,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: hasB ? const Color(0xFF00E5FF) : Colors.white24,
              ),
            ),
            child: Text(
              hasB ? 'B: ${_formatDuration(_loopEnd!)}' : 'Set B',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: hasB ? const Color(0xFF00E5FF) : Colors.white60,
              ),
            ),
          ),
        ),
        if (hasA || hasB) ...[
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            tooltip: 'Clear A-B Loop Range',
            onPressed: _clearLoopRange,
          ),
        ],
      ],
    );
  }

  Widget _buildTransposeControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.swap_vert, size: 16, color: Colors.white60),
        const SizedBox(width: 2),
        IconButton(
          icon: const Icon(Icons.remove, size: 16),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          tooltip: 'Transpose -1 semitone',
          onPressed: () => _setTranspose(_transpose - 1),
        ),
        Tooltip(
          message: 'Click to reset transposition',
          child: InkWell(
            onTap: () => _setTranspose(0),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _transpose != 0
                    ? const Color(0xFF6C63FF).withAlpha(60)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _transpose != 0
                      ? const Color(0xFF00E5FF)
                      : Colors.white24,
                ),
              ),
              child: Text(
                '${_transpose >= 0 ? "+$_transpose" : "$_transpose"} st',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: _transpose != 0
                      ? const Color(0xFF00E5FF)
                      : Colors.white70,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 16),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          tooltip: 'Transpose +1 semitone',
          onPressed: () => _setTranspose(_transpose + 1),
        ),
      ],
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
