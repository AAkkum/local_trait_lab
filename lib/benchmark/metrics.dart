import '../core/types/emotion_label.dart';
import '../core/utils/math_utils.dart';

class BenchmarkPredictionRow {
  const BenchmarkPredictionRow({
    required this.file,
    required this.groundTruth,
    this.predictedLabel,
    this.confidence,
    this.latencyMs = 0,
    this.modelId = '',
    this.succeeded = false,
    this.failureReason,
    this.scores = const <String, double>{},
  });

  final String file;
  final String groundTruth;
  final String? predictedLabel;
  final double? confidence;
  final int latencyMs;
  final String modelId;
  final bool succeeded;
  final String? failureReason;
  final Map<String, double> scores;
}

class ClassMetrics {
  const ClassMetrics({
    required this.precision,
    required this.recall,
    required this.f1,
  });

  final double precision;
  final double recall;
  final double f1;

  Map<String, Object?> toJson() => <String, Object?>{
        'precision': precision,
        'recall': recall,
        'f1': f1,
      };
}

class BenchmarkMetrics {
  const BenchmarkMetrics({
    required this.accuracy,
    required this.macroF1,
    required this.averageLatencyMs,
    required this.medianLatencyMs,
    required this.evaluatedExamples,
    required this.failedExamples,
    required this.confusionMatrix,
    required this.perClass,
  });

  final double accuracy;
  final double macroF1;
  final double averageLatencyMs;
  final double medianLatencyMs;
  final int evaluatedExamples;
  final int failedExamples;
  final Map<String, Map<String, int>> confusionMatrix;
  final Map<String, ClassMetrics> perClass;

  Map<String, Object?> toJson() => <String, Object?>{
        'accuracy': accuracy,
        'macro_f1': macroF1,
        'average_latency_ms': averageLatencyMs,
        'median_latency_ms': medianLatencyMs,
        'evaluated_examples': evaluatedExamples,
        'failed_examples': failedExamples,
        'confusion_matrix': confusionMatrix,
        'per_class': perClass.map((String key, ClassMetrics value) =>
            MapEntry<String, Object?>(key, value.toJson())),
      };
}

BenchmarkMetrics computeBenchmarkMetrics(List<BenchmarkPredictionRow> rows) {
  final List<BenchmarkPredictionRow> successful = rows
      .where((BenchmarkPredictionRow row) =>
          row.succeeded && row.predictedLabel != null)
      .toList();
  final List<int> latencies = successful
      .map((BenchmarkPredictionRow row) => row.latencyMs)
      .toList()
    ..sort();
  final int failed = rows.length - successful.length;

  final Map<String, Map<String, int>> confusion = <String, Map<String, int>>{
    for (final String actual in kEmotionLabels)
      actual: <String, int>{
        for (final String predicted in kEmotionLabels) predicted: 0
      }
  };

  int correct = 0;
  for (final BenchmarkPredictionRow row in successful) {
    confusion[row.groundTruth]![row.predictedLabel!] =
        confusion[row.groundTruth]![row.predictedLabel!]! + 1;
    if (row.groundTruth == row.predictedLabel) {
      correct++;
    }
  }

  final Map<String, ClassMetrics> perClass = <String, ClassMetrics>{};
  double macroF1 = 0.0;
  for (final String label in kEmotionLabels) {
    final int tp = confusion[label]![label]!;
    final int fp =
        kEmotionLabels.where((String other) => other != label).fold<int>(
              0,
              (int sum, String other) => sum + confusion[other]![label]!,
            );
    final int fn =
        kEmotionLabels.where((String other) => other != label).fold<int>(
              0,
              (int sum, String other) => sum + confusion[label]![other]!,
            );

    final double precision = tp + fp == 0 ? 0.0 : tp / (tp + fp);
    final double recall = tp + fn == 0 ? 0.0 : tp / (tp + fn);
    final double f1 = precision + recall == 0
        ? 0.0
        : (2 * precision * recall) / (precision + recall);
    perClass[label] = ClassMetrics(
      precision: roundTo(precision, 6),
      recall: roundTo(recall, 6),
      f1: roundTo(f1, 6),
    );
    macroF1 += f1;
  }

  final double accuracy =
      successful.isEmpty ? 0.0 : correct / successful.length;
  final double averageLatency = latencies.isEmpty
      ? 0.0
      : latencies.reduce((int a, int b) => a + b) / latencies.length;
  final double medianLatency = latencies.isEmpty
      ? 0.0
      : latencies.length.isOdd
          ? latencies[latencies.length ~/ 2].toDouble()
          : (latencies[(latencies.length ~/ 2) - 1] +
                  latencies[latencies.length ~/ 2]) /
              2.0;

  return BenchmarkMetrics(
    accuracy: roundTo(accuracy, 6),
    macroF1: roundTo(macroF1 / kEmotionLabels.length, 6),
    averageLatencyMs: roundTo(averageLatency, 3),
    medianLatencyMs: roundTo(medianLatency, 3),
    evaluatedExamples: successful.length,
    failedExamples: failed,
    confusionMatrix: confusion,
    perClass: perClass,
  );
}
