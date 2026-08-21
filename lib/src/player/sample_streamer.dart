import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import '../models/sample_info.dart';
import '../models/soundfont_format.dart';
import '../soundfont_file.dart';

/// Low-latency audio loader and streamer that connects SoundFont samples
/// to SoLoud's memory audio sources and buffer streams.
class SampleStreamer {
  const SampleStreamer._();

  /// Converts [SampleCompression] to SoLoud's [BufferType].
  static BufferType resolveBufferType(SampleCompression compression) {
    return switch (compression) {
      SampleCompression.pcm8 => BufferType.s8,
      SampleCompression.pcm16 => BufferType.s16le,
      SampleCompression.pcm24 => BufferType.s32le,
      SampleCompression.pcm32 => BufferType.s32le,
      SampleCompression.pcmFloat32 => BufferType.f32le,
      SampleCompression.ogg => BufferType.auto,
      SampleCompression.flac => BufferType.auto,
      SampleCompression.wav => BufferType.auto,
    };
  }

  /// Converts channel count to SoLoud's [Channels].
  static Channels resolveChannels(int channels) {
    return switch (channels) {
      1 => Channels.mono,
      2 => Channels.stereo,
      4 => Channels.quad,
      6 => Channels.surround51,
      8 => Channels.dolby71,
      _ => Channels.stereo,
    };
  }

  /// Creates a standard 44-byte RIFF/WAV header prepended to raw PCM bytes.
  static Uint8List createWavBytes({
    required Uint8List pcmBytes,
    required int sampleRate,
    required int channels,
    required int bitDepth,
  }) {
    final byteRate = sampleRate * channels * (bitDepth ~/ 8);
    final blockAlign = channels * (bitDepth ~/ 8);
    final dataSize = pcmBytes.length;
    final chunkSize = 36 + dataSize;

    final header = Uint8List(44);
    final b = ByteData.sublistView(header);

    // RIFF header
    b.setUint8(0, 0x52); // 'R'
    b.setUint8(1, 0x49); // 'I'
    b.setUint8(2, 0x46); // 'F'
    b.setUint8(3, 0x46); // 'F'
    b.setUint32(4, chunkSize, Endian.little);
    b.setUint8(8, 0x57); // 'W'
    b.setUint8(9, 0x41); // 'A'
    b.setUint8(10, 0x56); // 'V'
    b.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    b.setUint8(12, 0x66); // 'f'
    b.setUint8(13, 0x6D); // 'm'
    b.setUint8(14, 0x74); // 't'
    b.setUint8(15, 0x20); // ' '
    b.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    b.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
    b.setUint16(22, channels, Endian.little);
    b.setUint32(24, sampleRate, Endian.little);
    b.setUint32(28, byteRate, Endian.little);
    b.setUint16(32, blockAlign, Endian.little);
    b.setUint16(34, bitDepth, Endian.little);

    // data subchunk
    b.setUint8(36, 0x64); // 'd'
    b.setUint8(37, 0x61); // 'a'
    b.setUint8(38, 0x74); // 't'
    b.setUint8(39, 0x61); // 'a'
    b.setUint32(40, dataSize, Endian.little);

    final out = Uint8List(44 + dataSize);
    out.setRange(0, 44, header);
    out.setRange(44, 44 + dataSize, pcmBytes);
    return out;
  }

  /// Prepares an encoded or PCM sample buffer for SoLoud loaders, wrapping raw PCM with a WAV header.
  static Uint8List prepareAudioBytes({
    required Uint8List bytes,
    required SampleCompression compression,
    required int sampleRate,
    required int channels,
  }) {
    final isPcm = switch (compression) {
      SampleCompression.pcm8 ||
      SampleCompression.pcm16 ||
      SampleCompression.pcm24 ||
      SampleCompression.pcm32 ||
      SampleCompression.pcmFloat32 => true,
      _ => false,
    };

    if (!isPcm) return bytes;

    final bitDepth = switch (compression) {
      SampleCompression.pcm8 => 8,
      SampleCompression.pcm16 => 16,
      SampleCompression.pcm24 => 24,
      SampleCompression.pcm32 => 32,
      SampleCompression.pcmFloat32 => 32,
      _ => 16,
    };

    return createWavBytes(
      pcmBytes: bytes,
      sampleRate: sampleRate > 0 ? sampleRate : 44100,
      channels: channels > 0 ? channels : 1,
      bitDepth: bitDepth,
    );
  }

  /// Loads an uncompressed or container-encoded sample buffer directly into SoLoud memory
  /// via `loadMem`, returning a fully decoded, seekable, multi-voice [AudioSource].
  static Future<AudioSource?> loadAudioSourceFromBytes({
    required Uint8List bytes,
    required SampleCompression compression,
    required int sampleRate,
    required int channels,
    required String sourceKey,
  }) async {
    if (!SoLoud.instance.isInitialized) return null;

    final wavBytes = prepareAudioBytes(
      bytes: bytes,
      compression: compression,
      sampleRate: sampleRate,
      channels: channels,
    );

    try {
      return await SoLoud.instance.loadMem(
        sourceKey,
        wavBytes,
        mode: LoadMode.memory,
      );
    } catch (_) {
      return null;
    }
  }

