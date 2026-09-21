package com.nogroup.booknest

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

/** Home-screen widget: the book you are reading right now, with live
 *  progress. Tap anywhere to resume exactly where you stopped. */
class ReadingWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val title = prefs.getString("widget_reading_title", "Pick a book")
        val sub = prefs.getString("widget_reading_sub", "Your shelf is waiting")
        val percent = prefs.getInt("widget_reading_percent", 0)
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.widget_reading)
            views.setTextViewText(R.id.reading_title, title)
            views.setTextViewText(R.id.reading_sub, sub)
            views.setProgressBar(R.id.reading_bar, 100, percent.coerceIn(0, 100), false)
            views.setTextViewText(R.id.reading_percent, "$percent%")
            views.setOnClickPendingIntent(R.id.reading_root, deepLink(context, "booknest://resume"))
            manager.updateAppWidget(id, views)
        }
    }
}
