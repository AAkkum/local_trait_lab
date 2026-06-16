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
        title: const Text('Local Trait Lab'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Settings',
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
              Text('Choose an analysis', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Start with the trait you want to infer. Model details stay inside each workflow so the home screen does not become a wall of variants.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.mood),
                  title: const Text('Emotion analysis'),
                  subtitle: Text('Single image inference · current model family: ${controller.selectedModel.displayName}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => SingleImageScreen(controller: controller)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.analytics),
                  title: const Text('Dataset benchmark'),
                  subtitle: const Text('Evaluate a selected model on labeled emotion datasets'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => BenchmarkSetupScreen(controller: controller)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Advanced settings'),
                  subtitle: const Text('Local runtime and model file configuration'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => SettingsScreen(controller: controller)),
                  ),
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
