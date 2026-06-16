import 'dart:convert';

import 'package:local_trait_lab/benchmark/export.dart';
import 'package:local_trait_lab/benchmark/metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const BenchmarkExportService service = BenchmarkExportService();

  test('creates csv and json outputs', () {
    final List<BenchmarkPredictionRow> rows = <BenchmarkPredictionRow>[
      const BenchmarkPredictionRow(
        file: 'images/a.jpg',
        groundTruth: 'happy',
        predictedLabel: 'happy',
        confidence: 0.9,
        latencyMs: 15,
        modelId: 'gemma_e2b',
        succeeded: true,
        scores: <String, double>{'happy': 0.9},
      ),
    ];
    final BenchmarkMetrics metrics = computeBenchmarkMetrics(rows);
    final String csv = service.buildCsv(rows);
    final String json = service.buildJson(
      datasetName: 'demo',
      modelMetadata: <String, Object?>{'model_id': 'gemma_e2b'},
      metrics: metrics,
      rows: rows,
    );

    expect(csv, contains('ground_truth'));
    expect(jsonDecode(json)['dataset']['name'], 'demo');
  });
}
