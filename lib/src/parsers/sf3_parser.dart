import '../sources/soundfont_source.dart';
import 'sf2_parser.dart';

/// Parser for SoundFont 3 (`.sf3`) files.
///
/// SF3 uses the same RIFF structure as SF2, but stores Ogg Vorbis or FLAC
/// compressed audio streams in the `sdta` chunk.
class Sf3Parser {
  /// The input [SoundFontSource] providing the SF3 binary data.
  final SoundFontSource source;

  /// Creates an [Sf3Parser] reading from [source].
  Sf3Parser(this.source);

  /// Parses the SF3 binary stream into an [Sf2Data] container.
  Future<Sf2Data> parse() async {
    final sf2Parser = Sf2Parser(source);
    return await sf2Parser.parse(isSf3: true);
  }
}
