import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/online_voice.dart';
import 'api_client.dart';

class TtsApi {
  /// English-locale edge-tts voices the backend can generate with online.
  /// Backend-cached (see `/tts-voices`), so this is cheap to call often.
  Future<List<OnlineVoice>> listVoices() async {
    final res = await apiClient.get('/tts-voices');
    final data = res.data as Map<String, dynamic>;
    final voices = data['voices'] as List<dynamic>? ?? const [];
    return voices
        .map((e) => OnlineVoice.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Convert a single paragraph to an MP3 (dual voice).
  Future<Uint8List> convertDualVoice({
    required String text,
    required String paragraphVoice,
    required String dialogueVoice,
  }) async {
    final res = await apiClient.post<List<int>>(
      '/tts-dual-voice',
      data: {
        'text': text,
        'paragraphVoice': paragraphVoice,
        'dialogueVoice': dialogueVoice,
      },
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const []);
  }
}

final ttsApi = TtsApi();
