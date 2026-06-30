import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_controller.dart';

class BenchmarkResultsScreen extends StatelessWidget {
  const BenchmarkResultsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final run = controller.benchmarkResult;
    return Scaffold(
      appBar: AppBar(title: const Text('Benchmark Results')),
      body: run == null
          ? const Center(child: Text('No benchmark result available.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text('Dataset: ${run.dataset.name}',
                    style: Theme.of(context).textTheme.titleLarge),
                Text('Accuracy: ${run.metrics.accuracy.toStringAsFixed(4)}'),
                Text('Macro-F1: ${run.metrics.macroF1.toStringAsFixed(4)}'),
                Text(
                    'Average latency: ${run.metrics.averageLatencyMs.toStringAsFixed(2)} ms'),
                Text(
                    'Median latency: ${run.metrics.medianLatencyMs.toStringAsFixed(2)} ms'),
                Text('Evaluated examples: ${run.metrics.evaluatedExamples}'),
                Text('Failed examples: ${run.metrics.failedExamples}'),
                const SizedBox(height: 16),
                const Text('Per-class metrics',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                DataTable(
                  columns: const <DataColumn>[
                    DataColumn(label: Text('Class')),
                    DataColumn(label: Text('Precision')),
                    DataColumn(label: Text('Recall')),
                    DataColumn(label: Text('F1')),
                  ],
                  rows: run.metrics.perClass.entries.map((entry) {
                    return DataRow(cells: <DataCell>[
                      DataCell(Text(entry.key)),
                      DataCell(Text(entry.value.precision.toStringAsFixed(4))),
                      DataCell(Text(entry.value.recall.toStringAsFixed(4))),
                      DataCell(Text(entry.value.f1.toStringAsFixed(4))),
                    ]);
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text('Confusion matrix',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: <DataColumn>[
                      const DataColumn(label: Text('Actual \\ Predicted')),
                      ...run.metrics.confusionMatrix.keys.map(
                          (String label) => DataColumn(label: Text(label))),
                    ],
                    rows: run.metrics.confusionMatrix.entries.map((entry) {
                      return DataRow(
                        cells: <DataCell>[
                          DataCell(Text(entry.key)),
                          ...entry.value.values.map(
                              (int value) => DataCell(Text(value.toString()))),
                        ],
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                Text('CSV export: ${run.exports.csvPath ?? 'in-memory only'}'),
                Text(
                    'JSON export: ${run.exports.jsonPath ?? 'in-memory only'}'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: run.exports.csvPath == null &&
                          run.exports.jsonPath == null
                      ? null
                      : () async {
                          final files = <XFile>[
                            if (run.exports.csvPath != null)
                              XFile(run.exports.csvPath!),
                            if (run.exports.jsonPath != null)
                              XFile(run.exports.jsonPath!),
                          ];
                          await SharePlus.instance.share(
                            ShareParams(
                              files: files,
                              subject:
                                  'Benchmark exports for ${run.dataset.name}',
                              text: 'Benchmark exports for ${run.dataset.name}',
                            ),
                          );
                        },
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share export files'),
                ),
              ],
            ),
    );
  }
}