  /// Joins two audio sample buffers (Left and Right) into a single 2-channel stereo [AudioSource]
  /// using SoLoud's native [joinTwoSources] C++ engine method.
  static Future<AudioSource?> joinTwoAudioSources({
    required Uint8List leftBytes,
    required Uint8List rightBytes,
    required SampleInfo leftSample,
    required SampleInfo rightSample,
    required String sourceKey,
  }) async {
    if (!SoLoud.instance.isInitialized) return null;

    final preparedLeft = prepareAudioBytes(
      bytes: leftBytes,
      compression: leftSample.compression,
      sampleRate: leftSample.sampleRate,
      channels: leftSample.channels,
    );

    final preparedRight = prepareAudioBytes(
      bytes: rightBytes,
      compression: rightSample.compression,
      sampleRate: rightSample.sampleRate,
      channels: rightSample.channels,
    );

    try {
      return await SoLoud.instance.joinTwoSources(
        sourceKey,
        preparedLeft,
        preparedRight,
      );
    } catch (_) {
      return null;
    }
  }

  /// Loads pre-joined stereo 16-bit PCM bytes into SoLoud memory as a 2-channel [AudioSource].
  static Future<AudioSource?> loadStereoPcmAudioSource({
    required Uint8List stereoPcmBytes,
    required int sampleRate,
    required String sourceKey,
  }) async {
    if (!SoLoud.instance.isInitialized) return null;
    final effectiveRate = sampleRate > 0 ? sampleRate : 44100;
    final wavBytes = createWavBytes(
      pcmBytes: stereoPcmBytes,
      sampleRate: effectiveRate,
      channels: 2,
      bitDepth: 16,
    );
    try {
      return await SoLoud.instance.loadMem(
        sourceKey,
        wavBytes,
        mode: LoadMode.memory,
      );
    } catch (_) {
      return null;
    }
  }

  /// Fallback: Sets up a SoLoud buffer stream and streams sample bytes asynchronously.
  static AudioSource streamSample({
    required SoundFontFile soundFont,
    required SampleInfo sample,
    Uint8List? preloadedBytes,
    int chunkSize = 16384,
    BufferingType bufferingType = BufferingType.preserved,
    bool autoDispose = false,
  }) {
    final format = resolveBufferType(sample.compression);
    final channels = resolveChannels(sample.channels);

    final audio = SoLoud.instance.setBufferStream(
      autoDispose: autoDispose,
      bufferingType: BufferingType.preserved,
      bufferingTimeNeeds: 0,
      format: format,
      channels: channels,
      sampleRate: sample.sampleRate > 0 ? sample.sampleRate : 44100,
    );

    if (preloadedBytes != null && preloadedBytes.isNotEmpty) {
      _feedBytesSync(audio, preloadedBytes, chunkSize);
    } else {
      _feedStreamAsync(audio, soundFont.getSampleByteStream(sample, chunkSize: chunkSize));
    }

    return audio;
  }

  /// Fallback: Streams pre-joined stereo PCM bytes to a stereo SoLoud buffer stream.
  static AudioSource streamStereoPcm({
    required Uint8List stereoPcmBytes,
    required int sampleRate,
    int chunkSize = 16384,
    BufferingType bufferingType = BufferingType.preserved,
    bool autoDispose = false,
  }) {
    final audio = SoLoud.instance.setBufferStream(
      autoDispose: autoDispose,
      bufferingType: BufferingType.preserved,
      bufferingTimeNeeds: 0,
      format: BufferType.s16le,
      channels: Channels.stereo,
      sampleRate: sampleRate > 0 ? sampleRate : 44100,
    );

    _feedBytesSync(audio, stereoPcmBytes, chunkSize);
    return audio;
  }

  static void _feedBytesSync(
    AudioSource audio,
    Uint8List bytes,
    int chunkSize,
  ) {
    try {
      if (SoLoud.instance.isValidAudioSource(audio)) {
        SoLoud.instance.addAudioDataStream(audio, bytes);
        SoLoud.instance.setDataIsEnded(audio);
      }
    } catch (_) {
      // Source may have been stopped or disposed early
    }
  }

  static void _feedStreamAsync(
    AudioSource audio,
    Stream<Uint8List> stream,
  ) {
    scheduleMicrotask(() async {
      try {
        await for (final chunk in stream) {
          if (!SoLoud.instance.isValidAudioSource(audio)) break;
          if (chunk.isNotEmpty) {
            SoLoud.instance.addAudioDataStream(audio, chunk);
          }
        }
        if (SoLoud.instance.isValidAudioSource(audio)) {
          SoLoud.instance.setDataIsEnded(audio);
        }
      } catch (_) {
        // Source may have been stopped or disposed early
      }
    });
  }
}
