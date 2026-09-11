package com.atabey.local_trait_lab

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class GemmaDownloadService : Service() {
    private val executor = Executors.newSingleThreadExecutor()
    private val isRunning = AtomicBoolean(false)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val url = intent?.getStringExtra(EXTRA_URL).orEmpty()
        val fileName = intent?.getStringExtra(EXTRA_FILE_NAME) ?: DEFAULT_FILE_NAME
        if (url.isBlank()) {
            updateState("failed", reason = "No download URL configured.")
            stopSelf(startId)
            return START_NOT_STICKY
        }

        startDownloadForeground("Preparing Gemma download")
        if (isRunning.compareAndSet(false, true)) {
            executor.execute {
                try {
                    downloadModel(url, fileName)
                } finally {
                    isRunning.set(false)
                    stopSelf(startId)
                }
            }
        }
        return START_STICKY
    }

    private fun downloadModel(url: String, fileName: String) {
        val targetDirectory = File(getExternalFilesDir(null) ?: filesDir, "models")
        if (!targetDirectory.exists()) targetDirectory.mkdirs()
        val targetFile = File(targetDirectory, fileName)
        val partialFile = File(targetDirectory, "$fileName.part")
        if (targetFile.exists()) targetFile.delete()

        var downloadedBytes = if (partialFile.exists()) partialFile.length() else 0L
        updateState(
            state = "running",
            targetPath = targetFile.absolutePath,
            downloadedBytes = downloadedBytes,
            totalBytes = -1L,
            reason = null,
        )

        var connection: HttpURLConnection? = null
        try {
            connection = openConnection(url, downloadedBytes)
            val responseCode = connection.responseCode
            if (responseCode == 416) {
                partialFile.delete()
                downloadedBytes = 0L
                connection.disconnect()
                connection = openConnection(url, 0L)
            } else if (downloadedBytes > 0L && responseCode == HttpURLConnection.HTTP_OK) {
                partialFile.delete()
                downloadedBytes = 0L
            }

            val activeConnection = connection
            val activeResponseCode = activeConnection.responseCode
            if (activeResponseCode !in 200..299) {
                throw IllegalStateException("Download server returned HTTP $activeResponseCode.")
            }

            val contentLength = activeConnection.contentLengthLong
            val totalBytes = if (contentLength > 0L) downloadedBytes + contentLength else -1L
            activeConnection.inputStream.use { input ->
                FileOutputStream(partialFile, downloadedBytes > 0L).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var lastNotificationBytes = downloadedBytes
                    while (true) {
                        val read = input.read(buffer)
                        if (read == -1) break
                        output.write(buffer, 0, read)
                        downloadedBytes += read.toLong()
                        if (downloadedBytes - lastNotificationBytes >= NOTIFY_STEP_BYTES) {
                            lastNotificationBytes = downloadedBytes
                            updateState(
                                state = "running",
                                targetPath = targetFile.absolutePath,
                                downloadedBytes = downloadedBytes,
                                totalBytes = totalBytes,
                            )
                            updateDownloadNotification(downloadedBytes, totalBytes)
                        }
                    }
                }
            }

            if (targetFile.exists()) targetFile.delete()
            if (!partialFile.renameTo(targetFile)) {
                throw IllegalStateException("Could not finalize downloaded model file.")
            }
            updateState(
                state = "complete",
                targetPath = targetFile.absolutePath,
                downloadedBytes = targetFile.length(),
                totalBytes = targetFile.length(),
            )
            updateCompleteNotification()
        } catch (error: Throwable) {
            updateState(
                state = "failed",
                targetPath = targetFile.absolutePath,
                downloadedBytes = if (partialFile.exists()) partialFile.length() else downloadedBytes,
                totalBytes = -1L,
                reason = error.message ?: error.toString(),
            )
            updateFailedNotification(error.message ?: "Download failed")
        } finally {
            connection?.disconnect()
        }
    }

    private fun openConnection(url: String, resumeFrom: Long): HttpURLConnection {
        var currentUrl = URL(url)
        repeat(MAX_REDIRECTS) {
            val connection = (currentUrl.openConnection() as HttpURLConnection).apply {
                connectTimeout = 30_000
                readTimeout = 30_000
                instanceFollowRedirects = false
                requestMethod = "GET"
                setRequestProperty("User-Agent", "LocalTraitLab/1.0 Android")
                if (resumeFrom > 0L) setRequestProperty("Range", "bytes=$resumeFrom-")
            }
            val responseCode = connection.responseCode
            if (responseCode in 300..399) {
                val location = connection.getHeaderField("Location")
                connection.disconnect()
                if (location.isNullOrBlank()) {
                    throw IllegalStateException("Download redirect did not include a target location.")
                }
                currentUrl = URL(currentUrl, location)
            } else {
                return connection
            }
        }
        throw IllegalStateException("Download redirected too many times.")
    }

    private fun updateState(
        state: String,
        targetPath: String? = null,
        downloadedBytes: Long = -1L,
        totalBytes: Long = -1L,
        reason: String? = null,
    ) {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_STATE, state)
            .putLong(KEY_DOWNLOADED_BYTES, downloadedBytes)
            .putLong(KEY_TOTAL_BYTES, totalBytes)
        if (targetPath != null) prefs.putString(KEY_PATH, targetPath)
        if (reason == null) prefs.remove(KEY_REASON) else prefs.putString(KEY_REASON, reason)
        prefs.apply()
    }

    private fun startDownloadForeground(text: String) {
        createNotificationChannel()
        val notification = notificationBuilder(text)
            .setProgress(0, 0, true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateDownloadNotification(downloadedBytes: Long, totalBytes: Long) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val text = if (totalBytes > 0L) {
            "Downloaded ${downloadedBytes / MB} MB of ${totalBytes / MB} MB"
        } else {
            "Downloaded ${downloadedBytes / MB} MB"
        }
        val builder = notificationBuilder(text)
        if (totalBytes > 0L) {
            builder.setProgress(totalBytes.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(), downloadedBytes.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(), false)
        } else {
            builder.setProgress(0, 0, true)
        }
        manager.notify(NOTIFICATION_ID, builder.build())
    }

    private fun updateCompleteNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(
            NOTIFICATION_ID,
            notificationBuilder("Gemma model download complete")
                .setProgress(0, 0, false)
                .setOngoing(false)
                .build(),
        )
    }

    private fun updateFailedNotification(reason: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(
            NOTIFICATION_ID,
            notificationBuilder(reason)
                .setContentTitle("Gemma download failed")
                .setProgress(0, 0, false)
                .setOngoing(false)
                .build(),
        )
    }

    private fun notificationBuilder(text: String): Notification.Builder {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Downloading Gemma 4 E2B")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Model downloads",
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "com.atabey.local_trait_lab.START_GEMMA_DOWNLOAD"
        const val EXTRA_URL = "url"
        const val EXTRA_FILE_NAME = "file_name"
        const val PREFS = "gemma_download"
        const val KEY_STATE = "state"
        const val KEY_PATH = "download_path"
        const val KEY_REASON = "reason"
        const val KEY_DOWNLOADED_BYTES = "downloaded_bytes"
        const val KEY_TOTAL_BYTES = "total_bytes"
        private const val CHANNEL_ID = "gemma_model_downloads"
        private const val NOTIFICATION_ID = 4102
        private const val DEFAULT_FILE_NAME = "gemma-4-E2B-it.litertlm"
        private const val MAX_REDIRECTS = 10
        private const val MB = 1024L * 1024L
        private const val NOTIFY_STEP_BYTES = 8L * MB
    }
}
