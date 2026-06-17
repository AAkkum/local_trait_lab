import '../../analysis/analysis_model.dart';
import '../../analysis/analysis_request.dart';
import '../../analysis/analysis_result.dart';
import '../../analysis/label_mapping.dart';
import '../../analysis/model_config.dart';
import '../../analysis/task_spec.dart';
import '../../core/utils/math_utils.dart';
import 'emotieff_label_mapper.dart';
import 'emotieff_mock_runtime.dart';
import 'emotieff_onnx_runtime.dart';
import 'emotieff_runtime.dart';

class EmotiEffEmotionModel implements AnalysisModel {
  ModelConfig? _config;
  EmotiEffRuntime? _runtime;
  bool _isLoaded = false;

  @override
  String get id => _config?.variantId ?? 'emotieff';

  @override
  String get displayName => _config?.variantId ?? 'EmotiEff';

  @override
  String get family => 'emotieff';

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
        _runtime = const EmotiEffMockRuntime();
      case 'onnx':
        _runtime = EmotiEffOnnxRuntime(
          modelPath: (config.assetConfig['asset_path'] as String?) ?? '',
          variantId: config.variantId,
        );
      default:
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
          message: 'EmotiEff model is not loaded.',
        ),
      );
    }
    if (!supportedTasks.contains(request.taskId) || !request.taskSpec.acceptsRequest(request)) {
      return _failureResult(
        request: request,
        failure: const AnalysisFailure(
          type: AnalysisFailureType.unsupportedTask,
          message: 'Task is not supported by EmotiEff model.',
        ),
      );
    }
    final EmotiEffRuntime? runtime = _runtime;
    if (runtime == null) {
      return _failureResult(
        request: request,
        failure: AnalysisFailure(
          type: AnalysisFailureType.runtimeUnavailable,
          message: 'EmotiEff local runtime ${config.runtimeBackend} is not yet connected.',
        ),
      );
    }

    final InputAsset asset = request.inputs.first;
    try {
      final EmotiEffRuntimeOutput runtimeOutput = await runtime.classifyEmotion(asset: asset);
      final LabelMappingResult mapped = mapScoresToStandardLabels(
        rawScores: runtimeOutput.rawScores,
        backendToStandard: kEmotiEffBackendToStandard,
        logits: true,
      );
      final String predictedLabel = mapped.scores.entries.reduce(
        (MapEntry<String, double> a, MapEntry<String, double> b) => a.value >= b.value ? a : b,
      ).key;

      return AnalysisResult(
        task: request.taskId,
        modelId: config.variantId,
        prediction: Prediction(
          label: predictedLabel,
          confidence: roundTo(mapped.scores[predictedLabel]!, 6),
          scores: mapped.scores,
        ),
        rawOutput: runtimeOutput.rawScores,
        metadata: ResultMetadata(
          inputFile: asset.displayName,
          latencyMs: runtimeOutput.latencyMs,
          timestamp: DateTime.now(),
          modelVersion: config.version,
          preprocessing: <String, Object?>{'input_type': asset.type.name},
          labelMappingApplied: mapped.mappingApplied,
          scoreNormalizationMethod: 'softmax',
          runtimeBackend: runtimeOutput.runtimeBackend,
          rawOutputRetained: true,
          debug: runtimeOutput.debug,
        ),
      );
    } on AnalysisFailure catch (failure) {
      return _failureResult(request: request, failure: failure);
    } catch (error) {
      return _failureResult(
        request: request,
        failure: AnalysisFailure(
          type: AnalysisFailureType.unknown,
          message: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> unload() async {
    await _runtime?.close();
    _runtime = null;
    _config = null;
    _isLoaded = false;
  }

  AnalysisResult _failureResult({
    required AnalysisRequest request,
    required AnalysisFailure failure,
  }) {
    return AnalysisResult(
      task: request.taskId,
      modelId: _config?.variantId ?? 'emotieff',
      failure: failure,
      metadata: ResultMetadata(
        inputFile: request.inputs.isNotEmpty ? request.inputs.first.displayName : '',
        latencyMs: 0,
        timestamp: DateTime.now(),
        modelVersion: _config?.version ?? 'unknown',
        preprocessing: const <String, Object?>{},
        labelMappingApplied: const <String, String>{},
        scoreNormalizationMethod: 'none',
        runtimeBackend: _config?.runtimeBackend ?? 'unknown',
        rawOutputRetained: false,
      ),
    );
  }
}
