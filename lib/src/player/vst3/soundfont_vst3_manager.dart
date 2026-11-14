// ignore_for_file: experimental_member_use

import 'dart:io';

import 'package:flutter_soloud/flutter_soloud.dart';
import '../filters/soundfont_filter.dart';

/// Descriptor for a discovered `.vst3` plugin class and its bundle path.
class DiscoveredVst3Plugin {
  /// File system path to the `.vst3` bundle directory or binary.
  final String bundlePath;

  /// VST3 component class metadata exported by the plugin factory.
  final Vst3ClassInfo classInfo;

  /// Creates a [DiscoveredVst3Plugin] pairing a [bundlePath] with its [classInfo].
  const DiscoveredVst3Plugin({
    required this.bundlePath,
    required this.classInfo,
  });

  /// Human-readable plugin name.
  String get name => classInfo.name;

  /// 32-character hexadecimal VST3 class UID.
  String get classUid => classInfo.classUid;

  /// VST3 subcategory string (e.g., `'Instrument|Synth'`, `'Fx|Delay'`).
  String get subCategories => classInfo.subCategories;

  /// Whether this VST3 class is a virtual instrument (`Instrument`).
  bool get isInstrument => classInfo.isInstrument;

  /// Whether this VST3 class is an audio effect processor (`Fx`).
  bool get isEffect => classInfo.isEffect;
}

/// High-level manager for Desktop VST3 Effects ([Vst3EffectPlugin]) and
/// Virtual Instruments ([Vst3InstrumentPlugin]) in `soundfont_kit`.
///
/// Works on macOS, Windows, and Linux when `enable_vst3: true` is configured
/// under `hooks.user_defines.flutter_soloud` in the app's `pubspec.yaml`.
class SoundFontVst3Manager {
  /// Shared singleton instance for convenience.
  static final SoundFontVst3Manager instance = SoundFontVst3Manager();

  /// Underlying `flutter_soloud` [Vst3Host] instance used to scan and instantiate plugins.
  final Vst3Host host = Vst3Host();

  /// Active master insert effects keyed by slot index (`0..7`).
  final Map<int, Vst3EffectPlugin> _masterEffects = {};

  /// Active per-bus insert effects keyed by `"$busId:$slotIndex"`.
  final Map<String, Vst3EffectPlugin> _busEffects = {};

  /// Active virtual instruments and their playing SoLoud [SoundHandle]s.
  final Map<Vst3InstrumentPlugin, SoundHandle?> _instruments = {};

  /// Whether native VST3 hosting is compiled and supported on the current OS.
  bool get isSupported => host.isSupported;

  /// Standard OS VST3 plugin directories.
  List<String> get standardSearchPaths => host.standardSearchPaths;

  /// Scans a single `.vst3` bundle and returns all [DiscoveredVst3Plugin] classes inside it.
  List<DiscoveredVst3Plugin> scanBundle(String bundlePath) {
    if (!isSupported) return const [];
    final classes = host.scanBundle(bundlePath);
    return classes
        .map((c) => DiscoveredVst3Plugin(bundlePath: bundlePath, classInfo: c))
        .toList(growable: false);
  }

  /// Scans all standard OS VST3 directories (including vendor subdirectories)
  /// and returns discovered `.vst3` plugins.
  List<DiscoveredVst3Plugin> scanStandardDirectories({int maxDepth = 4}) {
    if (!isSupported) return const [];
    final discovered = <DiscoveredVst3Plugin>[];
    final seenBundles = <String>{};
    for (final dirPath in standardSearchPaths) {
      final dir = Directory(dirPath);
      _scanDirectoryRecursive(dir, maxDepth, discovered, seenBundles);
    }
    return discovered;
  }

