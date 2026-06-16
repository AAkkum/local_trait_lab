class Prediction {
  const Prediction({
    required this.label,
    required this.confidence,
    required this.scores,
  });

  final String label;
  final double confidence;
  final Map<String, double> scores;

  Map<String, Object?> toJson() => <String, Object?>{
        'label': label,
        'confidence': confidence,
        'scores': scores,
      };
}

enum AnalysisFailureType {
  modelNotLoaded,
  unsupportedTask,
  invalidInput,
  unsupportedLabelOutput,
  invalidStructuredOutput,
  invalidDataset,
  runtimeUnavailable,
  cancelled,
  unknown,
}

class AnalysisFailure implements Exception {
  const AnalysisFailure({
    required this.type,
    required this.message,
    this.details = const <String, Object?>{},
  });

  final AnalysisFailureType type;
  final String message;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type.name,
        'message': message,
        'details': details,
      };
}

class ResultMetadata {
  const ResultMetadata({
    required this.inputFile,
    required this.latencyMs,
    required this.timestamp,
    required this.modelVersion,
    required this.preprocessing,
    required this.labelMappingApplied,
    required this.scoreNormalizationMethod,
    required this.runtimeBackend,
    required this.rawOutputRetained,
    this.debug = const <String, Object?>{},
  });

  final String inputFile;
  final int latencyMs;
  final DateTime timestamp;
  final String modelVersion;
  final Map<String, Object?> preprocessing;
  final Map<String, String> labelMappingApplied;
  final String scoreNormalizationMethod;
  final String runtimeBackend;
  final bool rawOutputRetained;
  final Map<String, Object?> debug;

  Map<String, Object?> toJson() => <String, Object?>{
        'input_file': inputFile,
        'latency_ms': latencyMs,
        'timestamp': timestamp.toIso8601String(),
        'model_version': modelVersion,
        'preprocessing': preprocessing,
        'label_mapping_applied': labelMappingApplied,
        'score_normalization_method': scoreNormalizationMethod,
        'runtime_backend': runtimeBackend,
        'raw_output_retained': rawOutputRetained,
        'debug': debug,
      };
}

class AnalysisResult {
  const AnalysisResult({
    required this.task,
    required this.modelId,
    required this.metadata,
    this.prediction,
    this.rawOutput,
    this.failure,
  });

  final String task;
  final String modelId;
  final Prediction? prediction;
  final Object? rawOutput;
  final ResultMetadata metadata;
  final AnalysisFailure? failure;

  bool get succeeded => failure == null && prediction != null;

  Map<String, Object?> toJson() => <String, Object?>{
        'task': task,
        'model_id': modelId,
        'prediction': prediction?.toJson(),
        'raw_output': rawOutput,
        'metadata': metadata.toJson(),
        'failure': failure?.toJson(),
      };
}
