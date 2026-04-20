package com.audiobook.audiobook_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.KeyEvent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Home-screen widget that mirrors current playback state and forwards
 * transport controls to audio_service via the same MediaButton receiver
 * that handles the notification shade.
 *
 *  - Play/Pause → KEYCODE_MEDIA_PLAY_PAUSE
 *  - Next       → KEYCODE_MEDIA_NEXT
 *  - Previous   → KEYCODE_MEDIA_PREVIOUS
 *  - Body tap   → brings the app to the foreground
 *
 * State keys are written by AudiobookHomeWidget.updateState() on the Dart
 * side; we read them via HomeWidgetPlugin.getData().
 */
class AudiobookWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { id ->
            appWidgetManager.updateAppWidget(id, buildViews(context))
        }
    }

    private fun buildViews(context: Context): RemoteViews {
        val prefs = HomeWidgetPlugin.getData(context)
        val novel = prefs.getString("widget_novel_title", "") ?: ""
        val chapter = prefs.getString("widget_chapter_title", "") ?: ""
        val paragraph = prefs.getString("widget_paragraph_text", "") ?: ""
        val isPlaying = prefs.getBoolean("widget_is_playing", false)
        val speed = readDouble(prefs, "widget_speed", 1.0)

        val views = RemoteViews(context.packageName, R.layout.widget_layout)

        views.setTextViewText(
            R.id.widget_chapter,
            if (chapter.isNotEmpty()) chapter else "Tap to open Audiobook"
        )
        views.setTextViewText(
            R.id.widget_paragraph,
            when {
                paragraph.isNotEmpty() -> paragraph
                novel.isNotEmpty() -> novel
                else -> "No audiobook playing"
            }
        )
        views.setImageViewResource(
            R.id.widget_play_pause,
            if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
        )
        views.setTextViewText(R.id.widget_speed, formatSpeed(speed))

        // Tap the body → bring the app forward (no URI → no go_router 404).
        views.setOnClickPendingIntent(R.id.widget_root, launchAppIntent(context))

        // Transport controls → MediaButton broadcasts handled by audio_service.
        views.setOnClickPendingIntent(
            R.id.widget_play_pause,
            mediaKeyIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
        )
        views.setOnClickPendingIntent(
            R.id.widget_next,
            mediaKeyIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT)
        )
        views.setOnClickPendingIntent(
            R.id.widget_prev,
            mediaKeyIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS)
        )

        return views
    }

    private fun launchAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    /**
     * Build a PendingIntent that fires a MEDIA_BUTTON broadcast targeted at
     * audio_service's MediaButtonReceiver. This reuses the exact path the
     * lock-screen / notification controls use, so the widget inherits
     * audio_service's play/pause/next/prev semantics for free.
     */
    private fun mediaKeyIntent(context: Context, keyCode: Int): PendingIntent {
        val receiver = ComponentName(
            context.packageName,
            "com.ryanheise.audioservice.MediaButtonReceiver"
        )
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = receiver
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        // Unique requestCode per key so PendingIntents don't collide.
        return PendingIntent.getBroadcast(
            context,
            keyCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    /**
     * home_widget serializes Dart doubles as raw IEEE-754 bits packed into
     * a Long. Fall through to Float / String in case the plugin version
     * changes its serialization format.
     */
    private fun readDouble(
        prefs: SharedPreferences,
        key: String,
        default: Double
    ): Double {
        if (!prefs.contains(key)) return default
        return try {
            java.lang.Double.longBitsToDouble(prefs.getLong(key, 0L))
        } catch (_: ClassCastException) {
            try {
                prefs.getFloat(key, default.toFloat()).toDouble()
            } catch (_: ClassCastException) {
                prefs.getString(key, null)?.toDoubleOrNull() ?: default
            }
        }
    }

    private fun formatSpeed(speed: Double): String {
        val rounded = Math.round(speed * 100) / 100.0
        return if (rounded == rounded.toLong().toDouble()) {
            "${rounded.toLong()}.0×"
        } else {
            "${rounded}×"
        }
    }
}
