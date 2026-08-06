import 'dart:math' as math;
import 'dart:typed_data';

/// Apply a short linear fade-in and fade-out to [samples] in-place.
/// Prevents audible clicks at paragraph boundaries. Default 50 ms per fade.
Float32List applyFade(Float32List samples, int sampleRate, {int fadeMs = 50}) {
  final fadeSamples =
      (sampleRate * fadeMs / 1000).round().clamp(0, samples.length ~/ 2);
  if (fadeSamples == 0) return samples;
  final out = Float32List.fromList(samples);
  for (var i = 0; i < fadeSamples; i++) {
    final gain = i / fadeSamples;
    out[i] *= gain;
    out[out.length - 1 - i] *= gain;
  }
  return out;
}

/// Encode mono Float32 PCM samples (values in [-1, 1]) as a standard 16-bit
/// PCM WAV file. This is the format just_audio/ExoPlayer expect for local
/// playback.
Uint8List encodeWavPcm16(Float32List samples, int sampleRate) {
  const channels = 1;
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final dataSize = samples.length * 2;

  final buf = BytesBuilder();
  void str(String s) => buf.add(s.codeUnits);
  void u32(int v) =>
      buf.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) =>
      buf.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

  str('RIFF');
  u32(36 + dataSize);
  str('WAVE');
  str('fmt ');
  u32(16);
  u16(1); // PCM
  u16(channels);
  u32(sampleRate);
  u32(byteRate);
  u16(blockAlign);
  u16(bitsPerSample);
  str('data');
  u32(dataSize);

  final pcm = Uint8List(dataSize);
  final view = pcm.buffer.asByteData();
  for (var i = 0; i < samples.length; i++) {
    final s = (samples[i] * 32767.0).clamp(-32768.0, 32767.0).toInt();
    view.setInt16(i * 2, s, Endian.little);
  }
  buf.add(pcm);

  return buf.toBytes();
}
