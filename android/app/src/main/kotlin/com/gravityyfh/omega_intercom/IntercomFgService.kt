package com.gravityyfh.omega_intercom

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class IntercomFgService : Service() {
    companion object {
        const val CHANNEL_ID = "omega_intercom_fg"
        const val NOTIF_ID = 2001
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"

        fun ensureChannel(ctx: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val mgr = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val existing = mgr.getNotificationChannel(CHANNEL_ID)
                if (existing == null) {
                    val ch = NotificationChannel(CHANNEL_ID, "Intercom en cours", NotificationManager.IMPORTANCE_LOW)
                    ch.setShowBadge(false)
                    mgr.createNotificationChannel(ch)
                }
            }
        }

        fun buildNotification(ctx: Context, title: String, body: String): Notification {
            ensureChannel(ctx)
            return NotificationCompat.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(ctx.applicationInfo.icon)
                .setContentTitle(title)
                .setContentText(body)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .build()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Intercom actif"
        val body = intent?.getStringExtra(EXTRA_BODY) ?: "En cours"
        val notif = buildNotification(this, title, body)
        startForeground(NOTIF_ID, notif)
        return START_STICKY
    }
}

