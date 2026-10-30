/// SoundFont 2 modulator specification mapping a source controller to a generator destination.
class ModulatorInfo {
  /// Source data operator specifying the primary modulator input controller.
  final int srcOper;

  /// Destination generator operator controlled by this modulator.
  final int destOper;

  /// Degree to which the source modulates the destination.
  final int amount;

  /// Secondary modulator source operator that scales [amount].
  final int amtSrcOper;

  /// Transform operator applied to the modulation value before summation.
  final int transOper;

  /// Creates a [ModulatorInfo] with the given SF2 modulator operators and [amount].
  const ModulatorInfo({
    required this.srcOper,
    required this.destOper,
    required this.amount,
    required this.amtSrcOper,
    required this.transOper,
  });

  @override
  String toString() {
    return 'ModulatorInfo(src: $srcOper, dest: $destOper, amount: $amount)';
  }
}
