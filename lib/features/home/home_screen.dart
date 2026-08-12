import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../benchmark_setup/benchmark_setup_screen.dart';
import '../privacy_inference/privacy_inference_screen.dart';
import '../settings/settings_screen.dart';
import '../single_image/single_image_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Trait Lab'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(controller: controller),
              ),
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
              Text('Analysis workflows',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Run model validation benchmarks or collect local inference reactions for the user study.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy inference study'),
                  subtitle: const Text(
                      'Gemma analysis of selected photos and PDFs with follow-up questions'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PrivacyInferenceScreen(controller: controller),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.mood),
                  title: const Text('Emotion analysis'),
                  subtitle: Text(
                      'Single image inference · model family: ${controller.selectedModel.displayName}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            SingleImageScreen(controller: controller)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.analytics),
                  title: const Text('Dataset benchmark'),
                  subtitle: const Text(
                      'Evaluate emotion model predictions on labeled images'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            BenchmarkSetupScreen(controller: controller)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Advanced settings'),
                  subtitle: const Text(
                      'Model variants and local runtime configuration'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => SettingsScreen(controller: controller)),
                  ),
                ),
              ),
              if (controller.errorMessage != null) ...<Widget>[
                const SizedBox(height: 16),
                Text(controller.errorMessage!,
                    style: const TextStyle(color: Colors.red)),
              ],
            ],
          );
        },
      ),
    );
  }
}
