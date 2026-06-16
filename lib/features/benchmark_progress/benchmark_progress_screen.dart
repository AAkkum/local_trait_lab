import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../benchmark_results/benchmark_results_screen.dart';

class BenchmarkProgressScreen extends StatefulWidget {
  const BenchmarkProgressScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<BenchmarkProgressScreen> createState() => _BenchmarkProgressScreenState();
}

class _BenchmarkProgressScreenState extends State<BenchmarkProgressScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.controller.runBenchmark();
      if (mounted) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => BenchmarkResultsScreen(controller: widget.controller)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Benchmark Progress')),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (BuildContext context, Widget? child) {
          final progress = widget.controller.benchmarkProgress;
          final double value = progress == null || progress.total == 0 ? 0.0 : progress.current / progress.total;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LinearProgressIndicator(value: value),
                const SizedBox(height: 12),
                Text('Progress: ${progress?.current ?? 0} / ${progress?.total ?? 0}'),
                Text('Current file: ${progress?.currentFile ?? '-'}'),
                Text('Average latency: ${(progress?.averageLatencyMs ?? 0).toStringAsFixed(2)} ms'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: widget.controller.cancelBenchmark,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Cancel'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
