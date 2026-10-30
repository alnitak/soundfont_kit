import 'dart:convert';
import 'dart:typed_data';

/// A sequential binary reader wrapper around [Uint8List] and [ByteData] for RIFF chunk parsing.
class RiffReader {
  /// The underlying byte buffer.
  final Uint8List bytes;

  /// The [ByteData] view over [bytes].
  final ByteData byteData;

  /// Current read cursor position in bytes.
  int offset;

  /// Creates a [RiffReader] over [data] starting at [offset].
  RiffReader(Uint8List data, [this.offset = 0])
    : bytes = data,
      byteData = ByteData.sublistView(data);

  /// Total byte length of [bytes].
  int get length => bytes.length;

  /// Number of unread bytes remaining from [offset] to [length].
  int get remaining => length - offset;

  /// Whether there are unread bytes remaining in the buffer.
  bool get hasMore => offset < length;

  /// Reads an unsigned 8-bit integer and advances [offset] by 1 byte.
  int readUint8() {
    final v = byteData.getUint8(offset);
    offset += 1;
    return v;
  }

  /// Reads a signed 8-bit integer and advances [offset] by 1 byte.
  int readInt8() {
    final v = byteData.getInt8(offset);
    offset += 1;
    return v;
  }

  /// Reads a little-endian unsigned 16-bit integer and advances [offset] by 2 bytes.
  int readUint16() {
    final v = byteData.getUint16(offset, Endian.little);
    offset += 2;
    return v;
  }

  /// Reads a little-endian signed 16-bit integer and advances [offset] by 2 bytes.
  int readInt16() {
    final v = byteData.getInt16(offset, Endian.little);
    offset += 2;
    return v;
  }

  /// Reads a little-endian unsigned 32-bit integer and advances [offset] by 4 bytes.
  int readUint32() {
    final v = byteData.getUint32(offset, Endian.little);
    offset += 4;
    return v;
  }

  /// Reads a little-endian signed 32-bit integer and advances [offset] by 4 bytes.
  int readInt32() {
    final v = byteData.getInt32(offset, Endian.little);
    offset += 4;
    return v;
  }

  /// Reads a 4-character ASCII FourCC identifier and advances [offset] by 4 bytes.
  String readFourCC() {
    final str = ascii.decode(
      bytes.sublist(offset, offset + 4),
      allowInvalid: true,
    );
    offset += 4;
    return str;
  }

  /// Reads a null-terminated or fixed-length ASCII string of [byteLen] bytes and advances [offset].
  String readString(int byteLen) {
    final raw = bytes.sublist(offset, offset + byteLen);
    offset += byteLen;
    // Find null terminator if present
    final nullIdx = raw.indexOf(0);
    final validBytes = nullIdx >= 0 ? raw.sublist(0, nullIdx) : raw;
    return ascii.decode(validBytes, allowInvalid: true).trim();
  }

  /// Reads a raw [Uint8List] slice of [count] bytes and advances [offset].
  Uint8List readBytes(int count) {
    final slice = bytes.sublist(offset, offset + count);
    offset += count;
    return slice;
  }

  /// Returns a new [RiffReader] over the next [len] bytes and advances [offset] by [len].
  RiffReader slice(int len) {
    final sub = bytes.sublist(offset, offset + len);
    offset += len;
    return RiffReader(sub);
  }
}

/// Helper data structure representing a RIFF chunk header.
class RiffChunk {
  /// FourCC chunk identifier (e.g., `'RIFF'`, `'LIST'`, `'shdr'`).
  final String id;

  /// Payload size of the chunk in bytes.
  final int length;

  /// Starting byte offset of the chunk payload in the parent stream.
  final int offset;

  /// Optional 4-character form or list type for `'RIFF'` and `'LIST'` chunks.
  final String? type;

  /// Creates a [RiffChunk] descriptor.
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
