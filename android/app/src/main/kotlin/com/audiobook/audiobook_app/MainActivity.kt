package com.audiobook.audiobook_app

import com.ryanheise.audioservice.AudioServiceActivity

// Must extend AudioServiceActivity (not FlutterFragmentActivity) so audio_service's
// plugin method channel lands on the same cached FlutterEngine the plugin owns.
class MainActivity : AudioServiceActivity()
