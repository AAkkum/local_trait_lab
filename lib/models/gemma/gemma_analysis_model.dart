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
  Map<String, PromptTemplate> _taskPromptTemplates =
      const <String, PromptTemplate>{};
  bool _isLoaded = false;

  @override
  String get id => _config?.variantId ?? 'gemma';

  @override
  String get displayName => _config?.variantId ?? 'Gemma';

  @override
  String get family => 'gemma';

  @override
  Set<String> get supportedTasks => <String>{
        'emotion_classification',
        'privacy_inference',
        'privacy_profile_synthesis',
        'privacy_profile_repair',
      };

  @override
  bool get isLoaded => _isLoaded;

  @override
  bool get benchmarkEligible => true;

  @override
  Future<void> load(ModelConfig config) async {
    _config = config;
    _taskPromptTemplates = await _loadTaskPromptTemplates(config);
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
    final PromptTemplate? overrideTemplate =
        _taskPromptTemplates[request.taskId];
    final String prompt = _promptBuilder.buildPrompt(
      taskSpec: request.taskSpec,
      asset: asset,
      overrideTemplate: overrideTemplate,
    );

    final GemmaRuntimeOutput runtimeOutput = await runtime.runTask(
      taskSpec: request.taskSpec,
      asset: asset,
      prompt: prompt,
    );

    try {
      if (request.taskId == 'emotion_classification') {
        return _buildEmotionResult(
          request: request,
          config: config,
          asset: asset,
          runtimeOutput: runtimeOutput,
        );
      }
      if (request.taskId == 'privacy_profile_synthesis' ||
          request.taskId == 'privacy_profile_repair') {
        return _buildPrivacyProfileSynthesisResult(
          request: request,
          config: config,
          asset: asset,
          runtimeOutput: runtimeOutput,
        );
      }
      return _buildPrivacyResult(
        request: request,
        config: config,
        asset: asset,
        runtimeOutput: runtimeOutput,
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

  AnalysisResult _buildEmotionResult({
    required AnalysisRequest request,
    required ModelConfig config,
    required InputAsset asset,
    required GemmaRuntimeOutput runtimeOutput,
  }) {
    final ParsedGemmaOutput parsed =
        _outputParser.parseEmotion(runtimeOutput.rawText);
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
      metadata: _metadata(
        asset: asset,
        config: config,
        runtimeOutput: runtimeOutput,
        preprocessing: <String, Object?>{'input_type': asset.type.name},
        scoreNormalizationMethod: 'as_returned_json',
        labelMappingApplied: <String, String>{
          for (final String label in kEmotionLabels) label: label,
        },
      ),
    );
  }

  AnalysisResult _buildPrivacyResult({
    required AnalysisRequest request,
    required ModelConfig config,
    required InputAsset asset,
    required GemmaRuntimeOutput runtimeOutput,
  }) {
    late final Map<String, dynamic> decoded;
    try {
      decoded = _outputParser.parseJsonObject(runtimeOutput.rawText);
    } on AnalysisFailure {
      decoded = _privacyTextFallback(runtimeOutput.rawText);
    }
    String sensitivity = _safeString(decoded['sensitivity'], 'unknown');
    if (!request.taskSpec.outputSchema.allowedLabels.contains(sensitivity)) {
      sensitivity = 'unknown';
      decoded['sensitivity'] = sensitivity;
    }
    final double confidence = switch (sensitivity) {
      'high' => 0.75,
      'medium' => 0.5,
      'low' => 0.25,
      _ => 0.0,
    };
    return AnalysisResult(
      task: request.taskId,
      modelId: config.variantId,
      prediction: Prediction(
        label: sensitivity,
        confidence: roundTo(confidence, 6),
        scores: const <String, double>{},
      ),
      rawOutput: decoded,
      metadata: _metadata(
        asset: asset,
        config: config,
        runtimeOutput: runtimeOutput,
        preprocessing: <String, Object?>{
          'input_type': asset.type.name,
          'privacy_task': 'local_file_preview',
        },
        scoreNormalizationMethod: 'not_applicable',
        labelMappingApplied: const <String, String>{},
      ),
    );
  }

  Map<String, dynamic> _privacyTextFallback(String rawText) {
    final String compact = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    final String excerpt =
        compact.length <= 500 ? compact : '${compact.substring(0, 497)}...';
    return <String, dynamic>{
      'content_summary': excerpt.isEmpty
          ? 'Gemma returned no readable privacy inference.'
          : excerpt,
      'evidence': const <String>[],
      'owner_inferences': const <String>[],
      'private_signals': const <String>[],
      'profiling_uses': const <String>[],
      'cross_file_value': '',
      'sensitivity': 'unknown',
      'participant_headline': 'No reliable inference available',
      'participant_message':
          'The model response could not be structured reliably, so no personal inference is shown.',
      'parser_fallback': true,
      'raw_model_output': rawText,
    };
  }

  Map<String, dynamic> _profileTextFallback(String rawText) {
    return <String, dynamic>{
      'headline': 'Combined profile unavailable',
      'profile':
          'The model response could not be structured reliably, so the app cannot show a combined personal profile.',
      'key_inferences': const <String>[],
      'privacy_implication': '',
      'evidence_summary': const <String>[],
      'uncertainty_note':
          'Unstructured model output retained for research review.',
      'parser_fallback': true,
      'raw_model_output': rawText,
    };
  }

  AnalysisResult _buildPrivacyProfileSynthesisResult({
    required AnalysisRequest request,
    required ModelConfig config,
    required InputAsset asset,
    required GemmaRuntimeOutput runtimeOutput,
  }) {
    late final Map<String, dynamic> decoded;
    try {
      decoded = _outputParser.parseJsonObject(runtimeOutput.rawText);
    } on AnalysisFailure {
      decoded = _profileTextFallback(runtimeOutput.rawText);
    }
    return AnalysisResult(
      task: request.taskId,
      modelId: config.variantId,
      prediction: const Prediction(
        label: 'profile',
        confidence: 1.0,
        scores: <String, double>{},
      ),
      rawOutput: decoded,
      metadata: _metadata(
        asset: asset,
        config: config,
        runtimeOutput: runtimeOutput,
        preprocessing: <String, Object?>{
          'input_type': asset.type.name,
          'privacy_task': 'profile_synthesis',
          'input_text_length': asset.text?.length ?? 0,
        },
        scoreNormalizationMethod: 'not_applicable',
        labelMappingApplied: const <String, String>{},
      ),
    );
  }

  ResultMetadata _metadata({
    required InputAsset asset,
    required ModelConfig config,
    required GemmaRuntimeOutput runtimeOutput,
    required Map<String, Object?> preprocessing,
    required Map<String, String> labelMappingApplied,
    required String scoreNormalizationMethod,
  }) {
    return ResultMetadata(
      inputFile: asset.displayName,
      latencyMs: runtimeOutput.latencyMs,
      timestamp: DateTime.now(),
      modelVersion: config.version,
      preprocessing: preprocessing,
      labelMappingApplied: labelMappingApplied,
      scoreNormalizationMethod: scoreNormalizationMethod,
      runtimeBackend: runtimeOutput.runtimeBackend,
      rawOutputRetained: true,
      debug: runtimeOutput.debug,
    );
  }

  String _safeString(Object? value, String fallback) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  @override
  Future<void> unload() async {
    await _runtime?.close();
    _runtime = null;
    _config = null;
    _taskPromptTemplates = const <String, PromptTemplate>{};
    _isLoaded = false;
  }

  Future<Map<String, PromptTemplate>> _loadTaskPromptTemplates(
      ModelConfig config) async {
    final String emotionAssetPath =
        (config.assetConfig['task_config'] as String?) ??
            'assets/gemma_tasks/emotion_classification.json';
    final Map<String, String> assetPaths = <String, String>{
      'emotion_classification': emotionAssetPath,
      'privacy_inference': 'assets/gemma_tasks/privacy_inference.json',
      'privacy_profile_synthesis':
          'assets/gemma_tasks/privacy_profile_synthesis.json',
      'privacy_profile_repair':
          'assets/gemma_tasks/privacy_profile_repair.json',
    };
    final Map<String, PromptTemplate> templates = <String, PromptTemplate>{};
    for (final MapEntry<String, String> entry in assetPaths.entries) {
      templates[entry.key] = await _loadPromptTemplate(entry.value);
    }
    return templates;
  }

  Future<PromptTemplate> _loadPromptTemplate(String assetPath) async {
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
