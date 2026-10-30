import 'package:flutter_test/flutter_test.dart';
import 'package:soundfont_kit/soundfont_kit.dart';

void main() {
  test('inspect zones 70 and 71', () async {
    final sfPath =
        '/Volumes/NVME/workspace/libs/soundfont_kit/example/assets/Celesta_minimal.sf3';
    final sf = await SoundFontFile.fromFile(sfPath);
    for (final inst in sf.instruments) {
      print('Instrument "${inst.name}": ${inst.zones.length} zones');
      for (final z in inst.zones) {
        if (z.matches(70, 100)) {
          print('Zone for key 70: sample=${z.sampleRef?.name}, loopMode=${z.loopMode}, loopStart=${z.loopStart}, loopEnd=${z.loopEnd}, volEnvRelease=${z.volEnvRelease}');
        }
      }
    }
  });
}
