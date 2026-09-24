package org.krak_en.voice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat
import java.io.File

class KrakenRecordingService : Service() {

    companion object {
        const val ACTION_START = "ACTION_START"
        const val ACTION_PAUSE = "ACTION_PAUSE"
        const val ACTION_RESUME = "ACTION_RESUME"
        const val ACTION_STOP = "ACTION_STOP"
        const val ACTION_NOTIFICATION_STOP = "ACTION_NOTIFICATION_STOP"
        const val ACTION_NOTIFICATION_PAUSE = "ACTION_NOTIFICATION_PAUSE"
        
        const val EXTRA_FILE_PATH = "EXTRA_FILE_PATH"
        const val EXTRA_DEVICE_ID = "EXTRA_DEVICE_ID"

        var amplitudeListener: ((Double) -> Unit)? = null
        var isRecordingActive = false

        // Callback for notification-triggered actions back to Flutter
        var onNotificationStop: (() -> Unit)? = null
        var onNotificationPause: (() -> Unit)? = null
    }

    private var mediaRecorder: MediaRecorder? = null
    private var isPaused = false
    private val CHANNEL_ID = "KrakenRecordingChannel"
    private val NOTIFICATION_ID = 1
    
    private val handler = Handler(Looper.getMainLooper())
    private var amplitudeRunnable: Runnable? = null

    // Elapsed time tracking for notification
    private var recordingStartTimeMs: Long = 0L
    private var pausedDurationMs: Long = 0L
    private var pauseStartTimeMs: Long = 0L
    private var notificationUpdateRunnable: Runnable? = null