  void _scanDirectoryRecursive(
    Directory dir,
    int depthRemaining,
    List<DiscoveredVst3Plugin> out,
    Set<String> seenBundles,
  ) {
    if (depthRemaining <= 0 || !dir.existsSync()) return;
    try {
      for (final entity in dir.listSync(followLinks: true)) {
        final path = entity.path;
        final base = path.split(Platform.pathSeparator).last;
        if (base.startsWith('.')) continue;

        if (path.toLowerCase().endsWith('.vst3')) {
          final normalized = base.toLowerCase();
          if (seenBundles.add(normalized)) {
            try {
              out.addAll(scanBundle(path));
            } catch (_) {}
          }
        } else if (entity is Directory) {
          _scanDirectoryRecursive(entity, depthRemaining - 1, out, seenBundles);
        }
      }
    } catch (_) {}
  }

  /// Returns the currently loaded Master VST3 Effect in [slotIndex] (`0..7`), if any.
  Vst3EffectPlugin? getMasterEffect(int slotIndex) => _masterEffects[slotIndex];

  /// Returns the currently loaded Bus VST3 Effect on [bus] in [slotIndex] (`0..7`), if any.
  Vst3EffectPlugin? getBusEffect(Bus bus, int slotIndex) =>
      _busEffects['${bus.busId}:$slotIndex'];

  /// Loads a `.vst3` Audio Effect into Master [slotIndex] (`0..7`), replacing any
  /// existing effect in that slot.
  Vst3EffectPlugin loadMasterEffect({
    required int slotIndex,
    required String bundlePath,
    String? classUid,
    int sampleRate = 48000,
    int maxBlockSize = 2048,
  }) {
    unloadMasterEffect(slotIndex);
    final slot = SoLoud.instance.filters.customFilter(slotIndex);
    final plugin = host.loadEffect(
      bundlePath: bundlePath,
      slot: slot,
      classUid: classUid,
      sampleRate: sampleRate,
      maxBlockSize: maxBlockSize,
    );
    _masterEffects[slotIndex] = plugin;
    return plugin;
  }

  /// Unloads and disposes the Master VST3 Effect at [slotIndex] (`0..7`).
  void unloadMasterEffect(int slotIndex) {
    final existing = _masterEffects.remove(slotIndex);
    try {
      existing?.closeEditorWindow();
    } catch (_) {}
    existing?.dispose();
  }

  /// Loads a `.vst3` Audio Effect into [bus]'s custom filter [slotIndex] (`0..7`),
  /// replacing any existing effect in that slot on [bus].
  Vst3EffectPlugin loadBusEffect({
    required Bus bus,
    required int slotIndex,
    required String bundlePath,
    String? classUid,
    int sampleRate = 48000,
    int maxBlockSize = 2048,
  }) {
    if (!bus.isActive && SoLoud.instance.isInitialized) {
      bus.playOnEngine();
    }
    unloadBusEffect(bus, slotIndex);
    final slot = bus.filters.customFilter(slotIndex);
    final plugin = host.loadEffect(
      bundlePath: bundlePath,
      slot: slot,
      classUid: classUid,
      sampleRate: sampleRate,
      maxBlockSize: maxBlockSize,
    );
    _busEffects['${bus.busId}:$slotIndex'] = plugin;
    return plugin;
  }

  /// Unloads and disposes the Bus VST3 Effect on [bus] at [slotIndex] (`0..7`).
  void unloadBusEffect(Bus bus, int slotIndex) {
    final existing = _busEffects.remove('${bus.busId}:$slotIndex');
    try {
      existing?.closeEditorWindow();
    } catch (_) {}
    existing?.dispose();
  }

  /// Convenience helper to load a `.vst3` Audio Effect into any [SoundFontFilterRack]
  /// custom slot (`0..7`), whether global or bus-scoped.
  Vst3EffectPlugin? loadEffectIntoSlot({
    required String bundlePath,
    required SoundFontFilterRack rack,
    required int slotIndex,
    String? classUid,
    int sampleRate = 48000,
    int maxBlockSize = 2048,
  }) {
    try {
      if (rack.bus != null) {
        return loadBusEffect(
          bus: rack.bus!,
          slotIndex: slotIndex,
          bundlePath: bundlePath,
          classUid: classUid,
          sampleRate: sampleRate,
          maxBlockSize: maxBlockSize,
        );
      }
      return loadMasterEffect(
        slotIndex: slotIndex,
        bundlePath: bundlePath,
        classUid: classUid,
        sampleRate: sampleRate,
        maxBlockSize: maxBlockSize,
      );
    } catch (_) {
      return null;
    }
  }

