package com.kraken.hub.kraken_hub

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import java.io.File

class KrakenRecordingService : Service() {

    companion object {
        const val ACTION_START = "ACTION_START"
        const val ACTION_PAUSE = "ACTION_PAUSE"
        const val ACTION_RESUME = "ACTION_RESUME"
        const val ACTION_STOP = "ACTION_STOP"
        
        const val EXTRA_FILE_PATH = "EXTRA_FILE_PATH"

        var amplitudeListener: ((Double) -> Unit)? = null
        var isRecordingActive = false
    }

    private var mediaRecorder: MediaRecorder? = null
    private var isPaused = false
    private val CHANNEL_ID = "KrakenRecordingChannel"
    
    private val handler = Handler(Looper.getMainLooper())
    private var amplitudeRunnable: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val filePath = intent.getStringExtra(EXTRA_FILE_PATH)
                if (filePath != null) {
                    startRecording(filePath)
                }
            }
            ACTION_PAUSE -> pauseRecording()
            ACTION_RESUME -> resumeRecording()
            ACTION_STOP -> stopRecording()
        }
        return START_NOT_STICKY
    }

    private fun startRecording(filePath: String) {
        if (mediaRecorder != null) {
            stopRecording()
        }

        mediaRecorder = MediaRecorder().apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioChannels(1) // Mono
            setAudioSamplingRate(16000) // 16 kHz
            setAudioEncodingBitRate(64000) // 64 kbps
            setOutputFile(filePath)
            prepare()
            start()
        }
        isRecordingActive = true
        isPaused = false

        startForeground(1, createNotification("Recording..."))
        startAmplitudePolling()
    }

    private fun pauseRecording() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && mediaRecorder != null && !isPaused) {
            mediaRecorder?.pause()
            isPaused = true
            updateNotification("Recording Paused")
            stopAmplitudePolling()
        }
    }

    private fun resumeRecording() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && mediaRecorder != null && isPaused) {
            mediaRecorder?.resume()
            isPaused = false
            updateNotification("Recording...")
            startAmplitudePolling()
        }
    }

    private fun stopRecording() {
        try {
            mediaRecorder?.stop()
            mediaRecorder?.release()
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            mediaRecorder = null
            isRecordingActive = false
            isPaused = false
            stopAmplitudePolling()
            stopForeground(true)
            stopSelf()
        }
    }

    private fun startAmplitudePolling() {
        amplitudeRunnable = object : Runnable {
            override fun run() {
                if (isRecordingActive && !isPaused) {
                    try {
                        val amplitude = mediaRecorder?.maxAmplitude ?: 0
                        // In a real app we might convert to dBFS: 20 * log10(amplitude / 32767.0)
                        amplitudeListener?.invoke(amplitude.toDouble())
                    } catch (e: Exception) {
                        e.printStackTrace()
                    } finally {
                        handler.postDelayed(this, 33) // ~30Hz
                    }
                }
            }
        }
        handler.post(amplitudeRunnable!!)
    }

    private fun stopAmplitudePolling() {
        amplitudeRunnable?.let { handler.removeCallbacks(it) }
    }

    private fun createNotification(contentText: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Kraken Hub")
            .setContentText(contentText)
            .setSmallIcon(R.drawable.ic_notification_kraken)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(contentText: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(1, createNotification(contentText))
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Kraken Recording",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopRecording()
        super.onDestroy()
    }
}
