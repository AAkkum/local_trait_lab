import 'package:flutter/material.dart';

import '../../analysis/model_config.dart';
import '../../app/app_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced settings')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                'These settings are for local model execution only. They are not the future study server. The server part will later receive consented study answers or processed results, not run this inference path by default.',
                style: Theme.of(context).textTheme.bodyMedium,
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
                          decoration: const InputDecoration(
                            labelText: 'Local runtime',
                            helperText: 'mock now; ONNX or Android native later for real on-device inference',
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(value: 'mock', child: Text('mock')),
                            DropdownMenuItem(value: 'onnx', child: Text('onnx')),
                            DropdownMenuItem(value: 'android_native', child: Text('android native')),
                          ],
                          onChanged: (String? runtime) {
                            if (runtime == null) return;
                            final ModelConfig current = controller.settings.modelConfigs[model.id] ?? model.config;
                            controller.updateModelConfig(
                              model.id,
                              current.copyWith(
                                runtimeOptions: <String, Object?>{...current.runtimeOptions, 'backend': runtime},
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: ((controller.settings.modelConfigs[model.id] ?? model.config).assetConfig['asset_path']) as String? ?? '',
                          decoration: const InputDecoration(
                            labelText: 'Model file path',
                            helperText: 'Future path to a downloaded model file or folder on the device',
                          ),
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
