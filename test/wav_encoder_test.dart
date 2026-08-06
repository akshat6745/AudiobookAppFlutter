import 'dart:convert';
import 'dart:typed_data';

import 'package:audiobook_app/services/tts/wav_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('encodeWavPcm16', () {
    test('produces a RIFF/WAVE header', () {
      final wav = encodeWavPcm16(Float32List(0), 24000);
      expect(utf8.decode(wav.sublist(0, 4)), 'RIFF');
      expect(utf8.decode(wav.sublist(8, 12)), 'WAVE');
      expect(utf8.decode(wav.sublist(12, 16)), 'fmt ');
      expect(utf8.decode(wav.sublist(36, 40)), 'data');
    });

    test('fmt chunk declares PCM format 1', () {
      final wav = encodeWavPcm16(Float32List(0), 24000);
      final bd = wav.buffer.asByteData();
      // fmt chunk size = 16
      expect(bd.getUint32(16, Endian.little), 16);
      // audio format = 1 (PCM)
      expect(bd.getUint16(20, Endian.little), 1);
      // channels = 1 (mono)
      expect(bd.getUint16(22, Endian.little), 1);
      // bit depth = 16
      expect(bd.getUint16(34, Endian.little), 16);
    });

    test('sample rate is encoded correctly', () {
      for (final sr in [16000, 22050, 24000, 44100]) {
        final wav = encodeWavPcm16(Float32List(100), sr);
        final bd = wav.buffer.asByteData();
        expect(bd.getUint32(24, Endian.little), sr,
            reason: 'sample rate $sr mismatch');
      }
    });

    test('data chunk size equals samples * 2', () {
      final n = 100;
      final wav = encodeWavPcm16(Float32List(n), 24000);
      final bd = wav.buffer.asByteData();
      expect(bd.getUint32(40, Endian.little), n * 2);
      // Total file size = 44 header + n*2 data bytes
      expect(wav.length, 44 + n * 2);
    });

    test('RIFF chunk size equals 36 + data size', () {
      final n = 50;
      final wav = encodeWavPcm16(Float32List(n), 24000);
      final bd = wav.buffer.asByteData();
      expect(bd.getUint32(4, Endian.little), 36 + n * 2);
    });

    test('silence (0.0 samples) encodes to all-zero PCM bytes', () {
      final samples = Float32List(4); // all zeros
      final wav = encodeWavPcm16(samples, 24000);
      for (var i = 44; i < wav.length; i++) {
        expect(wav[i], 0, reason: 'byte $i should be 0 for silence');
      }
    });

    test('+1.0 encodes to 32767 and -1.0 encodes to -32767', () {
      // Float32 × 32767 (not 32768) is the standard mapping used here.
      final samples = Float32List.fromList([1.0, -1.0]);
      final wav = encodeWavPcm16(samples, 24000);
      final bd = wav.buffer.asByteData();
      expect(bd.getInt16(44, Endian.little), 32767);
      expect(bd.getInt16(46, Endian.little), -32767);
    });

    test('empty sample list produces 44-byte header only', () {
      final wav = encodeWavPcm16(Float32List(0), 24000);
      expect(wav.length, 44);
    });

    test('over-range samples are clamped, not wrapped', () {
      final samples = Float32List.fromList([2.0, -3.0]);
      final wav = encodeWavPcm16(samples, 24000);
      final bd = wav.buffer.asByteData();
      expect(bd.getInt16(44, Endian.little), 32767);
      expect(bd.getInt16(46, Endian.little), -32768);
    });
  });
}
