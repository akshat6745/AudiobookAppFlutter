package com.audiobook.audiobook_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Glance-card widget that mirrors the current playback state. The widget
 * is a single tap target: tapping anywhere launches the app. All transport
 * controls live in the in-app mini-player and the notification shade.
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
            R.id.widget_state_icon,
            if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
        )
        views.setTextViewText(R.id.widget_speed, formatSpeed(speed))
        views.setOnClickPendingIntent(R.id.widget_root, launchAppIntent(context))
        return views
    }

    private fun launchAppIntent(context: Context): PendingIntent {
        // Plain launch intent (no ACTION_VIEW / data URI) — we only want to
        // bring the app to the foreground at its current location. A deep
        // link here would be handed to go_router and 404 since the widget
        // host path isn't a declared route.
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
