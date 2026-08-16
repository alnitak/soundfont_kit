import '../sources/soundfont_source.dart';
import 'sf2_parser.dart';

/// Parser for SoundFont 3 (.sf3) files.
/// SF3 uses the same RIFF structure as SF2, but with Ogg Vorbis compressed audio streams in the `sdta` chunk.
class Sf3Parser {
  final SoundFontSource source;

  Sf3Parser(this.source);

  Future<Sf2Data> parse() async {
    final sf2Parser = Sf2Parser(source);
    return await sf2Parser.parse(isSf3: true);
  }
}
