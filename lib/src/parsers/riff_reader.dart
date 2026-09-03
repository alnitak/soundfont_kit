import 'dart:convert';
import 'dart:typed_data';

/// A binary reader wrapper around Uint8List/ByteData for RIFF chunk parsing.
class RiffReader {
  final Uint8List bytes;
  final ByteData byteData;
  int offset;

  RiffReader(Uint8List data, [this.offset = 0])
    : bytes = data,
      byteData = ByteData.sublistView(data);

  int get length => bytes.length;
  int get remaining => length - offset;
  bool get hasMore => offset < length;

  int readUint8() {
    final v = byteData.getUint8(offset);
    offset += 1;
    return v;
  }

  int readInt8() {
    final v = byteData.getInt8(offset);
    offset += 1;
    return v;
  }

  int readUint16() {
    final v = byteData.getUint16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int readInt16() {
    final v = byteData.getInt16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int readUint32() {
    final v = byteData.getUint32(offset, Endian.little);
    offset += 4;
    return v;
  }

  int readInt32() {
    final v = byteData.getInt32(offset, Endian.little);
    offset += 4;
    return v;
  }

  String readFourCC() {
    final str = ascii.decode(
      bytes.sublist(offset, offset + 4),
      allowInvalid: true,
    );
    offset += 4;
    return str;
  }

  String readString(int byteLen) {
    final raw = bytes.sublist(offset, offset + byteLen);
    offset += byteLen;
    // Find null terminator if present
    final nullIdx = raw.indexOf(0);
    final validBytes = nullIdx >= 0 ? raw.sublist(0, nullIdx) : raw;
    return ascii.decode(validBytes, allowInvalid: true).trim();
  }

  Uint8List readBytes(int count) {
    final slice = bytes.sublist(offset, offset + count);
    offset += count;
    return slice;
  }

  RiffReader slice(int len) {
    final sub = bytes.sublist(offset, offset + len);
    offset += len;
    return RiffReader(sub);
  }
}

/// Helper data structure representing a RIFF chunk header.
class RiffChunk {
  final String id;
  final int length;
  final int offset;
  final String? type;

  RiffChunk({
    required this.id,
    required this.length,
    required this.offset,
    this.type,
  });

  @override
  String toString() {
    return 'RiffChunk(id: "$id", length: $length, offset: $offset, type: ${type != null ? '"$type"' : 'null'})';
  }
}
