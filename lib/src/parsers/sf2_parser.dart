import 'dart:math' as math;
import 'dart:typed_data';

import '../models/instrument.dart';
import '../models/preset.dart';
import '../models/sample_info.dart';
import '../models/soundfont_format.dart';
import '../models/zone.dart';
import '../sources/soundfont_source.dart';
import 'riff_reader.dart';

/// Parsed SoundFont 2 container holding presets, instruments, and samples.
class Sf2Data {
  final String? name;
  final String? comment;
  final List<Preset> presets;
  final List<Instrument> instruments;
  final List<SampleInfo> samples;
  final Uint8List rawBytes;
  final int smplOffset;
  final int smplLength;
  final int sm24Offset;
  final int sm24Length;

  Sf2Data({
    this.name,
    this.comment,
    required this.presets,
    required this.instruments,
    required this.samples,
    required this.rawBytes,
    this.smplOffset = 0,
    this.smplLength = 0,
    this.sm24Offset = 0,
    this.sm24Length = 0,
  });
}

/// Parser for SF2 (SoundFont 2.0 / 2.04) binary files.
class Sf2Parser {
  final SoundFontSource source;

  Sf2Parser(this.source);

  Future<Sf2Data> parse({bool isSf3 = false}) async {
    final bytes = await source.getBytes();
    final reader = RiffReader(bytes);

    final header = reader.readFourCC();
    if (header != 'RIFF') {
      throw FormatException('Invalid SoundFont file: Header is "$header", expected "RIFF"');
    }
    reader.readUint32(); // riffSize
    final formType = reader.readFourCC();
    if (formType != 'sfbk') {
      throw FormatException('Invalid SoundFont form type: "$formType", expected "sfbk"');
    }

    String? sfName;
    String? sfComment;

    int smplOffset = 0;
    int smplLength = 0;
    int sm24Offset = 0;
    int sm24Length = 0;

    // Sub-chunks inside pdta
    Uint8List? phdrBytes, pbagBytes, pmodBytes, pgenBytes;
    Uint8List? instBytes, ibagBytes, imodBytes, igenBytes, shdrBytes;

    while (reader.remaining >= 8) {
      final chunkId = reader.readFourCC();
      final chunkSize = reader.readUint32();

      if (chunkId == 'LIST') {
        final listType = reader.readFourCC();
        final listDataSize = chunkSize - 4;
        final listEnd = reader.offset + listDataSize;

        if (listType == 'INFO') {
          while (reader.offset + 8 <= listEnd) {
            final infoId = reader.readFourCC();
            final infoSize = reader.readUint32();
            if (infoId == 'INAM') {
              sfName = reader.readString(infoSize);
            } else if (infoId == 'ICMT') {
              sfComment = reader.readString(infoSize);
            } else {
              reader.offset += infoSize;
            }
            if (infoSize % 2 != 0) reader.offset += 1;
          }
        } else if (listType == 'sdta') {
          while (reader.offset + 8 <= listEnd) {
            final sdtaId = reader.readFourCC();
            final sdtaSize = reader.readUint32();
            if (sdtaId == 'smpl' || sdtaId == 's3mp') {
              smplOffset = reader.offset;
              smplLength = sdtaSize;
              reader.offset += sdtaSize;
            } else if (sdtaId == 'sm24') {
              sm24Offset = reader.offset;
              sm24Length = sdtaSize;
              reader.offset += sdtaSize;
            } else {
              reader.offset += sdtaSize;
            }
            if (sdtaSize % 2 != 0) reader.offset += 1;
          }
        } else if (listType == 'pdta') {
          while (reader.offset + 8 <= listEnd) {
            final subId = reader.readFourCC();
            final subSize = reader.readUint32();
            final subData = reader.readBytes(subSize);
            if (subId == 'phdr') {
              phdrBytes = subData;
            } else if (subId == 'pbag') {
              pbagBytes = subData;
            } else if (subId == 'pmod') {
              pmodBytes = subData;
            } else if (subId == 'pgen') {
              pgenBytes = subData;
            } else if (subId == 'inst') {
              instBytes = subData;
            } else if (subId == 'ibag') {
              ibagBytes = subData;
            } else if (subId == 'imod') {
              imodBytes = subData;
            } else if (subId == 'igen') {
              igenBytes = subData;
            } else if (subId == 'shdr') {
              shdrBytes = subData;
            }

            if (subSize % 2 != 0) reader.offset += 1;
          }
        }
        reader.offset = listEnd;
      } else {
        reader.offset += chunkSize;
        if (chunkSize % 2 != 0) reader.offset += 1;
      }
    }

    // Parse Sample Headers (shdr)
    final samples = _parseSampleHeaders(shdrBytes, smplOffset, isSf3: isSf3);

    // Map samples by sample index
    final sampleMap = <int, SampleInfo>{};
    for (int i = 0; i < samples.length; i++) {
      sampleMap[i] = samples[i];
    }

    // Parse Instruments (inst, ibag, imod, igen)
    final instruments = _parseInstruments(instBytes, ibagBytes, imodBytes, igenBytes, sampleMap);

    // Map instruments by instrument index
    final instMap = <int, Instrument>{};
    for (int i = 0; i < instruments.length; i++) {
      instMap[i] = instruments[i];
    }

    // Parse Presets (phdr, pbag, pmod, pgen)
    final presets = _parsePresets(phdrBytes, pbagBytes, pmodBytes, pgenBytes, instMap, sampleMap);

    return Sf2Data(
      name: sfName,
      comment: sfComment,
      presets: presets,
      instruments: instruments,
      samples: samples,
      rawBytes: bytes,
      smplOffset: smplOffset,
      smplLength: smplLength,
      sm24Offset: sm24Offset,
      sm24Length: sm24Length,
    );
  }

