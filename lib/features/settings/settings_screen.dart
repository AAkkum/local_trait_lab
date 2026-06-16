import 'package:flutter/material.dart';

import '../../analysis/model_config.dart';
import '../../app/app_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              SwitchListTile(
                title: const Text('Debug mode'),
                value: controller.settings.debugMode,
                onChanged: controller.updateDebugMode,
              ),
              SwitchListTile(
                title: const Text('Retain raw outputs'),
                value: controller.settings.rawOutputRetention,
                onChanged: controller.updateRawOutputRetention,
              ),
              const SizedBox(height: 12),
              for (final model in controller.models)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(model.displayName, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: (controller.settings.modelConfigs[model.id] ?? model.config).runtimeBackend,
                          decoration: const InputDecoration(labelText: 'Runtime backend'),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(value: 'mock', child: Text('mock')),
                            DropdownMenuItem(value: 'onnx', child: Text('onnx')),
                            DropdownMenuItem(value: 'android_native', child: Text('android_native')),
                          ],
                          onChanged: (String? backend) {
                            if (backend == null) return;
                            final ModelConfig current = controller.settings.modelConfigs[model.id] ?? model.config;
                            controller.updateModelConfig(
                              model.id,
                              current.copyWith(
                                runtimeOptions: <String, Object?>{...current.runtimeOptions, 'backend': backend},
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: ((controller.settings.modelConfigs[model.id] ?? model.config).assetConfig['asset_path']) as String? ?? '',
                          decoration: const InputDecoration(labelText: 'Asset path'),
                          onChanged: (String path) {
                            final ModelConfig current = controller.settings.modelConfigs[model.id] ?? model.config;
                            controller.updateModelConfig(
                              model.id,
                              current.copyWith(assetConfig: <String, Object?>{...current.assetConfig, 'asset_path': path}),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