  /// Convenience helper to unload a `.vst3` Audio Effect from a [SoundFontFilterRack]
  /// custom slot (`0..7`).
  void unloadEffectFromSlot({
    required SoundFontFilterRack rack,
    required int slotIndex,
  }) {
    if (rack.bus != null) {
      unloadBusEffect(rack.bus!, slotIndex);
    } else {
      unloadMasterEffect(slotIndex);
    }
  }

  /// Loads a `.vst3` Virtual Instrument (`Instrument|Synth`) and optionally starts
  /// its audio stream on [busId] (`0` for Master, or a `Bus.busId`).
  Vst3InstrumentPlugin? loadInstrument({
    required String bundlePath,
    String? classUid,
    int sampleRate = 48000,
    int maxBlockSize = 2048,
    int busId = 0,
    bool autoPlay = true,
  }) {
    try {
      final synth = host.loadInstrument(
        bundlePath: bundlePath,
        classUid: classUid,
        sampleRate: sampleRate,
        maxBlockSize: maxBlockSize,
      );
      SoundHandle? handle;
      if (autoPlay && SoLoud.instance.isInitialized) {
        handle = SoLoud.instance.play(synth.audioSource, busId: busId);
      }
      _instruments[synth] = handle;
      return synth;
    } catch (_) {
      return null;
    }
  }

  /// Unloads and disposes a loaded [Vst3InstrumentPlugin].
  void unloadInstrument(Vst3InstrumentPlugin instrument) {
    final handle = _instruments.remove(instrument);
    if (handle != null &&
        SoLoud.instance.isInitialized &&
        SoLoud.instance.getIsValidVoiceHandle(handle)) {
      try {
        SoLoud.instance.stop(handle);
      } catch (_) {}
    }
    try {
      instrument.closeEditorWindow();
    } catch (_) {}
    instrument.dispose();
  }

  /// Broadcasts musical transport state (`bpm`, time signature, `isPlaying`) to
  /// all active VST3 effects and virtual instruments.
  void updateTransport({
    required double bpm,
    int timeSigNumerator = 4,
    int timeSigDenominator = 4,
    bool isPlaying = true,
  }) {
    for (final fx in _masterEffects.values) {
      if (!fx.isDisposed) {
        fx.setTransport(
          bpm: bpm,
          timeSigNumerator: timeSigNumerator,
          timeSigDenominator: timeSigDenominator,
          isPlaying: isPlaying,
        );
      }
    }
    for (final fx in _busEffects.values) {
      if (!fx.isDisposed) {
        fx.setTransport(
          bpm: bpm,
          timeSigNumerator: timeSigNumerator,
          timeSigDenominator: timeSigDenominator,
          isPlaying: isPlaying,
        );
      }
    }
    for (final inst in _instruments.keys) {
      if (!inst.isDisposed) {
        inst.setTransport(
          bpm: bpm,
          timeSigNumerator: timeSigNumerator,
          timeSigDenominator: timeSigDenominator,
          isPlaying: isPlaying,
        );
      }
    }
  }

  /// Disposes all managed VST3 effects and virtual instruments.
  void disposeAll() {
    for (final fx in _masterEffects.values) {
      fx.dispose();
    }
    _masterEffects.clear();

    for (final fx in _busEffects.values) {
      fx.dispose();
    }
    _busEffects.clear();

    final synths = _instruments.keys.toList();
    for (final synth in synths) {
      unloadInstrument(synth);
    }
    _instruments.clear();
  }
}
