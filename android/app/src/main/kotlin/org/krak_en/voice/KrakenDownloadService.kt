package org.krak_en.voice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Foreground service that downloads AI models **natively** on a background
 * thread, completely independent of Flutter's Dart engine lifecycle.
 *
 * When the user switches to another app, Flutter's Dart isolate may be paused,
 * but this service keeps running because it's a foreground service with its own
 * coroutine scope. The download continues at full speed.
 *
 * Progress is reported back to Flutter via a static callback that the
 * MainActivity wires to a MethodChannel.
 */
class KrakenDownloadService : Service() {

    companion object {
        const val ACTION_START = "ACTION_START_DOWNLOAD"
        const val ACTION_START_NATIVE_DOWNLOAD = "ACTION_START_NATIVE_DOWNLOAD"
        const val ACTION_STOP = "ACTION_STOP_DOWNLOAD"
        const val ACTION_UPDATE_PROGRESS = "ACTION_UPDATE_PROGRESS"
        const val EXTRA_PROGRESS_TEXT = "EXTRA_PROGRESS_TEXT"
        const val EXTRA_DOWNLOAD_URL = "EXTRA_DOWNLOAD_URL"
        const val EXTRA_OUTPUT_PATH = "EXTRA_OUTPUT_PATH"

        private const val CHANNEL_ID = "KrakenDownloadChannel"
        private const val NOTIFICATION_ID = 2  // Different from recording service (1)
        private const val TAG = "KrakenDownload"

        private const val MAX_RETRIES = 10
        private const val PART_SUFFIX = ".part"
        private const val CONNECT_TIMEOUT_MS = 30_000
        private const val READ_TIMEOUT_MS = 60_000

        /**
         * Static callback for sending progress updates back to Flutter.
         * Wired by MainActivity when the MethodChannel is set up.
         */
        var onProgress: ((Double, String) -> Unit)? = null

        /**
         * Static callback for notifying Flutter when the download completes.
         */
        var onComplete: (() -> Unit)? = null

        /**
         * Static callback for notifying Flutter when the download fails.
         */
        var onError: ((String) -> Unit)? = null

        /**
         * Whether a native download is currently in progress.
         */
        @Volatile
        var isDownloading = false
            private set
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var downloadJob: Job? = null
    private val serviceScope = CoroutineScope(Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val notification = createNotification("Preparing download…")
                startForeground(NOTIFICATION_ID, notification)
                acquireWakeLock()
            }
            ACTION_START_NATIVE_DOWNLOAD -> {
                val url = intent.getStringExtra(EXTRA_DOWNLOAD_URL) ?: return START_NOT_STICKY
                val outputPath = intent.getStringExtra(EXTRA_OUTPUT_PATH) ?: return START_NOT_STICKY

                val notification = createNotification("Downloading AI model…")
                startForeground(NOTIFICATION_ID, notification)
                acquireWakeLock()
                startNativeDownload(url, outputPath)
            }
            ACTION_UPDATE_PROGRESS -> {
                val text = intent.getStringExtra(EXTRA_PROGRESS_TEXT) ?: "Downloading…"
                updateNotification(text)
            }
            ACTION_STOP -> {
                downloadJob?.cancel()
                isDownloading = false
                releaseWakeLock()
                stopForeground(true)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    /**
     * Performs the HTTP download on a native coroutine, completely independent
     * of the Flutter engine. Supports resume via HTTP Range headers.
     */
    private fun startNativeDownload(url: String, outputPath: String) {
        if (isDownloading) {
            Log.w(TAG, "Download already in progress, ignoring duplicate request.")
            return
        }

        isDownloading = true
        val partPath = "$outputPath$PART_SUFFIX"

        downloadJob = serviceScope.launch {
            var attempt = 0
            while (attempt <= MAX_RETRIES) {
                try {
                    val partFile = File(partPath)
                    val existingBytes = if (partFile.exists()) partFile.length() else 0L

                    if (existingBytes > 0) {
                        Log.i(TAG, "Resuming from ${existingBytes / 1024 / 1024} MB (attempt ${attempt + 1})")
                    }

                    // Resolve the final URL by following redirects manually
                    // (Hugging Face redirects to a CDN with signed URLs)
                    val finalUrl = resolveRedirects(url)

                    val conn = (URL(finalUrl).openConnection() as HttpURLConnection).apply {
                        connectTimeout = CONNECT_TIMEOUT_MS
                        readTimeout = READ_TIMEOUT_MS
                        requestMethod = "GET"
                        if (existingBytes > 0) {
                            setRequestProperty("Range", "bytes=$existingBytes-")
                        }
                    }

                    val responseCode = conn.responseCode
                    if (responseCode != 200 && responseCode != 206) {
                        conn.disconnect()
                        throw IOException("HTTP $responseCode from server")
                    }

                    val contentLength = conn.contentLengthLong
                    val totalSize = if (responseCode == 206) {
                        // Parse total from Content-Range: bytes start-end/total
                        val range = conn.getHeaderField("Content-Range")
                        range?.substringAfter("/")?.toLongOrNull() ?: (existingBytes + contentLength)
                    } else {
                        contentLength
                    }

                    val inputStream = conn.inputStream
                    val outputStream = FileOutputStream(partFile, existingBytes > 0 && responseCode == 206)

                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    var totalReceived = existingBytes
                    var lastProgressUpdate = 0L

                    try {
                        while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                            outputStream.write(buffer, 0, bytesRead)
                            totalReceived += bytesRead

                            // Throttle progress updates to every 500ms
                            val now = System.currentTimeMillis()
                            if (now - lastProgressUpdate > 500) {
                                lastProgressUpdate = now
                                val progress = if (totalSize > 0) totalReceived.toDouble() / totalSize else 0.0
                                val sizeStr = "${totalReceived / 1024 / 1024} MB / ${totalSize / 1024 / 1024} MB"

                                withContext(Dispatchers.Main) {
                                    onProgress?.invoke(progress, sizeStr)
                                    updateNotification("Gemma: $sizeStr")
                                }
                            }
                        }
                    } finally {
                        outputStream.flush()
                        outputStream.close()
                        inputStream.close()
                        conn.disconnect()
                    }

                    // Download complete — rename .part → final
                    val finalFile = File(outputPath)
                    if (finalFile.exists()) finalFile.delete()
                    partFile.renameTo(finalFile)

                    Log.i(TAG, "Download complete: $outputPath (${totalReceived / 1024 / 1024} MB)")
                    isDownloading = false

                    withContext(Dispatchers.Main) {
                        onComplete?.invoke()
                        updateNotification("Download complete")
                    }
                    return@launch // Success — exit retry loop

                } catch (e: Exception) {
                    attempt++
                    Log.w(TAG, "Download error (attempt $attempt/$MAX_RETRIES): ${e.message}")

                    if (attempt <= MAX_RETRIES) {
                        // Exponential backoff: 3s, 6s, 9s, 12s, ...
                        val delayMs = 3000L * attempt
                        Log.i(TAG, "Retrying in ${delayMs / 1000}s...")
                        withContext(Dispatchers.Main) {
                            updateNotification("Connection lost, retrying in ${delayMs / 1000}s…")
                        }
                        kotlinx.coroutines.delay(delayMs)
                    } else {
                        // Out of retries
                        isDownloading = false
                        val errorMsg = "Download failed after $MAX_RETRIES retries: ${e.message}"
                        Log.e(TAG, errorMsg)

                        // Clean up partial file on final failure
                        try { File(partPath).delete() } catch (_: Exception) {}

                        withContext(Dispatchers.Main) {
                            onError?.invoke(errorMsg)
                            updateNotification("Download failed")
                        }
                        return@launch
                    }
                }
            }
        }
    }

    /**
     * Follows HTTP redirects manually to get the final download URL.
     * HuggingFace uses 302 redirects to CDN servers with signed URLs.
     */
    private fun resolveRedirects(urlStr: String): String {
        var currentUrl = urlStr
        var redirects = 0
        while (redirects < 5) {
            val conn = (URL(currentUrl).openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                connectTimeout = CONNECT_TIMEOUT_MS
                requestMethod = "GET"
            }
            val code = conn.responseCode
            if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
                currentUrl = conn.getHeaderField("Location") ?: break
                conn.disconnect()
                redirects++
            } else {
                conn.disconnect()
                return currentUrl
            }
        }
        return currentUrl
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "KrakenVoice:ModelDownload"
            ).apply {
                acquire(3 * 60 * 60 * 1000L) // 3-hour safety timeout
            }
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    private fun createNotification(contentText: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentPendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Krak-EN Voice")
            .setContentText(contentText)
            .setSmallIcon(R.drawable.ic_notification_kraken)
            .setContentIntent(contentPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(0, 0, true)
            .build()
    }

    fun updateNotification(text: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, createNotification(text))
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Model Downloads",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows progress while downloading AI models"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        downloadJob?.cancel()
        isDownloading = false
        releaseWakeLock()
        super.onDestroy()
    }
}
