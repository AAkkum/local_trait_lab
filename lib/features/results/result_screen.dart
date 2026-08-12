import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final result = controller.lastResult;
    return Scaffold(
      appBar: AppBar(title: const Text('Analysis result')),
      body: result == null
          ? const Center(child: Text('No result available.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text('Model: ${result.modelId}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (result.succeeded) ...<Widget>[
                  Text('Prediction: ${result.prediction!.label}',
                      style: Theme.of(context).textTheme.headlineSmall),
                  Text(
                      'Confidence: ${result.prediction!.confidence.toStringAsFixed(4)}'),
                  const SizedBox(height: 12),
                  for (final entry in result.prediction!.scores.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: <Widget>[
                          SizedBox(width: 80, child: Text(entry.key)),
                          Expanded(
                              child:
                                  LinearProgressIndicator(value: entry.value)),
                          const SizedBox(width: 12),
                          Text(entry.value.toStringAsFixed(4)),
                        ],
                      ),
                    ),
                ] else ...<Widget>[
                  Text('Failure: ${result.failure?.message ?? 'Unknown'}',
                      style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 12),
                Text('Latency: ${result.metadata.latencyMs} ms'),
                Text('Input file: ${result.metadata.inputFile}'),
                Text('Local runtime: ${result.metadata.runtimeBackend}'),
                const SizedBox(height: 12),
                ExpansionTile(
                  title: const Text('Raw output'),
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(const JsonEncoder.withIndent('  ')
                          .convert(result.rawOutput)),
                    ),
                  ],
                ),
                ExpansionTile(
                  title: const Text('Metadata'),
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(const JsonEncoder.withIndent('  ')
                          .convert(result.metadata.toJson())),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
