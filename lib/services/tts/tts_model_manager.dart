import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../storage.dart';
import 'sherpa_onnx_tts_engine.dart' show TtsModelPaths;

/// Downloads, extracts, and locates the on-device Kokoro TTS model.
///
/// The model ships as a compressed tar archive (sherpa-onnx release asset)
/// containing `model.onnx`, `voices.bin`, `tokens.txt`, and `espeak-ng-data/`.
/// It is fetched once, extracted into the app documents dir, and the resolved
/// directory (the one holding `model.onnx`) is remembered so later launches use
/// it fully offline.
///
/// NOTE (POC): extraction currently reads the whole archive into memory. Fine
/// on a flagship for the ~300 MB Kokoro model; switch to streaming extraction
/// before shipping to low-memory devices.
class TtsModelManager {
  TtsModelManager({
    required this.archiveUrl,
    required this.subdir,
    required this.modelDirName,
    this.prefsKey = 'tts_model_dir',
  });

  /// Kokoro English model — 54 voices (11 Am. female, 9 Am. male, 4 Br. female,
  /// 4 Br. male + more). See [KokoroVoices]. narrator/dialogue each map to one
  /// speaker id within the model.
  factory TtsModelManager.kokoro() => TtsModelManager(
        archiveUrl:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2',
        subdir: 'kokoro',
        modelDirName: 'kokoro-en-v0_19',
        // Versioned key so an older model's pointer isn't reused.
        prefsKey: 'tts_model_dir_kokoro_en_v0_19',
      );

  final String archiveUrl;
  final String subdir;

  /// The directory the archive extracts to (holds model.onnx). Adoption looks
  /// for exactly this, so a stale older model is never mistaken for the current
  /// one.
  final String modelDirName;
  final String prefsKey;

  /// Installed model paths, or null if no complete model is present.
  ///
  /// Resilient to a missing pref: besides the remembered directory, it scans
  /// the model base dir and adopts any subdirectory that holds a complete model
  /// (a side-loaded model, or one whose pref was lost/never flushed) — so an
  /// on-disk model is never re-downloaded just because the pointer is gone.
  Future<TtsModelPaths?> installedPaths() async {
    if (kIsWeb) return null;

    // 1) Fast path: the remembered directory.
    final saved = await Storage.getString(prefsKey);
    if (saved != null && _isComplete(TtsModelPaths(saved))) {
      return TtsModelPaths(saved);
    }

    // 2) Disk-adopt: the model extracts to <base>/<modelDirName>. Re-adopt it if
    //    the pointer was lost (side-loaded, or prefs cleared). Matching the
    //    exact dir name (not any subdir) avoids adopting a stale/older model.
    final base = await _baseDir();
    final expected = TtsModelPaths('${base.path}/$modelDirName');
    if (kDebugMode) {
      debugPrint('[tts-model] saved=$saved expected=${expected.modelDir} '
          'complete=${_isComplete(expected)}');
    }
    if (_isComplete(expected)) {
      await Storage.setString(prefsKey, expected.modelDir);
      return expected;
    }

    if (kDebugMode) debugPrint('[tts-model] no complete model found');
    return null;
  }

  bool _isComplete(TtsModelPaths paths) =>
      File(paths.kokoroModel).existsSync() &&
      File(paths.kokoroVoices).existsSync() &&
      File(paths.tokens).existsSync() &&
      Directory(paths.espeakData).existsSync();

  Future<Directory> _baseDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'models', subdir));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Download + extract + verify. Reports the download fraction via
  /// [onProgress] (0..1) and signals the extraction phase via [onExtracting].
  Future<TtsModelPaths> downloadAndInstall({
    void Function(double fraction)? onProgress,
    void Function()? onExtracting,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('On-device model download is unsupported on web');
    }

    final base = await _baseDir();
    final archivePath = p.join(base.path, 'download.tmp');

    final dio = Dio();
    // DEBUG-ONLY: on TLS-inspecting networks (corporate proxy / Zero Trust) the
    // model host (github.com → *.githubusercontent.com) is re-signed by a
    // private CA the emulator doesn't trust → CERTIFICATE_VERIFY_FAILED. The
    // download URL is a fixed, trusted constant, so accepting the re-signed cert
    // in debug only affects local testing; release builds keep verification.
    if (kDebugMode) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () =>
            HttpClient()..badCertificateCallback = (cert, host, port) => true,
      );
    }
    await dio.download(
      archiveUrl,
      archivePath,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );

    onExtracting?.call();
    final modelDir = await _extract(archivePath, base);

    try {
      File(archivePath).deleteSync();
    } catch (_) {}

    final paths = TtsModelPaths(modelDir);
    if (!File(paths.kokoroModel).existsSync()) {
      throw StateError('Model archive did not contain model.onnx');
    }
    await Storage.setString(prefsKey, modelDir);
    // Reclaim space from any previously-installed (older) model. Keep the
    // directory we actually extracted to, whatever its name.
    await _removeStaleModels(base, keep: p.basename(modelDir));
    return paths;
  }

  /// Delete model subdirectories other than [keep] (e.g. an older version left
  /// over after an upgrade).
  Future<void> _removeStaleModels(Directory base, {required String keep}) async {
    for (final dir in base.listSync().whereType<Directory>()) {
      if (dir.path.split('/').last != keep) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Extract a `.tar.bz2` / `.tar.gz` into [targetBase]. The bz2/tar decode is
  /// CPU-heavy and synchronous, so it runs in a **background isolate** — doing
  /// it on the main isolate blocked the UI thread long enough to ANR-crash the
  /// app right when the (large) download finished. Returns the directory
  /// containing `model.onnx`.
  Future<String> _extract(String archivePath, Directory targetBase) {
    final isGzip = archiveUrl.endsWith('.gz');
    final basePath = targetBase.path;
    return Isolate.run(
      () => _extractArchiveSync(archivePath, basePath, isGzip),
    );
  }

  /// Remove the installed model and forget its location.
  Future<void> delete() async {
    if (kIsWeb) return;
    final base = await _baseDir();
    try {
      if (base.existsSync()) base.deleteSync(recursive: true);
    } catch (_) {}
    await Storage.remove(prefsKey);
  }
}

/// Synchronous archive extraction, run in a background isolate via
/// [Isolate.run] so the CPU-heavy bz2/tar decode never blocks the UI thread.
/// Guards against path-traversal (zip-slip). Returns the directory that
/// contains `model.onnx`.
String _extractArchiveSync(
  String archivePath,
  String targetBasePath,
  bool isGzip,
) {
  final raw = File(archivePath).readAsBytesSync();
  final List<int> tarBytes =
      isGzip ? GZipDecoder().decodeBytes(raw) : BZip2Decoder().decodeBytes(raw);
  final archive = TarDecoder().decodeBytes(tarBytes);

  String? modelDir;
  for (final entry in archive) {
    final outPath = p.normalize(p.join(targetBasePath, entry.name));
    if (!p.isWithin(targetBasePath, outPath)) continue;

    if (entry.isFile) {
      final f = File(outPath);
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(entry.content as List<int>);
      if (p.basename(outPath) == 'model.onnx') {
        modelDir = f.parent.path;
      }
    } else {
      Directory(outPath).createSync(recursive: true);
    }
  }

  if (modelDir == null) {
    throw StateError('Model archive did not contain model.onnx');
  }
  return modelDir;
}
