import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'dual_voice_segmenter.dart';
import 'kokoro_voices.dart';
import 'tts_engine.dart';
import 'wav_encoder.dart';

/// Filesystem locations of the Kokoro ONNX model + assets.
class TtsModelPaths {
  const TtsModelPaths(this.modelDir);

  final String modelDir;

  String get kokoroModel => '$modelDir/model.onnx';
  String get kokoroVoices => '$modelDir/voices.bin';
  String get tokens => '$modelDir/tokens.txt';
  String get espeakData => '$modelDir/espeak-ng-data';
  // Present only in the zh bilingual model (kokoro-multi-lang-v1_1). The
  // English-only model (kokoro-en-v0_19) has neither. Pass '' when absent —
  // sherpa-onnx skips validation for empty-string optional paths.
  String get dictDir {
    final path = '$modelDir/dict';
    return Directory(path).existsSync() ? path : '';
  }
  // sherpa-onnx Validate() calls FileExists() on the whole lexicon string
  // (no space-splitting), so only one path can be passed here. Present in zh
  // model only; absent in the English model which uses espeak directly.
  String get lexicon {
    final path = '$modelDir/lexicon-us-en.txt';
    return File(path).existsSync() ? path : '';
  }
}

/// On-device Piper/Kokoro TTS via sherpa_onnx.
///
/// Generation runs in a **dedicated background isolate** — `OfflineTts.generate`
/// is a blocking native call, and running it on the main isolate froze the UI
/// thread (ANR / "app not responding" on tap/play). The worker loads the model
/// once and serves generation requests; the main isolate only awaits results,
/// so the UI stays responsive. Output is 16-bit PCM WAV (played by just_audio).
class SherpaOnnxTtsEngine implements TtsEngine {
  SherpaOnnxTtsEngine({
    required this.paths,
    // Fallback speaker ids when the chosen voice isn't a known Kokoro voice
    // (e.g. a legacy edge name still stored): am_michael / af_heart.
    this.narratorSid = 16,
    this.dialogueSid = 3,
    this.speed = 1.0,
    this.numThreads = 4,
  });

  final TtsModelPaths paths;
  final int narratorSid;
  final int dialogueSid;
  final double speed;

  /// ONNX intra-op threads. 4 threads → RTF ≈ 0.65–0.75 on a flagship
  /// (well ahead of real-time) with thermal headroom on Snapdragon 8 Elite.
  /// Drop to 3 on mid-range devices (RTF ≈ 0.85–0.95 but still under 1.0).
  /// (A quantized/int8 model would cut this further.)
  final int numThreads;

  Isolate? _isolate;
  SendPort? _cmdPort;
  ReceivePort? _fromWorker;
  Completer<void>? _ready;
  int _nextId = 0;
  final Map<int, Completer<TtsAudio>> _pending = {};

  Future<void> _ensureWorker() {
    final existing = _ready;
    if (existing != null) return existing.future;

    final ready = Completer<void>();
    _ready = ready;
    final fromWorker = ReceivePort();
    _fromWorker = fromWorker;
    fromWorker.listen((msg) => _onWorkerMessage(msg, ready));
    Isolate.spawn(_workerMain, fromWorker.sendPort).then((iso) {
      _isolate = iso;
    }).catchError((Object e) {
      if (!ready.isCompleted) ready.completeError(e);
    });
    return ready.future;
  }

  void _onWorkerMessage(dynamic msg, Completer<void> ready) {
    if (msg is SendPort) {
      _cmdPort = msg;
      // Hand the worker the model config so it can load the model once.
      msg.send(<String, dynamic>{
        'type': 'init',
        'model': paths.kokoroModel,
        'voices': paths.kokoroVoices,
        'tokens': paths.tokens,
        'dataDir': paths.espeakData,
        'dictDir': paths.dictDir,
        'lexicon': paths.lexicon,
        'numThreads': numThreads,
      });
      return;
    }
    if (msg is! Map) return;
    switch (msg['type']) {
      case 'ready':
        if (!ready.isCompleted) ready.complete();
        break;
      case 'initError':
        if (!ready.isCompleted) {
          ready.completeError(StateError(msg['error'] as String? ?? 'TTS init failed'));
        }
        break;
      case 'result':
        final id = msg['id'] as int;
        final c = _pending.remove(id);
        if (c == null) return;
        final err = msg['error'] as String?;
        if (err != null) {
          c.completeError(StateError(err));
          return;
        }
        final bytes = msg['wav'] as Uint8List;
        if (kDebugMode) {
          final genMs = msg['genMs'] as int;
          final audioMs = msg['audioMs'] as int;
          final rtf = audioMs > 0 ? genMs / audioMs : 0.0;
          debugPrint(
            '[tts] gen ${genMs}ms → ${(audioMs / 1000).toStringAsFixed(2)}s audio | '
            'RTF=${rtf.toStringAsFixed(2)} '
            '${rtf > 0 && rtf < 1 ? "(faster than real-time)" : "(SLOWER than real-time)"}',
          );
        }
        c.complete(TtsAudio(bytes, 'wav'));
        break;
    }
  }

