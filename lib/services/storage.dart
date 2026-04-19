import 'package:shared_preferences/shared_preferences.dart';

class Storage {
  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get prefs async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<String?> getString(String key) async {
    final p = await prefs;
    return p.getString(key);
  }

  static Future<void> setString(String key, String value) async {
    final p = await prefs;
    await p.setString(key, value);
  }

  static Future<void> remove(String key) async {
    final p = await prefs;
    await p.remove(key);
  }
}

// Storage keys
class StorageKeys {
  static const downloadedChapters = 'downloaded_chapters';
  static const widgetPendingAction = 'widget_pending_action';
  static const narratorVoice = 'pref_narrator_voice';
  static const dialogueVoice = 'pref_dialogue_voice';
  static const playbackSpeed = 'pref_playback_speed';
  static const lastPlayingState = 'last_playing_state';
}
