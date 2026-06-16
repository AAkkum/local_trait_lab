import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../benchmark_progress/benchmark_progress_screen.dart';
import '../shared/model_selector.dart';

class BenchmarkSetupScreen extends StatelessWidget {
  const BenchmarkSetupScreen({super.key, required this.controller});

  final AppController controller;

  Future<void> _pickZip() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['zip'],
    );
    if (result != null && result.files.single.path != null) {
      await controller.importBenchmarkZip(result.files.single.path!);
    }
  }

  Future<void> _pickDirectory() async {
    final String? directory = await FilePicker.getDirectoryPath();
    if (directory != null) {
      await controller.importBenchmarkDirectory(directory);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dataset benchmark')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          final dataset = controller.benchmarkDataset;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                'Import a labeled emotion dataset and run the selected local model on the same analysis path used by the single-image workflow.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              ModelSelector(controller: controller),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickZip,
                icon: const Icon(Icons.archive),
                label: const Text('Import dataset ZIP'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickDirectory,
                icon: const Icon(Icons.folder_open),
                label: const Text('Import dataset folder'),
              ),
              const SizedBox(height: 16),
              if (dataset != null) ...<Widget>[
                Text('Dataset: ${dataset.name}'),
                Text('Examples: ${dataset.examples.length}'),
                Text('Source: ${dataset.sourceType}'),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: dataset == null
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => BenchmarkProgressScreen(controller: controller)),
                        );
                      },
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Start benchmark'),
              ),
              if (controller.errorMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(controller.errorMessage!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          );
        },
      ),
    );
  }
}