    // Phone call detection
    private var telephonyManager: TelephonyManager? = null
    private var telephonyCallback: Any? = null // TelephonyCallback on API 31+
    private var wasRecordingBeforeCall = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val filePath = intent.getStringExtra(EXTRA_FILE_PATH)
                val deviceId = if (intent.hasExtra(EXTRA_DEVICE_ID)) {
                    intent.getIntExtra(EXTRA_DEVICE_ID, -1).takeIf { it >= 0 }
                } else null
                if (filePath != null) {
                    startRecording(filePath, deviceId)
                }
            }
            ACTION_PAUSE -> pauseRecording()
            ACTION_RESUME -> resumeRecording()
            ACTION_STOP -> stopRecording()
            ACTION_NOTIFICATION_STOP -> {
                onNotificationStop?.invoke()
                stopRecording()
            }
            ACTION_NOTIFICATION_PAUSE -> {
                if (isPaused) {
                    onNotificationPause?.invoke()
                    resumeRecording()
                } else {
                    onNotificationPause?.invoke()
                    pauseRecording()
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun startRecording(filePath: String, preferredDeviceId: Int? = null) {
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

            // Apply preferred audio input device if specified (API 28+)
            if (preferredDeviceId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
                val target = devices.firstOrNull { it.id == preferredDeviceId }
                if (target != null) {
                    setPreferredDevice(target)
                    android.util.Log.i("KrakenRecording", "Using preferred device: ${target.productName} (id=$preferredDeviceId)")
                }
            }

            prepare()
            start()
        }
        isRecordingActive = true
        isPaused = false
        recordingStartTimeMs = System.currentTimeMillis()
        pausedDurationMs = 0L

        startForeground(NOTIFICATION_ID, createNotification("Recording…", java.time.Duration.ZERO))
        startAmplitudePolling()
        startNotificationUpdater()
        registerPhoneCallListener()
    }

    private fun pauseRecording() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && mediaRecorder != null && !isPaused) {
            mediaRecorder?.pause()
            isPaused = true
            pauseStartTimeMs = System.currentTimeMillis()
            updateNotificationWithElapsed()
            stopAmplitudePolling()
        }
    }

    private fun resumeRecording() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && mediaRecorder != null && isPaused) {
            mediaRecorder?.resume()
            pausedDurationMs += System.currentTimeMillis() - pauseStartTimeMs
            isPaused = false
            updateNotificationWithElapsed()
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
            stopNotificationUpdater()
            unregisterPhoneCallListener()
            stopForeground(true)
            stopSelf()
        }
    }

    // --- Elapsed time & notification ---

    private fun getElapsedSeconds(): Long {
        if (recordingStartTimeMs == 0L) return 0
        val now = System.currentTimeMillis()
        val totalMs = now - recordingStartTimeMs - pausedDurationMs -
            (if (isPaused) (now - pauseStartTimeMs) else 0L)
        return (totalMs / 1000).coerceAtLeast(0)
    }

    private fun formatElapsed(totalSeconds: Long): String {
        val h = totalSeconds / 3600
        val m = (totalSeconds % 3600) / 60
        val s = totalSeconds % 60
        return if (h > 0) {
            String.format("%02d:%02d:%02d", h, m, s)
        } else {
            String.format("%02d:%02d", m, s)
        }
    }

    private fun startNotificationUpdater() {
        notificationUpdateRunnable = object : Runnable {
            override fun run() {
                if (isRecordingActive) {
                    updateNotificationWithElapsed()
                    handler.postDelayed(this, 1000)
                }
            }
        }
        handler.post(notificationUpdateRunnable!!)
    }

    private fun stopNotificationUpdater() {
        notificationUpdateRunnable?.let { handler.removeCallbacks(it) }
    }

    private fun updateNotificationWithElapsed() {
        val elapsed = getElapsedSeconds()
        val elapsedStr = formatElapsed(elapsed)
        val statusText = if (isPaused) "Paused — $elapsedStr" else "Recording — $elapsedStr"
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, createNotification(statusText, java.time.Duration.ofSeconds(elapsed)))
    }

    private fun createNotification(contentText: String, elapsed: java.time.Duration): Notification {
        // Tap notification → open app
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentPendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // Stop action
        val stopIntent = Intent(this, KrakenRecordingService::class.java).apply {
            action = ACTION_NOTIFICATION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // Pause/Resume action
        val pauseIntent = Intent(this, KrakenRecordingService::class.java).apply {
            action = ACTION_NOTIFICATION_PAUSE
        }
        val pausePendingIntent = PendingIntent.getService(
            this, 2, pauseIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val pauseLabel = if (isPaused) "Resume" else "Pause"
        val pauseIcon = if (isPaused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Kraken — Recording")
            .setContentText(contentText)
            .setSmallIcon(R.drawable.ic_notification_kraken)
            .setContentIntent(contentPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setUsesChronometer(!isPaused)
            .setWhen(if (!isPaused) System.currentTimeMillis() - (elapsed.toMillis()) else System.currentTimeMillis())
            .addAction(pauseIcon, pauseLabel, pausePendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPendingIntent)
            .build()
    }

    // --- Phone call detection (H1-53) ---

    private fun registerPhoneCallListener() {
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // API 31+ uses TelephonyCallback — requires READ_PHONE_STATE at runtime
            try {
                val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) {
                        handleCallState(state)
                    }
                }
                telephonyCallback = callback
                telephonyManager?.registerTelephonyCallback(mainExecutor, callback)
            } catch (e: SecurityException) {
                // READ_PHONE_STATE not granted — phone call auto-pause won't work,
                // but recording should proceed normally.
                android.util.Log.w("KrakenRecording", "Phone call listener skipped: ${e.message}")
            }
        }
        // For older APIs, best-effort via AudioManager focus changes (omitted for brevity)
    }

    private fun unregisterPhoneCallListener() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && telephonyCallback != null) {
            telephonyManager?.unregisterTelephonyCallback(telephonyCallback as TelephonyCallback)
            telephonyCallback = null
        }
    }

    private fun handleCallState(state: Int) {
        when (state) {
            TelephonyManager.CALL_STATE_RINGING,
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                // Phone call started — auto-pause
                if (isRecordingActive && !isPaused) {
                    wasRecordingBeforeCall = true
                    pauseRecording()
                    // Notify Flutter so Dart-side timer freezes
                    onNotificationPause?.invoke()
                }
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                // Call ended — auto-resume if we paused for the call
                if (isRecordingActive && isPaused && wasRecordingBeforeCall) {
                    wasRecordingBeforeCall = false
                    resumeRecording()
                    // Notify Flutter so Dart-side timer resumes
                    onNotificationPause?.invoke()
                }
            }
        }
    }

    // --- Amplitude polling ---

    private fun startAmplitudePolling() {
        amplitudeRunnable = object : Runnable {
            override fun run() {
                if (isRecordingActive && !isPaused) {
                    try {
                        val amplitude = mediaRecorder?.maxAmplitude ?: 0
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
