package com.nogroup.booknest

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Receives BookNest's push messages (data-only, high priority) and shows
 * them as notifications while the app is not on screen. In the foreground
 * the in-app watcher already shows banners, so nothing is posted twice.
 * Messages of one conversation replace each other (same tag).
 */
class BookNestMessagingService : FirebaseMessagingService() {
    companion object {
        const val EXTRA_ROUTE = "booknest_route"
        private const val CHANNEL_ID = "chat" // same channel as in-app banners
    }

    override fun onNewToken(token: String) {
        // The app registers the current token with the server on every start.
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (MainActivity.inForeground) return
        val data = message.data
        val title = data["title"] ?: message.notification?.title ?: "BookNest"
        val body = data["body"] ?: message.notification?.body ?: ""
        val route = data["route"]
        val tag = data["tag"] ?: route ?: "booknest"
        try {
            ensureChannel()
            val open = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                if (route != null) putExtra(EXTRA_ROUTE, route)
            }
            val pending = PendingIntent.getActivity(
                this, tag.hashCode(), open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setColor(0xFF00E5FF.toInt())
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setAutoCancel(true)
                .setContentIntent(pending)
                .build()
            NotificationManagerCompat.from(this).notify(tag, 1, notification)
        } catch (e: SecurityException) {
            // Notifications not allowed by the user — nothing to show.
        } catch (e: Throwable) {
            // Never crash on a malformed message.
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Messages", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Messages from readers and clubs"
            },
        )
    }
}
