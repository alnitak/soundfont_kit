import 'zone.dart';

/// Represents a SoundFont instrument containing one or more synthesis [zones].
class Instrument {
  /// The unique 0-based index of this instrument within the SoundFont.
  final int id;

  /// The human-readable name of the instrument.
  final String name;

  /// The synthesis zones mapping key and velocity ranges to audio samples.
  final List<Zone> zones;

  /// Creates an [Instrument] with the given [id], [name], and [zones].
  const Instrument({
    required this.id,
    required this.name,
    this.zones = const [],
  });

  @override
  String toString() {
    return 'Instrument(id: $id, name: "$name", zones: ${zones.length})';
  }
}
