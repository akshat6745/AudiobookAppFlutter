import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Dart-side bridge for the Android home widget.
///
/// The widget is a one-way glance surface: Dart pushes playback state via
/// [updateState] and the native provider redraws. Tapping the widget
/// launches the app. There are no per-button controls on the widget — the
/// in-app mini-player and the notification shade already cover that.
class AudiobookHomeWidget {
  static const _providerName = 'AudiobookWidgetProvider';

  static Timer? _debounce;
  static int? _lastHash;

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Push current playback state to the widget. Debounced 300ms,
  /// hash-deduped so identical payloads don't redraw.
  static Future<void> updateState({
    required String novelTitle,
    required String chapterTitle,
    required String paragraphText,
    required bool isPlaying,
    required double speed,
  }) async {
    if (!_android) return;
    final hash = Object.hash(
        novelTitle, chapterTitle, paragraphText, isPlaying, speed);
    if (hash == _lastHash) return;
    _lastHash = hash;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        await HomeWidget.saveWidgetData('widget_novel_title', novelTitle);
        await HomeWidget.saveWidgetData('widget_chapter_title', chapterTitle);
        await HomeWidget.saveWidgetData('widget_paragraph_text', paragraphText);
        await HomeWidget.saveWidgetData('widget_is_playing', isPlaying);
        await HomeWidget.saveWidgetData('widget_speed', speed);
        await HomeWidget.updateWidget(androidName: _providerName);
      } catch (_) {
        // Widget not installed, or plugin not ready — ignore.
      }
    });
  }
}