  List<SampleInfo> _parseSampleHeaders(Uint8List? shdrBytes, int smplOffset, {bool isSf3 = false}) {
    if (shdrBytes == null) return [];
    final reader = RiffReader(shdrBytes);
    final count = shdrBytes.length ~/ 46;
    final list = <SampleInfo>[];

    for (int i = 0; i < count; i++) {
      final name = reader.readString(20);
      final start = reader.readUint32();
      final end = reader.readUint32();
      final startloop = reader.readUint32();
      final endloop = reader.readUint32();
      final sampleRate = reader.readUint32();
      final originalPitch = reader.readUint8();
      final pitchCorrection = reader.readInt8();
      final sampleLink = reader.readUint16();
      final sampleType = reader.readUint16();

      // Skip EOS terminal record or empty sample headers
      if (name == 'EOS' || (start == 0 && end == 0)) {
        continue;
      }

      // Check if sampleType bit 0x8000 indicates SF3 Ogg Vorbis sample or if file is SF3
      final isOgg = isSf3 || (sampleType & 0x8000) != 0;

      final byteOffset = isOgg ? (smplOffset + start) : (smplOffset + (start * 2));
      final byteLength = isOgg
          ? ((end > start) ? (end - start) : 0)
          : ((end > start) ? (end - start) * 2 : 0);

      list.add(SampleInfo(
        id: list.length,
        name: name,
        sampleRate: sampleRate,
        originalPitch: originalPitch,
        pitchCorrection: pitchCorrection,
        loopStart: startloop - start,
        loopEnd: endloop - start,
        sampleCount: end - start,
        byteOffset: byteOffset,
        byteLength: byteLength,
        compression: isOgg ? SampleCompression.ogg : SampleCompression.pcm16,
        channels: 1,
        sampleType: sampleType,
        sampleLink: sampleLink,
      ));
    }
    return list;
  }

