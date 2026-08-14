import '../models/sample_info.dart';
import '../models/soundfont_format.dart';
import '../sources/soundfont_source.dart';
import 'sf2_parser.dart';

/// Parser for SoundFont 3 (.sf3) files.
/// SF3 uses the same RIFF structure as SF2, but with Ogg Vorbis compressed audio streams in the `sdta` chunk.
class Sf3Parser {
  final SoundFontSource source;

  Sf3Parser(this.source);

  Future<Sf2Data> parse() async {
    final sf2Parser = Sf2Parser(source);
    final sf2Data = await sf2Parser.parse();

    // Mark all samples as OGG Vorbis compressed in SF3
    final updatedSamples = <SampleInfo>[];
    for (final s in sf2Data.samples) {
      updatedSamples.add(SampleInfo(
        id: s.id,
        name: s.name,
        sampleRate: s.sampleRate,
        originalPitch: s.originalPitch,
        pitchCorrection: s.pitchCorrection,
        loopStart: s.loopStart,
        loopEnd: s.loopEnd,
        sampleCount: s.sampleCount,
        byteOffset: s.byteOffset,
        byteLength: s.byteLength,
        compression: SampleCompression.ogg,
        samplePath: s.samplePath,
        channels: s.channels,
        sampleType: s.sampleType,
      ));
    }

    return Sf2Data(
      name: sf2Data.name,
      comment: sf2Data.comment,
      presets: sf2Data.presets,
      instruments: sf2Data.instruments,
      samples: updatedSamples,
      rawBytes: sf2Data.rawBytes,
      smplOffset: sf2Data.smplOffset,
      smplLength: sf2Data.smplLength,
      sm24Offset: sf2Data.sm24Offset,
      sm24Length: sf2Data.sm24Length,
    );
  }
}
