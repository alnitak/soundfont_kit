import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:soundfont_reader/soundfont_reader.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SimpleSoundFontApp());
}

class SimpleSoundFontApp extends StatelessWidget {
  const SimpleSoundFontApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: SimpleSoundFontHomePage());
  }
}

class SimpleSoundFontHomePage extends StatefulWidget {
  const SimpleSoundFontHomePage({super.key});

  @override
  State<SimpleSoundFontHomePage> createState() =>
      _SimpleSoundFontHomePageState();
}

class _SimpleSoundFontHomePageState extends State<SimpleSoundFontHomePage> {
  final List<String> _bundledAssets = [
    'assets/Celesta_minimal.sf3',
    'assets/SFX_StarWars_ships.SF2.zip',
    'assets/SFX_StarWars_weapons.SF2',
    'assets/TerribleDanger.sf2',
    'assets/RatAttack.sf2',
    'assets/1115_PassingJet.sf2.zip',
    'assets/Pac-Man-W2_.sf2.zip',
  ];

  late String _selectedAsset;
  bool _isLoading = true;
  String? _errorMessage;

  SoundFontFile? _soundFont;
  SoundFontPlayer? _player;
  Preset? _selectedPreset;

  final SoundFontGlobalFilters _filters = const SoundFontGlobalFilters();

  @override
  void initState() {
    super.initState();
    _selectedAsset = _bundledAssets.first;
    _initEngineAndLoad(_selectedAsset);
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _initEngineAndLoad(String assetPath) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (!SoLoud.instance.isInitialized) {
        await SoLoud.instance.init();
      }

      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      final sf = await SoundFontFile.fromBytes(bytes);
      final player = sf.createPlayer();

      setState(() {
        _soundFont = sf;
        _player = player;
        _selectedPreset = sf.presets.isNotEmpty ? sf.presets.first : null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading SoundFont: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _playNote(int midiKey) async {
    final player = _player;
    final preset = _selectedPreset;
    if (player == null || preset == null) return;
    try {
      await player.playPreset(preset, key: midiKey, velocity: 100);
    } catch (e) {
      debugPrint('Playback error: $e');
    }
  }

  Future<void> _playChord(List<int> midiKeys) async {
    final player = _player;
    final preset = _selectedPreset;
    if (player == null || preset == null) return;
    try {
      for (final key in midiKeys) {
        await player.playPreset(preset, key: key, velocity: 95);
      }
    } catch (e) {
      debugPrint('Chord playback error: $e');
    }
  }

  Future<void> _stopAll() async {
    await _player?.stopMixerOutput();
  }

  @override
  Widget build(BuildContext context) {
    final sf = _soundFont;

    return Scaffold(
      appBar: AppBar(title: const Text('SoundFont Reader Simple Example')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Run lib/main_full.dart for the full interactive demonstration.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (sf != null) ...[
                    const Text('Select SoundFont:'),
                    DropdownButton<String>(
                      value: _selectedAsset,
                      isExpanded: true,
                      items: _bundledAssets.map((asset) {
                        return DropdownMenuItem(
                          value: asset,
                          child: Text(asset),
                        );
                      }).toList(),
                      onChanged: (newAsset) {
                        if (newAsset != null && newAsset != _selectedAsset) {
                          setState(() => _selectedAsset = newAsset);
                          _initEngineAndLoad(newAsset);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text('Audition Notes:'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: () => _playNote(60),
                          child: const Text('Play C4'),
                        ),
                        ElevatedButton(
                          onPressed: () => _playNote(64),
                          child: const Text('Play E4'),
                        ),
                        ElevatedButton(
                          onPressed: () => _playNote(67),
                          child: const Text('Play G4'),
                        ),
                        ElevatedButton(
                          onPressed: () => _playNote(79),
                          child: const Text('Play G5'),
                        ),
                        ElevatedButton(
                          onPressed: () => _playChord([60, 64, 67, 79]),
                          child: const Text('Play Chord'),
                        ),
                        ElevatedButton(
                          onPressed: _stopAll,
                          child: const Text('Stop All'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text('Filters:'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: SoundFontFilterType.values.map((type) {
                        final active = _filters.isActive(type);
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: active,
                              onChanged: (checked) {
                                setState(() {
                                  _filters.toggle(type, checked ?? false);
                                });
                              },
                            ),
                            Text(type.label),
                          ],
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
