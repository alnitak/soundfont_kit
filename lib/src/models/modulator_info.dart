/// SF2 Modulator specification data.
class ModulatorInfo {
  final int srcOper;
  final int destOper;
  final int amount;
  final int amtSrcOper;
  final int transOper;

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
