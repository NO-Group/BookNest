package com.nogroup.booknest

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

/** Home-screen widget: the reading streak counter. */
class StreakWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val streak = prefs.getString("widget_streak", "0")
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.widget_streak)
            views.setTextViewText(R.id.streak_count, "🔥 $streak")
            views.setOnClickPendingIntent(R.id.streak_root, deepLink(context, "booknest://streaks"))
            manager.updateAppWidget(id, views)
        }
    }
}
