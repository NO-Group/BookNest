package com.nogroup.booknest

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

/** Home-screen widget: the gems wallet balance. */
class GemsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val gems = prefs.getString("widget_gems", "0")
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.widget_gems)
            views.setTextViewText(R.id.gems_count, "💎 $gems")
            views.setOnClickPendingIntent(R.id.gems_root, deepLink(context, "booknest://wallet"))
            manager.updateAppWidget(id, views)
        }
    }
}
