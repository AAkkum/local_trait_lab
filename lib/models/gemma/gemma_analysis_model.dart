import '../../analysis/analysis_model.dart';
import '../../analysis/analysis_request.dart';
import '../../analysis/analysis_result.dart';
import '../../analysis/model_config.dart';
import '../../analysis/task_spec.dart';
import '../../core/types/emotion_label.dart';
import '../../core/utils/math_utils.dart';
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
    switch (config.runtimeBackend) {
      case 'mock':
        _runtime = const GemmaMockRuntime();
      default:
        // TODO(atabey): Connect real Gemma runtime here for LiteRT / AI Edge integration.
        _runtime = null;
    }
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
    if (!supportedTasks.contains(request.taskId) || !request.taskSpec.acceptsRequest(request)) {
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
          message: 'Gemma runtime backend ${config.runtimeBackend} is not yet connected.',
        ),
      );
    }

    final InputAsset asset = request.inputs.first;
    final String prompt = _promptBuilder.buildEmotionPrompt(
      taskSpec: request.taskSpec,
      asset: asset,
    );

    final GemmaRuntimeOutput runtimeOutput = await runtime.runTask(
      taskSpec: request.taskSpec,
      asset: asset,
      prompt: prompt,
    );

    try {
      final ParsedGemmaOutput parsed = _outputParser.parse(runtimeOutput.rawText);
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
          labelMappingApplied: <String, String>{for (final String label in kEmotionLabels) label: label},
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
    _runtime = null;
    _config = null;
    _isLoaded = false;
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
        inputFile: request.inputs.isNotEmpty ? request.inputs.first.displayName : '',
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
