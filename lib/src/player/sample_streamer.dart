import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import '../models/sample_info.dart';
import '../models/soundfont_format.dart';
import '../soundfont_file.dart';

/// Low-latency audio streamer that connects SoundFont sample byte streams
/// to SoLoud's buffer streams.
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

  /// Sets up a SoLoud buffer stream and streams sample bytes asynchronously,
  /// returning the [AudioSource] immediately for instant playback.
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

  /// Streams pre-joined stereo PCM bytes to a stereo SoLoud buffer stream.
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
      for (int i = 0; i < bytes.length; i += chunkSize) {
        if (!SoLoud.instance.isValidAudioSource(audio)) break;
        final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        final chunk = Uint8List.sublistView(bytes, i, end);
        SoLoud.instance.addAudioDataStream(audio, chunk);
      }
      if (SoLoud.instance.isValidAudioSource(audio)) {
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
