package com.nogroup.booknest

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

/** Home-screen widget: four one-tap shortcuts into the app. */
class QuickActionsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.widget_quick_actions)
            views.setOnClickPendingIntent(R.id.qa_write, deepLink(context, "booknest://write"))
            views.setOnClickPendingIntent(R.id.qa_search, deepLink(context, "booknest://search"))
            views.setOnClickPendingIntent(R.id.qa_word, deepLink(context, "booknest://word"))
            views.setOnClickPendingIntent(R.id.qa_feed, deepLink(context, "booknest://feed"))
            manager.updateAppWidget(id, views)
        }
    }
}
