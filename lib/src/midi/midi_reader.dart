import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'midi_models.dart';

/// High-performance binary parser for Standard MIDI Files (SMF format 0, 1, 2).
class MidiReader {
  /// Parses a [MidiFile] from raw binary [bytes].
  static MidiFile fromBytes(Uint8List bytes) {
    final byteData = ByteData.sublistView(bytes);
    int offset = 0;

    // 1. Parse MThd Chunk
    if (bytes.length < 14) {
      throw const FormatException('Invalid MIDI file: data too short for header.');
    }

    final headerMagic = _readFourCC(bytes, offset);
    offset += 4;
    if (headerMagic != 'MThd') {
      throw FormatException('Invalid MIDI file: expected "MThd" header, got "$headerMagic".');
    }

    final headerLength = byteData.getUint32(offset, Endian.big);
    offset += 4;
    if (headerLength < 6) {
      throw FormatException('Invalid MIDI header length: $headerLength (expected >= 6).');
    }

    final format = byteData.getUint16(offset, Endian.big);
    offset += 2;
    final numTracks = byteData.getUint16(offset, Endian.big);
    offset += 2;
    final timeDivision = byteData.getUint16(offset, Endian.big);
    offset += 2;

    // Skip any extra header bytes if headerLength > 6
    if (headerLength > 6) {
      offset += (headerLength - 6);
    }

    final header = MidiHeader(
      format: format,
      numTracks: numTracks,
      timeDivision: timeDivision,
    );

    // 2. Parse MTrk Chunks
    final tracks = <MidiTrack>[];
    int trackIndex = 0;

    while (offset + 8 <= bytes.length && tracks.length < numTracks) {
      final chunkType = _readFourCC(bytes, offset);
      offset += 4;
      final chunkLength = byteData.getUint32(offset, Endian.big);
      offset += 4;

      if (chunkType == 'MTrk') {
        final trackEnd = (offset + chunkLength).clamp(0, bytes.length);
        final trackEvents = <MidiEvent>[];
        int absoluteTick = 0;
        int runningStatus = 0;
        String? trackName;

        while (offset < trackEnd) {
          // Read variable-length delta time
          final (deltaTime, vlqBytes) = _readVLQ(bytes, offset);
          offset += vlqBytes;
          absoluteTick += deltaTime;

          if (offset >= trackEnd) break;

          int statusByte = bytes[offset];

          if ((statusByte & 0x80) != 0) {
            // New status byte
            runningStatus = statusByte;
            offset++;
          } else {
            // Running status applies (reuse previous runningStatus, offset is unchanged)
            if (runningStatus == 0) {
              throw FormatException(
                'Invalid MIDI track #$trackIndex: data byte 0x${statusByte.toRadixString(16)} encountered without prior status byte.',
              );
            }
            statusByte = runningStatus;
          }

          if (statusByte == 0xFF) {
            // Meta Event
            if (offset >= trackEnd) break;
            final metaType = bytes[offset++];
            final (metaLength, metaVlqBytes) = _readVLQ(bytes, offset);
            offset += metaVlqBytes;

            final metaEnd = (offset + metaLength).clamp(0, trackEnd);
            final metaData = bytes.sublist(offset, metaEnd);
            offset = metaEnd;

            final metaEvent = _parseMetaEvent(
              metaType: metaType,
              data: metaData,
              deltaTime: deltaTime,
              absoluteTick: absoluteTick,
            );
            trackEvents.add(metaEvent);

            if (metaEvent is TrackNameEvent && trackName == null) {
              trackName = metaEvent.text;
            }

            if (metaEvent is EndOfTrackEvent) {
              // Reached end of track event
              offset = trackEnd;
              break;
            }
          } else if (statusByte == 0xF0 || statusByte == 0xF7) {
            // SysEx Event
            final (sysExLength, sysExVlqBytes) = _readVLQ(bytes, offset);
            offset += sysExVlqBytes;
            final sysExEnd = (offset + sysExLength).clamp(0, trackEnd);
            final sysExData = bytes.sublist(offset, sysExEnd);
            offset = sysExEnd;

            trackEvents.add(
              SysExEvent(
                data: sysExData,
                deltaTime: deltaTime,
                absoluteTick: absoluteTick,
              ),
            );
          } else {
            // Channel Voice / Mode Message
            final messageType = statusByte & 0xF0;
            final channel = statusByte & 0x0F;

            switch (messageType) {
              case 0x80: // Note Off
                if (offset + 2 > trackEnd) break;
                final note = bytes[offset++];
                final velocity = bytes[offset++];
                trackEvents.add(
                  NoteOffEvent(
                    channel: channel,
                    note: note,
                    velocity: velocity,
                    deltaTime: deltaTime,
                    absoluteTick: absoluteTick,
                  ),
                );
                break;

              case 0x90: // Note On
                if (offset + 2 > trackEnd) break;
                final note = bytes[offset++];
                final velocity = bytes[offset++];
                trackEvents.add(
                  NoteOnEvent(
                    channel: channel,
                    note: note,
                    velocity: velocity,
                    deltaTime: deltaTime,
                    absoluteTick: absoluteTick,
                  ),
                );
                break;

              case 0xA0: // Polyphonic Key Pressure
                if (offset + 2 > trackEnd) break;
                final note = bytes[offset++];
                final pressure = bytes[offset++];
                trackEvents.add(
                  PolyphonicKeyPressureEvent(
                    channel: channel,
                    note: note,
                    pressure: pressure,
                    deltaTime: deltaTime,
                    absoluteTick: absoluteTick,
                  ),
                );
                break;

              case 0xB0: // Control Change
                if (offset + 2 > trackEnd) break;
                final controller = bytes[offset++];
                final value = bytes[offset++];
                trackEvents.add(
                  ControlChangeEvent(
                    channel: channel,
                    controller: controller,
                    value: value,
                    deltaTime: deltaTime,
                    absoluteTick: absoluteTick,
                  ),
                );
                break;

              case 0xC0: // Program Change (1 data byte)
                if (offset + 1 > trackEnd) break;
                final program = bytes[offset++];
                trackEvents.add(
                  ProgramChangeEvent(
                    channel: channel,
                    program: program,
                    deltaTime: deltaTime,
                    absoluteTick: absoluteTick,
                  ),
                );
                break;

              case 0xD0: // Channel Pressure (1 data byte)
                if (offset + 1 > trackEnd) break;
                final pressure = bytes[offset++];
                trackEvents.add(
                  ChannelPressureEvent(
                    channel: channel,
                    pressure: pressure,
                    deltaTime: deltaTime,
                    absoluteTick: absoluteTick,
                  ),
                );
                break;

              case 0xE0: // Pitch Bend (2 data bytes, 14-bit unsigned)
                if (offset + 2 > trackEnd) break;
                final lsb = bytes[offset++];
                final msb = bytes[offset++];
                final value = (msb << 7) | lsb;
                trackEvents.add(
                  PitchBendEvent(
                    channel: channel,
                    value: value,
                    deltaTime: deltaTime,
                    absoluteTick: absoluteTick,
                  ),
                );
                break;

              default:
                // Unrecognized status byte, skip
                break;
            }
          }
        }

        tracks.add(
          MidiTrack(
            trackNumber: trackIndex,
            events: trackEvents,
            name: trackName,
          ),
        );
        trackIndex++;
        offset = trackEnd;
      } else {
        // Skip unknown chunk
        offset += chunkLength;
      }
    }

    return MidiFile(header: header, tracks: tracks);
  }

