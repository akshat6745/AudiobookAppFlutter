package com.audiobook.audiobook_app

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin

class ParagraphWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        Factory(applicationContext)

    private class Factory(private val ctx: Context) : RemoteViewsFactory {
        private var text = ""

        override fun onDataSetChanged() {
            val prefs = HomeWidgetPlugin.getData(ctx)
            val p = prefs.getString("widget_paragraph_text", "") ?: ""
            val n = prefs.getString("widget_novel_title", "") ?: ""
            text = if (p.isNotEmpty()) p else if (n.isNotEmpty()) n else "No audiobook playing"
        }

        override fun getCount() = 1
        override fun getViewAt(position: Int): RemoteViews {
            val v = RemoteViews(ctx.packageName, R.layout.widget_paragraph_item)
            v.setTextViewText(R.id.widget_paragraph_text, text)
            return v
        }
        override fun getLoadingView(): RemoteViews? = null
        override fun getViewTypeCount() = 1
        override fun getItemId(position: Int) = 0L
        override fun hasStableIds() = true
        override fun onCreate() {}
        override fun onDestroy() {}
    }
}
