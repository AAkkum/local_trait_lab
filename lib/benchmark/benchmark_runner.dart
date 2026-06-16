import '../analysis/analysis_model.dart';
import '../analysis/analysis_request.dart';
import '../analysis/task_spec.dart';
import 'benchmark_dataset.dart';
import 'export.dart';
import 'metrics.dart';

class BenchmarkProgress {
  const BenchmarkProgress({
    required this.current,
    required this.total,
    required this.currentFile,
    required this.averageLatencyMs,
    this.isFinished = false,
  });

  final int current;
  final int total;
  final String currentFile;
  final double averageLatencyMs;
  final bool isFinished;
}

class BenchmarkRunResult {
  const BenchmarkRunResult({
    required this.dataset,
    required this.rows,
    required this.metrics,
    required this.exports,
  });

  final BenchmarkDataset dataset;
  final List<BenchmarkPredictionRow> rows;
  final BenchmarkMetrics metrics;
  final BenchmarkExportBundle exports;
}

typedef ProgressCallback = void Function(BenchmarkProgress progress);

class BenchmarkRunner {
  const BenchmarkRunner({
    BenchmarkExportService? exportService,
  }) : _exportService = exportService ?? const BenchmarkExportService();

  final BenchmarkExportService _exportService;

  Future<BenchmarkRunResult> run({
    required BenchmarkDataset dataset,
    required AnalysisModel model,
    required AnalysisTaskSpec taskSpec,
    required ProgressCallback onProgress,
    bool Function()? shouldCancel,
  }) async {
    final List<BenchmarkPredictionRow> rows = <BenchmarkPredictionRow>[];
    int latencySum = 0;

    for (int i = 0; i < dataset.examples.length; i++) {
      if (shouldCancel?.call() ?? false) {
        break;
      }
      final LabeledExample example = dataset.examples[i];
      final result = await model.analyze(
        AnalysisRequest(
          taskId: taskSpec.id,
          inputs: <InputAsset>[example.image],
          taskSpec: taskSpec,
        ),
      );

      if (result.succeeded && result.prediction != null) {
        latencySum += result.metadata.latencyMs;
        rows.add(
          BenchmarkPredictionRow(
            file: example.relativePath,
            groundTruth: example.groundTruthLabel,
            predictedLabel: result.prediction!.label,
            confidence: result.prediction!.confidence,
            latencyMs: result.metadata.latencyMs,
            modelId: result.modelId,
            succeeded: true,
            scores: result.prediction!.scores,
          ),
        );
      } else {
        rows.add(
          BenchmarkPredictionRow(
            file: example.relativePath,
            groundTruth: example.groundTruthLabel,
            latencyMs: result.metadata.latencyMs,
            modelId: result.modelId,
            succeeded: false,
            failureReason: result.failure?.message ?? 'Unknown failure',
          ),
        );
      }

      final int succeededCount = rows.where((BenchmarkPredictionRow row) => row.succeeded).length;
      final double averageLatency = succeededCount == 0 ? 0.0 : latencySum / succeededCount;
      onProgress(
        BenchmarkProgress(
          current: i + 1,
          total: dataset.examples.length,
          currentFile: example.relativePath,
          averageLatencyMs: averageLatency,
          isFinished: i + 1 == dataset.examples.length,
        ),
      );
    }

    final BenchmarkMetrics metrics = computeBenchmarkMetrics(rows);
    final BenchmarkExportBundle exports = await _exportService.exportToFiles(
      datasetName: dataset.name,
      modelMetadata: <String, Object?>{
        'model_id': model.id,
        'display_name': model.displayName,
        'family': model.family,
      },
      metrics: metrics,
      rows: rows,
    );

    return BenchmarkRunResult(
      dataset: dataset,
      rows: rows,
      metrics: metrics,
      exports: exports,
    );
  }
}
