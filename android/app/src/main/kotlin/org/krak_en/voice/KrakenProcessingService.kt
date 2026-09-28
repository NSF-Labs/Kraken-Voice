package org.krak_en.voice

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.*
import androidx.core.app.NotificationCompat

/** Keeps user-requested local file processing alive when the UI is backgrounded. */
class KrakenProcessingService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    override fun onBind(intent: Intent?) = null
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(
            "kraken_processing", "Transcription and summaries", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, "kraken_processing")
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("Krak-EN Voice is processing")
            .setContentText("Transcription and AI summaries continue in the background.")
            .setContentIntent(open).setOngoing(true).setSilent(true).build()
        // Local file processing is an explicitly supported dataSync use case.
        startForeground(3, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "kraken:processing").apply {
                acquire(6 * 60 * 60 * 1000L)
            }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) = START_NOT_STICKY
    override fun onTimeout(startId: Int, fgsType: Int) {
        // Persisted requests are recovered on next launch; never overrun Android's deadline.
        stopSelf()
    }
    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }
}