  /// Parses a [MidiFile] from an existing [File].
  static Future<MidiFile> fromFile(File file) async {
    final bytes = await file.readAsBytes();
    return fromBytes(bytes);
  }

  /// Parses a [MidiFile] synchronously from a [File].
  static MidiFile fromFileSync(File file) {
    final bytes = file.readAsBytesSync();
    return fromBytes(bytes);
  }

  /// Parses a [MidiFile] from a Flutter asset bundle [assetPath].
  static Future<MidiFile> fromAsset(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    return fromBytes(byteData.buffer.asUint8List());
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  static String _readFourCC(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) return '';
    return String.fromCharCodes(bytes.sublist(offset, offset + 4));
  }

  /// Reads a Variable-Length Quantity (VLQ). Returns `(value, bytesConsumed)`.
  static (int, int) _readVLQ(Uint8List bytes, int offset) {
    int value = 0;
    int bytesConsumed = 0;

    while (offset + bytesConsumed < bytes.length && bytesConsumed < 4) {
      final byte = bytes[offset + bytesConsumed];
      bytesConsumed++;
      value = (value << 7) | (byte & 0x7F);
      if ((byte & 0x80) == 0) {
        break;
      }
    }

    return (value, bytesConsumed);
  }

  static MetaEvent _parseMetaEvent({
    required int metaType,
    required Uint8List data,
    required int deltaTime,
    required int absoluteTick,
  }) {
    switch (metaType) {
      case 0x01: // Text Event
        return TextEvent(
          text: _decodeString(data),
          deltaTime: deltaTime,
          absoluteTick: absoluteTick,
        );
      case 0x02: // Copyright Event
        return CopyrightEvent(
          text: _decodeString(data),
          deltaTime: deltaTime,
          absoluteTick: absoluteTick,
        );
      case 0x03: // Track Name
        return TrackNameEvent(
          text: _decodeString(data),
          deltaTime: deltaTime,
          absoluteTick: absoluteTick,
        );
      case 0x04: // Instrument Name
        return InstrumentNameEvent(
          text: _decodeString(data),
          deltaTime: deltaTime,
          absoluteTick: absoluteTick,
        );
      case 0x05: // Lyric
        return LyricEvent(
          text: _decodeString(data),
          deltaTime: deltaTime,
          absoluteTick: absoluteTick,
        );
      case 0x06: // Marker
        return MarkerEvent(
          text: _decodeString(data),
          deltaTime: deltaTime,
          absoluteTick: absoluteTick,
        );
      case 0x07: // Cue Point
        return CuePointEvent(
          text: _decodeString(data),
          deltaTime: deltaTime,
          absoluteTick: absoluteTick,
        );
      case 0x20: // Channel Prefix
        final channel = data.isNotEmpty ? data[0] : 0;
        return ChannelPrefixEvent(
          channel: channel,
          deltaTime: deltaTime,
          absoluteTick: absoluteTick,
        );
      case 0x2F: // End of Track
        return EndOfTrackEvent(
          deltaTime: deltaTime,
          absoluteTick: absoluteTick,
        );
      case 0x51: // Set Tempo
        int tempo = 500000;
        if (data.length >= 3) {
          tempo = (data[0] << 16) | (data[1] << 8) | data[2];
        }
        return SetTempoEvent(
          microsecondsPerQuarterNote: tempo,
          deltaTime: deltaTime,
          absoluteTick: absoluteTick,
        );
      case 0x58: // Time Signature
        final num = data.isNotEmpty ? data[0] : 4;
        final denomExp = data.length > 1 ? data[1] : 2;
        final clocks = data.length > 2 ? data[2] : 24;
        final thirtySeconds = data.length > 3 ? data[3] : 8;
        return TimeSignatureEvent(
          numerator: num,
          denominator: 1 << denomExp,
          clocksPerClick: clocks,
          thirtySecondsPer24Clocks: thirtySeconds,
          deltaTime: deltaTime,
          absoluteTick: absoluteTick,
        );
      case 0x59: // Key Signature
        final sf = data.isNotEmpty ? data[0].toSigned(8) : 0;
        final mi = data.length > 1 ? data[1] : 0;
        return KeySignatureEvent(
          sf: sf,
          mi: mi,
          deltaTime: deltaTime,
          absoluteTick: absoluteTick,
        );
      case 0x7F: // Sequencer Specific
        return SequencerSpecificEvent(
          data: data,
          deltaTime: deltaTime,
          absoluteTick: absoluteTick,
        );
      default:
        return UnknownMetaEvent(
          metaType: metaType,
          data: data,
          deltaTime: deltaTime,
          absoluteTick: absoluteTick,
        );
    }
  }

  static String _decodeString(Uint8List data) {
    try {
      return utf8.decode(data);
    } catch (_) {
      return latin1.decode(data);
    }
  }
}
