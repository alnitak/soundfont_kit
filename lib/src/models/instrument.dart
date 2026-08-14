import 'zone.dart';

/// Represents an Instrument containing one or more synthesis zones.
class Instrument {
  final int id;
  final String name;
  final List<Zone> zones;

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
