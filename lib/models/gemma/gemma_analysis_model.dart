import 'dart:convert';

import 'package:flutter/services.dart';

import '../../analysis/analysis_model.dart';
import '../../analysis/analysis_request.dart';
import '../../analysis/analysis_result.dart';
import '../../analysis/model_config.dart';
import '../../analysis/task_spec.dart';
import '../../core/types/emotion_label.dart';
import '../../core/utils/math_utils.dart';
import 'gemma_litert_runtime.dart';
import 'gemma_mock_runtime.dart';
import 'gemma_output_parser.dart';
import 'gemma_prompt_builder.dart';
import 'gemma_runtime.dart';

class GemmaAnalysisModel implements AnalysisModel {
  GemmaAnalysisModel({
    GemmaPromptBuilder? promptBuilder,
    GemmaOutputParser? outputParser,
  })  : _promptBuilder = promptBuilder ?? const GemmaPromptBuilder(),
        _outputParser = outputParser ?? const GemmaOutputParser();

  final GemmaPromptBuilder _promptBuilder;
  final GemmaOutputParser _outputParser;
  ModelConfig? _config;
  GemmaRuntime? _runtime;
  PromptTemplate? _taskPromptTemplate;
  bool _isLoaded = false;

  @override
  String get id => _config?.variantId ?? 'gemma';

  @override
  String get displayName => _config?.variantId ?? 'Gemma';

  @override
  String get family => 'gemma';

  @override
  Set<String> get supportedTasks => <String>{'emotion_classification'};

  @override
  bool get isLoaded => _isLoaded;

  @override
  bool get benchmarkEligible => true;

  @override
  Future<void> load(ModelConfig config) async {
    _config = config;
    _taskPromptTemplate = await _loadPromptTemplate(config);
    switch (config.runtimeBackend) {
      case 'mock':
        _runtime = const GemmaMockRuntime();
      case 'litert_lm':
        _runtime = GemmaLiteRtRuntime(
          modelPath: (config.assetConfig['asset_path'] as String?) ?? '',
          variantId: config.variantId,
          maxTokens:
              (config.runtimeOptions['max_tokens'] as num?)?.toInt() ?? 384,
          temperature:
              (config.runtimeOptions['temperature'] as num?)?.toDouble() ?? 0.0,
          topK: (config.runtimeOptions['top_k'] as num?)?.toInt() ?? 1,
          topP: (config.runtimeOptions['top_p'] as num?)?.toDouble() ?? 0.95,
          textBackend:
              (config.runtimeOptions['text_backend'] as String?) ?? 'cpu',
          visionBackend:
              (config.runtimeOptions['vision_backend'] as String?) ?? 'gpu',
        );
      default:
        _runtime = null;
    }
    await _runtime?.load();
    _isLoaded = true;
  }

  @override
  Future<AnalysisResult> analyze(AnalysisRequest request) async {
    final ModelConfig? config = _config;
    if (!_isLoaded || config == null) {
      return _failureResult(
        request: request,
        failure: const AnalysisFailure(
          type: AnalysisFailureType.modelNotLoaded,
          message: 'Gemma model is not loaded.',
        ),
      );
    }
    if (!supportedTasks.contains(request.taskId) ||
        !request.taskSpec.acceptsRequest(request)) {
      return _failureResult(
        request: request,
        failure: const AnalysisFailure(
          type: AnalysisFailureType.unsupportedTask,
          message: 'Task is not supported by Gemma model.',
        ),
      );
    }
    final GemmaRuntime? runtime = _runtime;
    if (runtime == null) {
      return _failureResult(
        request: request,
        failure: AnalysisFailure(
          type: AnalysisFailureType.runtimeUnavailable,
          message:
              'Gemma local runtime ${config.runtimeBackend} is not yet connected.',
        ),
      );
    }

    final InputAsset asset = request.inputs.first;
    final String prompt = _promptBuilder.buildEmotionPrompt(
      taskSpec: request.taskSpec,
      asset: asset,
      overrideTemplate: _taskPromptTemplate,
    );

    final GemmaRuntimeOutput runtimeOutput = await runtime.runTask(
      taskSpec: request.taskSpec,
      asset: asset,
      prompt: prompt,
    );

    try {
      final ParsedGemmaOutput parsed =
          _outputParser.parse(runtimeOutput.rawText);
      final Prediction prediction = Prediction(
        label: parsed.label,
        confidence: roundTo(parsed.scores[parsed.label] ?? 0.0, 6),
        scores: parsed.scores,
      );
      return AnalysisResult(
        task: request.taskId,
        modelId: config.variantId,
        prediction: prediction,
        rawOutput: runtimeOutput.rawText,
        metadata: ResultMetadata(
          inputFile: asset.displayName,
          latencyMs: runtimeOutput.latencyMs,
          timestamp: DateTime.now(),
          modelVersion: config.version,
          preprocessing: <String, Object?>{'input_type': asset.type.name},
          labelMappingApplied: <String, String>{
            for (final String label in kEmotionLabels) label: label
          },
          scoreNormalizationMethod: 'as_returned_json',
          runtimeBackend: runtimeOutput.runtimeBackend,
          rawOutputRetained: true,
          debug: runtimeOutput.debug,
        ),
      );
    } on AnalysisFailure catch (failure) {
      return _failureResult(
        request: request,
        rawOutput: runtimeOutput.rawText,
        failure: failure,
        latencyMs: runtimeOutput.latencyMs,
      );
    }
  }

  @override
  Future<void> unload() async {
    await _runtime?.close();
    _runtime = null;
    _config = null;
    _taskPromptTemplate = null;
    _isLoaded = false;
  }

  Future<PromptTemplate?> _loadPromptTemplate(ModelConfig config) async {
    final String? assetPath = config.assetConfig['task_config'] as String?;
    if (assetPath == null || assetPath.trim().isEmpty) return null;
    final String rawConfig = await rootBundle.loadString(assetPath);
    final Map<String, Object?> decoded =
        jsonDecode(rawConfig) as Map<String, Object?>;
    final String? systemInstructions =
        decoded['system_instructions'] as String?;
    final String? userTemplate = decoded['user_template'] as String?;
    if (systemInstructions == null || userTemplate == null) {
      throw AnalysisFailure(
        type: AnalysisFailureType.invalidStructuredOutput,
        message: 'Gemma task config $assetPath is missing prompt fields.',
      );
    }
    return PromptTemplate(
      systemInstructions: systemInstructions,
      userTemplate: userTemplate,
    );
  }

  AnalysisResult _failureResult({
    required AnalysisRequest request,
    required AnalysisFailure failure,
    Object? rawOutput,
    int latencyMs = 0,
  }) {
    return AnalysisResult(
      task: request.taskId,
      modelId: _config?.variantId ?? 'gemma',
      rawOutput: rawOutput,
      failure: failure,
      metadata: ResultMetadata(
        inputFile:
            request.inputs.isNotEmpty ? request.inputs.first.displayName : '',
        latencyMs: latencyMs,
        timestamp: DateTime.now(),
        modelVersion: _config?.version ?? 'unknown',
        preprocessing: const <String, Object?>{},
        labelMappingApplied: const <String, String>{},
        scoreNormalizationMethod: 'none',
        runtimeBackend: _config?.runtimeBackend ?? 'unknown',
        rawOutputRetained: rawOutput != null,
      ),
    );
  }
}
