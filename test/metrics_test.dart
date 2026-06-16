import 'package:emotion_benchmark_app/benchmark/metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('computes accuracy and macro f1 on simple predictions', () {
    final BenchmarkMetrics metrics = computeBenchmarkMetrics(<BenchmarkPredictionRow>[
      const BenchmarkPredictionRow(file: 'a', groundTruth: 'happy', predictedLabel: 'happy', latencyMs: 10, modelId: 'm', succeeded: true),
      const BenchmarkPredictionRow(file: 'b', groundTruth: 'sad', predictedLabel: 'happy', latencyMs: 20, modelId: 'm', succeeded: true),
      const BenchmarkPredictionRow(file: 'c', groundTruth: 'neutral', succeeded: false, failureReason: 'failed'),
    ]);

    expect(metrics.accuracy, 0.5);
    expect(metrics.evaluatedExamples, 2);
    expect(metrics.failedExamples, 1);
    expect(metrics.confusionMatrix['happy']!['happy'], 1);
  });
}
