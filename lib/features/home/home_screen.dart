import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../benchmark_setup/benchmark_setup_screen.dart';
import '../settings/settings_screen.dart';
import '../single_image/single_image_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emotion Benchmark App'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => SettingsScreen(controller: controller)),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              const Text(
                'Select a model backend',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (final model in controller.models)
                Card(
                  child: RadioListTile<String>(
                    value: model.id,
                    groupValue: controller.selectedModelId,
                    onChanged: (String? value) {
                      if (value != null) controller.selectModel(value);
                    },
                    title: Text(model.displayName),
                    subtitle: Text(
                      'Family: ${model.family} | Benchmark: ${model.benchmarkEligible ? 'eligible' : 'disabled'} | '
                      'Backend: ${(controller.settings.modelConfigs[model.id] ?? model.config).runtimeBackend}',
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.image_search),
                label: const Text('Single Image Demo'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => SingleImageScreen(controller: controller)),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.analytics),
                label: const Text('Benchmark Mode'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => BenchmarkSetupScreen(controller: controller)),
                ),
              ),
              if (controller.errorMessage != null) ...<Widget>[
                const SizedBox(height: 16),
                Text(controller.errorMessage!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          );
        },
      ),
    );
  }
}
