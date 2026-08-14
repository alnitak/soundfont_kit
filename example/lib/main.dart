import 'package:flutter/material.dart';
import 'package:soundfont_reader/soundfont_reader.dart';

void main() {
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
  State<SoundFontInspectorScreen> createState() => _SoundFontInspectorScreenState();
}

class _SoundFontInspectorScreenState extends State<SoundFontInspectorScreen> {
  final List<String> _assetFiles = [
    'assets/Rhodes - minimal (from Dream Piano).sf2',
    'assets/Rhodes - minimal (from Dream Piano).sf3',
    'assets/Dream Piano (converted).sfz+flac.zip',
  ];

  late String _selectedAsset;
  bool _isLoading = false;
  String? _error;
  SoundFontFile? _soundFont;
  SampleInfo? _selectedSample;
  String? _sampleByteDetails;

  @override
  void initState() {
    super.initState();
    _selectedAsset = _assetFiles.first;
    _loadSoundFont(_selectedAsset);
  }

  Future<void> _loadSoundFont(String assetPath) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _soundFont = null;
      _selectedSample = null;
      _sampleByteDetails = null;
    });

    try {
      final sf = await SoundFontFile.fromAsset(assetPath);
      setState(() {
        _soundFont = sf;
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
          ? bytes.sublist(0, 4).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')
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
                  child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
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
              const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text('Error Loading SoundFont', style: Theme.of(context).textTheme.titleLarge),
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
        return ExpansionTile(
          title: Text('${preset.name} (Bank ${preset.bank}, Program ${preset.program})'),
          subtitle: Text('${preset.zones.length} Zones'),
          children: preset.zones.map((zone) {
            return ListTile(
              dense: true,
              leading: const Icon(Icons.layers, size: 18),
              title: Text('Key Range: ${zone.keyRangeMin}..${zone.keyRangeMax} | Vel: ${zone.velRangeMin}..${zone.velRangeMax}'),
              subtitle: Text('RootKey: ${zone.rootKey ?? "-"} | Pan: ${zone.pan ?? 0.0} | Attenuation: ${zone.attenuation ?? 0.0} dB'),
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
        return ExpansionTile(
          title: Text(inst.name),
          subtitle: Text('${inst.zones.length} Zones'),
          children: inst.zones.map((zone) {
            return ListTile(
              dense: true,
              leading: const Icon(Icons.graphic_eq, size: 18),
              title: Text('Sample ID: ${zone.sampleID ?? "-"} (${zone.sampleRef?.name ?? "N/A"})'),
              subtitle: Text('Key: ${zone.keyRangeMin}..${zone.keyRangeMax} | RootKey: ${zone.rootKey ?? "-"}'),
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
                  Text(_sampleByteDetails!, style: const TextStyle(fontFamily: 'monospace')),
                ],
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: sf.samples.length,
            itemBuilder: (context, index) {
              final sample = sf.samples[index];
              return ListTile(
                title: Text('${sample.name} [ID: ${sample.id}]'),
                subtitle: Text(
                  'Rate: ${sample.sampleRate} Hz | Key: ${sample.originalPitch} | Compression: ${sample.compression.name.toUpperCase()}\n'
                  '${sample.samplePath != null ? "Path: ${sample.samplePath}" : "Offset: ${sample.byteOffset}, Length: ${sample.byteLength} B"}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.file_download),
                  tooltip: 'Read Sample Bytes',
                  onPressed: () => _inspectSampleBytes(sample),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
