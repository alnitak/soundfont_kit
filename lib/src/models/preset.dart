import 'zone.dart';

/// Represents a SoundFont preset (patch) selectable by MIDI [bank] and [program].
class Preset {
  /// The MIDI bank number (`0..127` for melodic banks, `128` for percussion).
  final int bank;

  /// The MIDI program (patch) number (`0..127`).
  final int program;

  /// The human-readable name of this preset.
  final String name;

  /// The preset zones referencing instruments and applying relative generator offsets.
  final List<Zone> zones;

  /// SoundFont library metadata identifier (`dwLibrary`).
  final int library;

  /// SoundFont genre classification identifier (`dwGenre`).
  final int genre;

  /// SoundFont morphology classification identifier (`dwMorphology`).
  final int morphology;

  /// Creates a [Preset] with the given [bank], [program], [name], and [zones].
  const Preset({
    required this.bank,
    required this.program,
    required this.name,
    this.zones = const [],
    this.library = 0,
    this.genre = 0,
    this.morphology = 0,
  });

  @override
  String toString() {
    return 'Preset(bank: $bank, program: $program, name: "$name", zones: ${zones.length})';
  }
}
