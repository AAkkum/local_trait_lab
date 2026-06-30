package com.atabey.local_trait_lab

import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class MainActivity : FlutterActivity() {
    private var gemmaEngine: Engine? = null
    private var gemmaConversation: Conversation? = null
    private var loadedModelPath: String? = null
    private var loadedTopK: Int = 1
    private var loadedTopP: Double = 0.95
    private var loadedTemperature: Double = 0.0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GEMMA_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> handleGemmaLoad(call, result)
                "runImagePrompt" -> handleGemmaRunImagePrompt(call, result)
                "unload" -> handleGemmaUnload(result)
                else -> result.notImplemented()
            }
        }
    }

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

    companion object {
        private const val TAG = "LocalTraitGemma"
        private const val GEMMA_CHANNEL = "local_trait_lab/gemma_litert"
    }
}
