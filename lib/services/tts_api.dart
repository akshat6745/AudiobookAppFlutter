import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_client.dart';

class TtsApi {
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
