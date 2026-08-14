import 'zone.dart';

/// Represents a SoundFont Preset (Patch).
class Preset {
  final int bank;
  final int program;
  final String name;
  final List<Zone> zones;
  final int library;
  final int genre;
  final int morphology;

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