  List<Instrument> _parseInstruments(
    Uint8List? instBytes,
    Uint8List? ibagBytes,
    Uint8List? imodBytes,
    Uint8List? igenBytes,
    Map<int, SampleInfo> sampleMap,
  ) {
    if (instBytes == null || ibagBytes == null || igenBytes == null) return [];

    final instReader = RiffReader(instBytes);
    final instCount = instBytes.length ~/ 22;

    final bagReader = RiffReader(ibagBytes);
    final bagCount = ibagBytes.length ~/ 4;

    final genReader = RiffReader(igenBytes);

    final instruments = <Instrument>[];

    final instRecords = <_InstRecord>[];
    for (int i = 0; i < instCount; i++) {
      final name = instReader.readString(20);
      final bagIdx = instReader.readUint16();
      instRecords.add(_InstRecord(name: name, bagIdx: bagIdx));
    }

    final bagRecords = <_BagRecord>[];
    for (int i = 0; i < bagCount; i++) {
      final genIdx = bagReader.readUint16();
      final modIdx = bagReader.readUint16();
      bagRecords.add(_BagRecord(genIdx: genIdx, modIdx: modIdx));
    }

    for (int i = 0; i < instRecords.length - 1; i++) {
      final rec = instRecords[i];
      final nextRec = instRecords[i + 1];
      if (rec.name == 'EOI') continue;

      final startBag = rec.bagIdx;
      final endBag = nextRec.bagIdx;

      final zones = <Zone>[];
      Zone? globalZone;

      for (int b = startBag; b < endBag && b < bagRecords.length; b++) {
        final bag = bagRecords[b];
        final nextBagGen = (b + 1 < bagRecords.length) ? bagRecords[b + 1].genIdx : (igenBytes.length ~/ 4);

        final gens = _parseGenerators(genReader, bag.genIdx, nextBagGen);

        final isGlobal = !gens.containsKey(53); // 53 = sampleID

        if (isGlobal) {
          globalZone = _createZoneFromGens(gens, globalZone: null, sampleMap: sampleMap);
        } else {
          final zone = _createZoneFromGens(gens, globalZone: globalZone, sampleMap: sampleMap);
          zones.add(zone);
        }
      }

      instruments.add(Instrument(
        id: instruments.length,
        name: rec.name,
        zones: zones,
      ));
    }

    return instruments;
  }

  List<Preset> _parsePresets(
    Uint8List? phdrBytes,
    Uint8List? pbagBytes,
    Uint8List? pmodBytes,
    Uint8List? pgenBytes,
    Map<int, Instrument> instMap,
    Map<int, SampleInfo> sampleMap,
  ) {
    if (phdrBytes == null || pbagBytes == null || pgenBytes == null) return [];

    final phdrReader = RiffReader(phdrBytes);
    final phdrCount = phdrBytes.length ~/ 38;

    final bagReader = RiffReader(pbagBytes);
    final bagCount = pbagBytes.length ~/ 4;

    final genReader = RiffReader(pgenBytes);

    final presets = <Preset>[];

    final phdrRecords = <_PhdrRecord>[];
    for (int i = 0; i < phdrCount; i++) {
      final name = phdrReader.readString(20);
      final preset = phdrReader.readUint16();
      final bank = phdrReader.readUint16();
      final bagIdx = phdrReader.readUint16();
      final library = phdrReader.readUint32();
      final genre = phdrReader.readUint32();
      final morphology = phdrReader.readUint32();
      phdrRecords.add(_PhdrRecord(
        name: name,
        preset: preset,
        bank: bank,
        bagIdx: bagIdx,
        library: library,
        genre: genre,
        morphology: morphology,
      ));
    }

    final bagRecords = <_BagRecord>[];
    for (int i = 0; i < bagCount; i++) {
      final genIdx = bagReader.readUint16();
      final modIdx = bagReader.readUint16();
      bagRecords.add(_BagRecord(genIdx: genIdx, modIdx: modIdx));
    }

    for (int i = 0; i < phdrRecords.length - 1; i++) {
      final rec = phdrRecords[i];
      final nextRec = phdrRecords[i + 1];
      if (rec.name == 'EOP') continue;

      final startBag = rec.bagIdx;
      final endBag = nextRec.bagIdx;

      final zones = <Zone>[];
      Zone? globalZone;

      for (int b = startBag; b < endBag && b < bagRecords.length; b++) {
        final bag = bagRecords[b];
        final nextBagGen = (b + 1 < bagRecords.length) ? bagRecords[b + 1].genIdx : (pgenBytes.length ~/ 4);

        final gens = _parseGenerators(genReader, bag.genIdx, nextBagGen);

        final isGlobal = !gens.containsKey(41); // 41 = instrument

        if (isGlobal) {
          globalZone = _createZoneFromGens(gens, globalZone: null, sampleMap: sampleMap);
        } else {
          final zone = _createZoneFromGens(gens, globalZone: globalZone, sampleMap: sampleMap);
          zones.add(zone);
        }
      }

      presets.add(Preset(
        bank: rec.bank,
        program: rec.preset,
        name: rec.name,
        zones: zones,
        library: rec.library,
        genre: rec.genre,
        morphology: rec.morphology,
      ));
    }

    return presets;
  }

