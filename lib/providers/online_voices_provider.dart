import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/online_voice.dart';
import '../services/tts_api.dart';

/// Online (edge-tts) voice catalog, fetched from the backend's `/tts-voices`
/// endpoint. The backend itself caches this for 24h, and Riverpod caches the
/// resolved list for the life of the app — call `ref.invalidate` if a manual
/// refresh is ever needed (not expected; the catalog barely changes).
final onlineVoicesProvider = FutureProvider<List<OnlineVoice>>((ref) {
  return ttsApi.listVoices();
});
