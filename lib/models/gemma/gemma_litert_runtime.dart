import 'dart:io';

import 'package:flutter/services.dart';

import '../../analysis/analysis_result.dart';
import '../../analysis/task_spec.dart';
import 'gemma_runtime.dart';

class GemmaLiteRtRuntime implements GemmaRuntime {
  GemmaLiteRtRuntime({
    required this.modelPath,
    required this.variantId,
    this.maxTokens = 384,
    this.temperature = 0.0,
    this.topK = 1,
    this.topP = 0.95,
    this.textBackend = 'cpu',
    this.visionBackend = 'gpu',
  });

  static const MethodChannel _channel =
      MethodChannel('local_trait_lab/gemma_litert');

  final String modelPath;
  final String variantId;
  final int maxTokens;
  final double temperature;
  final int topK;
  final double topP;
  final String textBackend;
  final String visionBackend;
  bool _loaded = false;

  @override
  Future<void> load() async {
    if (_loaded) return;
    if (modelPath.trim().isEmpty) {
      throw const AnalysisFailure(
        type: AnalysisFailureType.runtimeUnavailable,
        message:
            'No Gemma model file path configured. Import a LiteRT-LM model file in Advanced settings.',
      );
    }
    final File modelFile = File(modelPath);
    if (!await modelFile.exists()) {
      throw AnalysisFailure(
        type: AnalysisFailureType.runtimeUnavailable,
        message: 'Configured Gemma model file does not exist: $modelPath',
      );
    }
    final int modelSize = await modelFile.length();
    if (modelSize < 1024 * 1024 * 1024) {
      throw AnalysisFailure(
        type: AnalysisFailureType.runtimeUnavailable,
        message:
            'Configured Gemma model is only ${(modelSize / (1024 * 1024)).toStringAsFixed(1)} MB. Re-import the real gemma-4-E2B-it.litertlm file.',
      );
    }

    await _channel.invokeMethod<void>('load', <String, Object?>{
      'modelPath': modelPath,
      'variantId': variantId,
      'maxTokens': maxTokens,
      'temperature': temperature,
      'topK': topK,
      'topP': topP,
      'textBackend': textBackend,
      'visionBackend': visionBackend,
    });
    _loaded = true;
  }

  @override
  Future<GemmaRuntimeOutput> runTask({
    required AnalysisTaskSpec taskSpec,
    required InputAsset asset,
    required String prompt,
  }) async {
    await load();
    final List<int>? bytes = asset.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const AnalysisFailure(
        type: AnalysisFailureType.invalidInput,
        message: 'Gemma image input has no loaded bytes.',
      );
    }

    final Object? response = await _channel
        .invokeMethod<Object?>('runImagePrompt', <String, Object?>{
      'prompt': prompt,
      'imageBytes': Uint8List.fromList(bytes),
      'inputFile': asset.displayName,
    });
    final Map<Object?, Object?> map = response as Map<Object?, Object?>;
    return GemmaRuntimeOutput(
      rawText: (map['rawText'] as String?) ?? '',
      latencyMs: (map['latencyMs'] as num?)?.toInt() ?? 0,
      runtimeBackend: 'litert_lm',
      debug: <String, Object?>{
        'variant_id': variantId,
        'model_path': modelPath,
        'text_backend': textBackend,
        'vision_backend': visionBackend,
        'max_tokens': maxTokens,
        'temperature': temperature,
        'top_k': topK,
        'top_p': topP,
        'task_id': taskSpec.id,
      },
    );
  }

  @override
  Future<void> close() async {
    if (!_loaded) return;
    await _channel.invokeMethod<void>('unload');
    _loaded = false;
  }
}
