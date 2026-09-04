package com.nogroup.booknest

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

/** Home-screen widget: the Word of the Day from the bundled edition. */
class WordOfDayWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val word = prefs.getString("widget_word", "serendipity")
        val definition = prefs.getString("widget_word_def", "Tap to open Word Nest")
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.widget_word_of_day)
            views.setTextViewText(R.id.wotd_word, word)
            views.setTextViewText(R.id.wotd_def, definition)
            views.setOnClickPendingIntent(R.id.wotd_root, deepLink(context, "booknest://word"))
            manager.updateAppWidget(id, views)
        }
    }
}

internal fun deepLink(context: Context, uri: String): PendingIntent =
    PendingIntent.getActivity(
        context,
        uri.hashCode(),
        Intent(Intent.ACTION_VIEW, Uri.parse(uri)).setPackage(context.packageName),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
