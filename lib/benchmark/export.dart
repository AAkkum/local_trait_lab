import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'metrics.dart';

class BenchmarkExportBundle {
  const BenchmarkExportBundle({
    required this.csvContent,
    required this.jsonContent,
    this.csvPath,
    this.jsonPath,
  });

  final String csvContent;
  final String jsonContent;
  final String? csvPath;
  final String? jsonPath;
}

class BenchmarkExportService {
  const BenchmarkExportService();

  String buildCsv(List<BenchmarkPredictionRow> rows) {
    final StringBuffer buffer = StringBuffer(
      'file,ground_truth,predicted_label,confidence,latency_ms,model_id,succeeded,failure_reason,'
      'angry,disgust,fear,happy,neutral,sad,surprise\n',
    );
    for (final BenchmarkPredictionRow row in rows) {
      buffer.writeln([
        row.file,
        row.groundTruth,
        row.predictedLabel ?? '',
        row.confidence?.toStringAsFixed(6) ?? '',
        row.latencyMs,
        row.modelId,
        row.succeeded,
        row.failureReason ?? '',
        row.scores['angry'] ?? '',
        row.scores['disgust'] ?? '',
        row.scores['fear'] ?? '',
        row.scores['happy'] ?? '',
        row.scores['neutral'] ?? '',
        row.scores['sad'] ?? '',
        row.scores['surprise'] ?? '',
      ].join(','));
    }
    return buffer.toString();
  }

  String buildJson({
    required String datasetName,
    required Map<String, Object?> modelMetadata,
    required BenchmarkMetrics metrics,
    required List<BenchmarkPredictionRow> rows,
  }) {
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'dataset': <String, Object?>{'name': datasetName},
      'model': modelMetadata,
      'metrics': metrics.toJson(),
      'predictions': rows.map((BenchmarkPredictionRow row) {
        return <String, Object?>{
          'file': row.file,
          'ground_truth': row.groundTruth,
          'predicted_label': row.predictedLabel,
          'confidence': row.confidence,
          'latency_ms': row.latencyMs,
          'model_id': row.modelId,
          'succeeded': row.succeeded,
          'failure_reason': row.failureReason,
          'scores': row.scores,
        };
      }).toList(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<BenchmarkExportBundle> exportToFiles({
    required String datasetName,
    required Map<String, Object?> modelMetadata,
    required BenchmarkMetrics metrics,
    required List<BenchmarkPredictionRow> rows,
  }) async {
    final String csv = buildCsv(rows);
    final String json = buildJson(
      datasetName: datasetName,
      modelMetadata: modelMetadata,
      metrics: metrics,
      rows: rows,
    );

    final Directory dir = await getApplicationDocumentsDirectory();
    final String safeName = datasetName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final String base = p.join(dir.path, 'benchmark_$safeName');
    final File csvFile = File('${base}_predictions.csv');
    final File jsonFile = File('${base}_summary.json');
    await csvFile.writeAsString(csv);
    await jsonFile.writeAsString(json);

    return BenchmarkExportBundle(
      csvContent: csv,
      jsonContent: json,
      csvPath: csvFile.path,
      jsonPath: jsonFile.path,
    );
  }
}