  @override
  Future<bool> isAvailable() async {
    return Directory(paths.modelDir).existsSync() &&
        File(paths.kokoroModel).existsSync();
  }

  @override
  Future<TtsAudio> synthParagraph({
    required String text,
    // Voice ids from the picker (see KokoroVoices). Unknown ids fall back to
    // narratorSid / dialogueSid.
    required String paragraphVoice,
    required String dialogueVoice,
  }) async {
    await _ensureWorker();
    final id = _nextId++;
    final completer = Completer<TtsAudio>();
    _pending[id] = completer;
    _cmdPort!.send(<String, dynamic>{
      'type': 'gen',
      'id': id,
      'text': text,
      'narratorSid': KokoroVoices.sidFor(paragraphVoice, fallback: narratorSid),
      'dialogueSid': KokoroVoices.sidFor(dialogueVoice, fallback: dialogueSid),
      'speed': speed,
    });
    return completer.future;
  }

  @override
  Future<void> dispose() async {
    _cmdPort?.send(const <String, dynamic>{'type': 'dispose'});
    _isolate?.kill(priority: Isolate.immediate);
    _fromWorker?.close();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('TTS engine disposed'));
    }
    _pending.clear();
    _isolate = null;
    _cmdPort = null;
    _fromWorker = null;
    _ready = null;
  }
}

// ─────────────────────── Worker isolate ───────────────────────

/// Entry point of the TTS worker isolate. Owns the loaded [sherpa.OfflineTts]
/// and generates audio off the main thread. Requests are processed one at a
/// time (generation is a blocking native call) — which suits the serial nature
/// of on-device synthesis and keeps CPU bounded.
void _workerMain(SendPort toMain) {
  final cmd = ReceivePort();
  toMain.send(cmd.sendPort);

  sherpa.OfflineTts? tts;

  cmd.listen((message) {
    if (message is! Map) return;
    switch (message['type']) {
      case 'init':
        try {
          sherpa.initBindings();
          final modelConfig = sherpa.OfflineTtsModelConfig(
            kokoro: sherpa.OfflineTtsKokoroModelConfig(
              model: message['model'] as String,
              voices: message['voices'] as String,
              tokens: message['tokens'] as String,
              dataDir: message['dataDir'] as String,
              dictDir: message['dictDir'] as String? ?? '',
              lexicon: message['lexicon'] as String? ?? '',
            ),
            numThreads: message['numThreads'] as int,
            provider: 'cpu',
          );
          tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: modelConfig));
          toMain.send(const <String, dynamic>{'type': 'ready'});
        } catch (e) {
          toMain.send(<String, dynamic>{
            'type': 'initError',
            'error': e.toString(),
          });
        }
        break;

      case 'gen':
        final id = message['id'] as int;
        final engine = tts;
        if (engine == null) {
          toMain.send(<String, dynamic>{
            'type': 'result',
            'id': id,
            'error': 'TTS not initialized',
          });
          return;
        }
        try {
          final sw = Stopwatch()..start();
          final segments = DualVoiceSegmenter.segment(message['text'] as String);
          final chunks = <Float32List>[];
          var sampleRate = 24000;
          for (final seg in segments) {
            final segText = _ensureTerminalPunctuation(seg.text);
            final audio = engine.generate(
              text: segText,
              sid: seg.isDialogue
                  ? message['dialogueSid'] as int
                  : message['narratorSid'] as int,
              speed: message['speed'] as double,
            );
            sampleRate = audio.sampleRate;
            chunks.add(audio.samples);
          }
          sw.stop();
          final faded = applyFade(_concat(chunks), sampleRate);
          // Append a 250ms trailing silence pad so short headings ("Underlord",
          // "Chapter 16") decay cleanly before the next paragraph starts.
          final samples = _concat([faded, Float32List((sampleRate * 0.25).round())]);
          final wav = encodeWavPcm16(samples, sampleRate);
          final audioMs =
              sampleRate > 0 ? (samples.length * 1000 / sampleRate).round() : 0;
          toMain.send(<String, dynamic>{
            'type': 'result',
            'id': id,
            'wav': wav,
            'genMs': sw.elapsedMilliseconds,
            'audioMs': audioMs,
          });
        } catch (e) {
          toMain.send(<String, dynamic>{
            'type': 'result',
            'id': id,
            'error': e.toString(),
          });
        }
        break;

      case 'dispose':
        tts?.free();
        tts = null;
        cmd.close();
        break;
    }
  });
}

// ─────────────────────── helpers (shared by worker) ───────────────────────

final _terminalPunct = RegExp(r'[.!?…:;—][”"\x27)\]]*$');

String _ensureTerminalPunctuation(String raw) {
  final cleaned = raw.replaceAll('[', ' ').replaceAll(']', ' ').trim();
  if (cleaned.isEmpty) return raw;
  return _terminalPunct.hasMatch(cleaned) ? cleaned : '$cleaned.';
}

Float32List _concat(List<Float32List> parts) {
  final total = parts.fold<int>(0, (n, p) => n + p.length);
  final out = Float32List(total);
  var offset = 0;
  for (final p in parts) {
    out.setAll(offset, p);
    offset += p.length;
  }
  return out;
}
