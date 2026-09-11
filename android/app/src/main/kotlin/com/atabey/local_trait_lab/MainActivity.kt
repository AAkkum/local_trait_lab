package com.atabey.local_trait_lab

import android.Manifest
import android.content.Context
import android.content.Intent
import android.os.Build
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.SamplerConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class MainActivity : FlutterActivity() {
    private var gemmaEngine: Engine? = null
    private var gemmaConversation: Conversation? = null
    private var loadedModelPath: String? = null
    private var loadedTopK: Int = 1
    private var loadedTopP: Double = 0.95
    private var loadedTemperature: Double = 0.0
    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GEMMA_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> runOnWorker { handleGemmaLoad(call, MainThreadResult(result)) }
                "runImagePrompt" -> runOnWorker { handleGemmaRunImagePrompt(call, MainThreadResult(result)) }
                "runTextPrompt" -> runOnWorker { handleGemmaRunTextPrompt(call, MainThreadResult(result)) }
                "renderPdfFirstPage" -> runOnWorker { handleRenderPdfFirstPage(call, MainThreadResult(result)) }
                "renderPdfFirstPageFromPath" -> runOnWorker { handleRenderPdfFirstPageFromPath(call, MainThreadResult(result)) }
                "startGemmaDownload" -> runOnWorker { handleStartGemmaDownload(call, MainThreadResult(result)) }
                "getGemmaDownloadStatus" -> runOnWorker { handleGetGemmaDownloadStatus(MainThreadResult(result)) }
                "unload" -> runOnWorker { handleGemmaUnload(MainThreadResult(result)) }
                else -> result.notImplemented()
            }
        }
    }


    private fun runOnWorker(block: () -> Unit) {
        backgroundExecutor.execute(block)
    }

    private inner class MainThreadResult(private val delegate: MethodChannel.Result) : MethodChannel.Result {
        override fun success(result: Any?) {
            mainHandler.post { delegate.success(result) }
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            mainHandler.post { delegate.error(errorCode, errorMessage, errorDetails) }
        }

        override fun notImplemented() {
            mainHandler.post { delegate.notImplemented() }
        }
    }


    private fun handleStartGemmaDownload(call: MethodCall, result: MethodChannel.Result) {
        try {
            val url = call.argument<String>("url") ?: ""
            val fileName = call.argument<String>("fileName") ?: "gemma_model.litertlm"
            if (url.isBlank()) {
                result.error("GEMMA_DOWNLOAD_NO_URL", "No Gemma download URL configured.", null)
                return
            }

            val baseDirectory = getExternalFilesDir(null) ?: filesDir
            val targetDirectory = File(baseDirectory, "models")
            if (!targetDirectory.exists()) targetDirectory.mkdirs()
            val targetFile = File(targetDirectory, fileName)

            gemmaDownloadPreferences()
                .edit()
                .putString(GemmaDownloadService.KEY_STATE, "pending")
                .putString(GemmaDownloadService.KEY_PATH, targetFile.absolutePath)
                .putLong(GemmaDownloadService.KEY_DOWNLOADED_BYTES, 0L)
                .putLong(GemmaDownloadService.KEY_TOTAL_BYTES, -1L)
                .remove(GemmaDownloadService.KEY_REASON)
                .apply()

            requestNotificationPermissionIfNeeded()

            val intent = Intent(this, GemmaDownloadService::class.java).apply {
                action = GemmaDownloadService.ACTION_START
                putExtra(GemmaDownloadService.EXTRA_URL, url)
                putExtra(GemmaDownloadService.EXTRA_FILE_NAME, fileName)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }

            result.success(querySavedGemmaDownloadStatus())
        } catch (error: Throwable) {
            Log.e(TAG, "Gemma download start failed", error)
            result.error("GEMMA_DOWNLOAD_FAILED", error.message ?: error.toString(), null)
        }
    }

    private fun handleGetGemmaDownloadStatus(result: MethodChannel.Result) {
        try {
            result.success(querySavedGemmaDownloadStatus())
        } catch (error: Throwable) {
            Log.e(TAG, "Gemma download status failed", error)
            result.error("GEMMA_DOWNLOAD_STATUS_FAILED", error.message ?: error.toString(), null)
        }
    }

    private fun querySavedGemmaDownloadStatus(): Map<String, Any?> {
        val preferences = gemmaDownloadPreferences()
        val state = preferences.getString(GemmaDownloadService.KEY_STATE, null)
            ?: return mapOf("state" to "not_found")
        val targetPath = preferences.getString(GemmaDownloadService.KEY_PATH, null)
        val downloadedBytes = preferences.getLong(GemmaDownloadService.KEY_DOWNLOADED_BYTES, -1L)
        val totalBytes = preferences.getLong(GemmaDownloadService.KEY_TOTAL_BYTES, -1L)
        val progress = if (totalBytes > 0L && downloadedBytes >= 0L) {
            downloadedBytes.toDouble() / totalBytes.toDouble()
        } else {
            null
        }
        return mapOf(
            "state" to state,
            "local_path" to targetPath,
            "downloaded_bytes" to downloadedBytes,
            "total_bytes" to totalBytes,
            "progress" to progress,
            "reason" to preferences.getString(GemmaDownloadService.KEY_REASON, null),
        )
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        mainHandler.post {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return@post
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST_CODE)
        }
    }

    private fun gemmaDownloadPreferences() = getSharedPreferences(GemmaDownloadService.PREFS, Context.MODE_PRIVATE)

    private fun handleGemmaLoad(call: MethodCall, result: MethodChannel.Result) {
        try {
            val modelPath = call.argument<String>("modelPath") ?: ""
            if (modelPath.isBlank()) {
                result.error("GEMMA_NO_MODEL", "No Gemma model path configured.", null)
                return
            }
            if (gemmaEngine != null && loadedModelPath == modelPath) {
                result.success(null)
                return
            }
            closeGemma()

            val textBackend = backendFromLabel(call.argument<String>("textBackend") ?: "cpu")
            val visionBackend = backendFromLabel(call.argument<String>("visionBackend") ?: "gpu")
            val maxTokens = call.argument<Int>("maxTokens") ?: 384
            val temperature = call.argument<Double>("temperature") ?: 0.0
            val topK = call.argument<Int>("topK") ?: 1
            val topP = call.argument<Double>("topP") ?: 0.95

            val engine = createGemmaEngineWithFallbacks(
                modelPath = modelPath,
                textBackend = textBackend,
                visionBackend = visionBackend,
                maxTokens = maxTokens,
            )
            val conversation = engine.createConversation(
                ConversationConfig(
                    samplerConfig = SamplerConfig(
                        topK = topK,
                        topP = topP,
                        temperature = temperature,
                    )
                )
            )
            gemmaEngine = engine
            gemmaConversation = conversation
            loadedModelPath = modelPath
            loadedTopK = topK
            loadedTopP = topP
            loadedTemperature = temperature
            result.success(null)
        } catch (error: Throwable) {
            Log.e(TAG, "Gemma load failed", error)
            closeGemma()
            result.error("GEMMA_LOAD_FAILED", error.message ?: error.toString(), null)
        }
    }

    private fun createGemmaEngineWithFallbacks(
        modelPath: String,
        textBackend: Backend,
        visionBackend: Backend,
        maxTokens: Int,
    ): Engine {
        val attempts = listOf(
            textBackend to visionBackend,
            textBackend to Backend.CPU(),
            Backend.GPU() to Backend.CPU(),
            Backend.CPU() to Backend.CPU(),
        ).distinctBy { it.first::class.qualifiedName + ":" + it.second::class.qualifiedName }

        val failures = mutableListOf<String>()
        var lastError: Throwable? = null
        for ((candidateTextBackend, candidateVisionBackend) in attempts) {
            try {
                Log.d(TAG, "Creating Gemma engine text=$candidateTextBackend vision=$candidateVisionBackend")
                return createGemmaEngine(
                    modelPath = modelPath,
                    textBackend = candidateTextBackend,
                    visionBackend = candidateVisionBackend,
                    maxTokens = maxTokens,
                )
            } catch (error: Throwable) {
                val message = error.message ?: error.toString()
                failures.add("text=$candidateTextBackend vision=$candidateVisionBackend: $message")
                Log.w(TAG, "Gemma engine attempt failed text=$candidateTextBackend vision=$candidateVisionBackend", error)
                lastError = error
            }
        }
        throw IllegalStateException("All Gemma backend attempts failed: ${failures.joinToString(" | ")}", lastError)
    }

    private fun createGemmaEngine(
        modelPath: String,
        textBackend: Backend,
        visionBackend: Backend,
        maxTokens: Int,
    ): Engine {
        val cacheDirectory = getExternalFilesDir(null)?.absolutePath ?: cacheDir.absolutePath
        val engineConfig = EngineConfig(
            modelPath = modelPath,
            backend = textBackend,
            visionBackend = visionBackend,
            maxNumTokens = maxTokens,
            cacheDir = cacheDirectory,
        )
        val engine = Engine(engineConfig)
        engine.initialize()
        return engine
    }

    private fun handleGemmaRunImagePrompt(call: MethodCall, result: MethodChannel.Result) {
        val engine = gemmaEngine
        if (engine == null) {
            result.error("GEMMA_NOT_LOADED", "Gemma LiteRT-LM runtime is not loaded.", null)
            return
        }

        val conversation = resetGemmaConversation(engine)
        if (conversation == null) {
            result.error("GEMMA_NOT_LOADED", "Gemma LiteRT-LM runtime is not loaded.", null)
            return
        }

        try {
            val prompt = call.argument<String>("prompt") ?: ""
            val imageBytes = call.argument<ByteArray>("imageBytes")
            if (imageBytes == null || imageBytes.isEmpty()) {
                result.error("GEMMA_BAD_IMAGE", "Image bytes are empty.", null)
                return
            }
            val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            if (bitmap == null) {
                result.error("GEMMA_BAD_IMAGE", "Could not decode image bytes.", null)
                return
            }

            val output = StringBuilder()
            val errorRef = AtomicReference<String?>(null)
            val latch = CountDownLatch(1)
            val start = System.nanoTime()
            val contents = Contents.of(
                listOf(
                    Content.ImageBytes(bitmap.toPngByteArray()),
                    Content.Text(prompt),
                )
            )
            conversation.sendMessageAsync(
                contents,
                object : MessageCallback {
                    override fun onMessage(message: Message) {
                        output.append(message.toString())
                    }

                    override fun onDone() {
                        latch.countDown()
                    }

                    override fun onError(throwable: Throwable) {
                        errorRef.set(throwable.message ?: throwable.toString())
                        latch.countDown()
                    }
                },
                emptyMap(),
            )

            val completed = latch.await(180, TimeUnit.SECONDS)
            if (!completed) {
                result.error("GEMMA_TIMEOUT", "Gemma inference timed out after 180 seconds.", null)
                return
            }
            val error = errorRef.get()
            if (error != null) {
                result.error("GEMMA_INFERENCE_FAILED", error, null)
                return
            }
            val latencyMs = ((System.nanoTime() - start) / 1_000_000L).toInt()
            result.success(mapOf("rawText" to output.toString(), "latencyMs" to latencyMs))
        } catch (error: Throwable) {
            Log.e(TAG, "Gemma inference failed", error)
            result.error("GEMMA_INFERENCE_FAILED", error.message ?: error.toString(), null)
        }
    }

    private fun handleGemmaRunTextPrompt(call: MethodCall, result: MethodChannel.Result) {
        val engine = gemmaEngine
        if (engine == null) {
            result.error("GEMMA_NOT_LOADED", "Gemma LiteRT-LM runtime is not loaded.", null)
            return
        }

        val conversation = resetGemmaConversation(engine)
        if (conversation == null) {
            result.error("GEMMA_NOT_LOADED", "Gemma LiteRT-LM runtime is not loaded.", null)
            return
        }

        try {
            val prompt = call.argument<String>("prompt") ?: ""
            if (prompt.isBlank()) {
                result.error("GEMMA_BAD_PROMPT", "Text prompt is empty.", null)
                return
            }

            val output = StringBuilder()
            val errorRef = AtomicReference<String?>(null)
            val latch = CountDownLatch(1)
            val start = System.nanoTime()
            val contents = Contents.of(listOf(Content.Text(prompt)))
            conversation.sendMessageAsync(
                contents,
                object : MessageCallback {
                    override fun onMessage(message: Message) {
                        output.append(message.toString())
                    }

                    override fun onDone() {
                        latch.countDown()
                    }

                    override fun onError(throwable: Throwable) {
                        errorRef.set(throwable.message ?: throwable.toString())
                        latch.countDown()
                    }
                },
                emptyMap(),
            )

            val completed = latch.await(180, TimeUnit.SECONDS)
            if (!completed) {
                result.error("GEMMA_TIMEOUT", "Gemma text inference timed out after 180 seconds.", null)
                return
            }
            val error = errorRef.get()
            if (error != null) {
                result.error("GEMMA_INFERENCE_FAILED", error, null)
                return
            }
            val latencyMs = ((System.nanoTime() - start) / 1_000_000L).toInt()
            result.success(mapOf("rawText" to output.toString(), "latencyMs" to latencyMs))
        } catch (error: Throwable) {
            Log.e(TAG, "Gemma text inference failed", error)
            result.error("GEMMA_INFERENCE_FAILED", error.message ?: error.toString(), null)
        }
    }

    private fun resetGemmaConversation(engine: Engine): Conversation? {
        try {
            gemmaConversation?.close()
        } catch (error: Throwable) {
            Log.w(TAG, "Closing Gemma conversation before reset failed", error)
        }
        val conversation = engine.createConversation(
            ConversationConfig(
                samplerConfig = SamplerConfig(
                    topK = loadedTopK,
                    topP = loadedTopP,
                    temperature = loadedTemperature,
                )
            )
        )
        gemmaConversation = conversation
        return conversation
    }


    private fun handleRenderPdfFirstPage(call: MethodCall, result: MethodChannel.Result) {
        var pdfFile: File? = null
        try {
            val pdfBytes = call.argument<ByteArray>("pdfBytes")
            if (pdfBytes == null || pdfBytes.isEmpty()) {
                result.error("PDF_EMPTY", "PDF bytes are empty.", null)
                return
            }

            pdfFile = File.createTempFile("local_trait_pdf_", ".pdf", cacheDir)
            FileOutputStream(pdfFile).use { stream -> stream.write(pdfBytes) }
            renderPdfFirstPageFile(pdfFile, result)
        } catch (error: Throwable) {
            Log.e(TAG, "PDF render failed", error)
            result.error("PDF_RENDER_FAILED", error.message ?: error.toString(), null)
        } finally {
            pdfFile?.delete()
        }
    }

    private fun handleRenderPdfFirstPageFromPath(call: MethodCall, result: MethodChannel.Result) {
        try {
            val path = call.argument<String>("path") ?: ""
            if (path.isBlank()) {
                result.error("PDF_EMPTY_PATH", "PDF path is empty.", null)
                return
            }
            renderPdfFirstPageFile(File(path), result)
        } catch (error: Throwable) {
            Log.e(TAG, "PDF render by path failed", error)
            result.error("PDF_RENDER_FAILED", error.message ?: error.toString(), null)
        }
    }

    private fun renderPdfFirstPageFile(pdfFile: File, result: MethodChannel.Result) {
        if (!pdfFile.exists() || pdfFile.length() <= 0L) {
            result.error("PDF_NOT_FOUND", "PDF file is missing or empty.", null)
            return
        }
        ParcelFileDescriptor.open(pdfFile, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
            PdfRenderer(descriptor).use { renderer ->
                if (renderer.pageCount <= 0) {
                    result.error("PDF_NO_PAGES", "PDF has no renderable pages.", null)
                    return
                }
                renderer.openPage(0).use { page ->
                    val maxSide = 1200
                    val scale = minOf(
                        maxSide.toFloat() / page.width.toFloat(),
                        maxSide.toFloat() / page.height.toFloat(),
                        1.5f,
                    ).coerceAtLeast(1.0f)
                    val width = (page.width * scale).toInt()
                    val height = (page.height * scale).toInt()
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bitmap)
                    canvas.drawColor(Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    val pngBytes = bitmap.toPngByteArray()
                    bitmap.recycle()
                    result.success(mapOf("pngBytes" to pngBytes, "width" to width, "height" to height))
                }
            }
        }
    }

    private fun handleGemmaUnload(result: MethodChannel.Result) {
        closeGemma()
        result.success(null)
    }

    private fun closeGemma() {
        try {
            gemmaConversation?.close()
        } catch (error: Throwable) {
            Log.w(TAG, "Closing Gemma conversation failed", error)
        }
        try {
            gemmaEngine?.close()
        } catch (error: Throwable) {
            Log.w(TAG, "Closing Gemma engine failed", error)
        }
        gemmaConversation = null
        gemmaEngine = null
        loadedModelPath = null
        loadedTopK = 1
        loadedTopP = 0.95
        loadedTemperature = 0.0
    }

    private fun backendFromLabel(label: String): Backend {
        return when (label.lowercase()) {
            "gpu" -> Backend.GPU()
            "npu", "tpu" -> Backend.NPU(nativeLibraryDir = applicationInfo.nativeLibraryDir)
            else -> Backend.CPU()
        }
    }

    private fun Bitmap.toPngByteArray(): ByteArray {
        val stream = ByteArrayOutputStream()
        compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }

    override fun onDestroy() {
        backgroundExecutor.shutdownNow()
        closeGemma()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "LocalTraitGemma"
        private const val GEMMA_CHANNEL = "local_trait_lab/gemma_litert"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 4103
    }
}