  Map<int, int> _parseGenerators(RiffReader genReader, int startIdx, int endIdx) {
    final map = <int, int>{};
    genReader.offset = startIdx * 4;
    for (int g = startIdx; g < endIdx; g++) {
      if (genReader.remaining < 4) break;
      final oper = genReader.readUint16();
      final amount = genReader.readUint16();
      map[oper] = amount;
    }
    return map;
  }

  Zone _createZoneFromGens(
    Map<int, int> gens, {
    Zone? globalZone,
    required Map<int, SampleInfo> sampleMap,
  }) {
    int keyMin = globalZone?.keyRangeMin ?? 0;
    int keyMax = globalZone?.keyRangeMax ?? 127;
    if (gens.containsKey(43)) {
      final val = gens[43]!;
      keyMin = val & 0xFF;
      keyMax = (val >> 8) & 0xFF;
    }

    int velMin = globalZone?.velRangeMin ?? 0;
    int velMax = globalZone?.velRangeMax ?? 127;
    if (gens.containsKey(44)) {
      final val = gens[44]!;
      velMin = val & 0xFF;
      velMax = (val >> 8) & 0xFF;
    }

    int? sampleID = gens[53] ?? globalZone?.sampleID;
    int? instID = gens[41] ?? globalZone?.instrumentID;
    SampleInfo? sampleRef = sampleID != null ? sampleMap[sampleID] : null;

    int? rootKey = gens[58] ?? sampleRef?.originalPitch ?? globalZone?.rootKey;
    int? fineTune = gens[52] ?? globalZone?.pitchCorrection;

    double? attenuation = globalZone?.attenuation;
    if (gens.containsKey(48)) {
      attenuation = gens[48]! / 10.0;
    }

    double? pan = globalZone?.pan;
    if (gens.containsKey(17)) {
      final rawPan = _toSigned16(gens[17]!);
      pan = (rawPan / 500.0).clamp(-1.0, 1.0);
    }

    LoopMode? loopMode = globalZone?.loopMode;
    if (gens.containsKey(54)) {
      final modeVal = gens[54]!;
      if (modeVal == 1) {
        loopMode = LoopMode.continuous;
      } else if (modeVal == 3) {
        loopMode = LoopMode.sustain;
      } else {
        loopMode = LoopMode.none;
      }
    }

    return Zone(
      keyRangeMin: keyMin,
      keyRangeMax: keyMax,
      velRangeMin: velMin,
      velRangeMax: velMax,
      rootKey: rootKey,
      pitchCorrection: fineTune,
      attenuation: attenuation,
      pan: pan,
      sampleID: sampleID,
      sampleRef: sampleRef,
      instrumentID: instID,
      loopMode: loopMode,
      volEnvAttack: _timecentsToSeconds(gens[34] ?? _toRaw16(globalZone?.volEnvAttack)),
      volEnvHold: _timecentsToSeconds(gens[35] ?? _toRaw16(globalZone?.volEnvHold)),
      volEnvDecay: _timecentsToSeconds(gens[36] ?? _toRaw16(globalZone?.volEnvDecay)),
      volEnvSustain: gens.containsKey(37) ? (gens[37]! / 1000.0) : globalZone?.volEnvSustain,
      volEnvRelease: _timecentsToSeconds(gens[38] ?? _toRaw16(globalZone?.volEnvRelease)),
      generators: Map.unmodifiable(gens),
    );
  }

  int _toSigned16(int val) {
    return val >= 0x8000 ? val - 0x10000 : val;
  }

  int? _toRaw16(double? sec) => null;

  double? _timecentsToSeconds(int? timecents) {
    if (timecents == null || timecents == -32768) return null;
    final signedTC = _toSigned16(timecents);
    return math.pow(2.0, signedTC / 1200.0).toDouble();
  }
}

class _InstRecord {
  final String name;
  final int bagIdx;
  _InstRecord({required this.name, required this.bagIdx});
}

class _PhdrRecord {
  final String name;
  final int preset;
  final int bank;
  final int bagIdx;
  final int library;
  final int genre;
  final int morphology;

  _PhdrRecord({
    required this.name,
    required this.preset,
    required this.bank,
    required this.bagIdx,
    required this.library,
    required this.genre,
    required this.morphology,
  });
}

class _BagRecord {
  final int genIdx;
  final int modIdx;
  _BagRecord({required this.genIdx, required this.modIdx});
}
