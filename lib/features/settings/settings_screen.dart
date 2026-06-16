import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../analysis/analysis_registry.dart';
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
                'These settings configure local model execution only. They are not the future study server. For EmotiEff, choose one model variant and one local runtime.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              for (final model in controller.models) _ModelSettingsCard(controller: controller, model: model),
            ],
          );
        },
      ),
    );
  }
}

class _ModelSettingsCard extends StatelessWidget {
  const _ModelSettingsCard({required this.controller, required this.model});

  final AppController controller;
  final RegisteredModel model;

  @override
  Widget build(BuildContext context) {
    final ModelConfig config = controller.configForModel(model.id);
    final ModelVariant selectedVariant = model.variantById(config.variantId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(model.displayName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedVariant.id,
              decoration: const InputDecoration(labelText: 'Model variant'),
              items: <DropdownMenuItem<String>>[
                for (final variant in model.variants)
                  DropdownMenuItem(value: variant.id, child: Text(variant.displayName)),
              ],
              onChanged: (String? variantId) {
                if (variantId == null) return;
                final ModelVariant variant = model.variantById(variantId);
                controller.updateModelConfig(
                  model.id,
                  config.copyWith(
                    variantId: variant.id,
                    version: variant.version,
                  ),
                );
              },
            ),
            if (selectedVariant.notes != null || selectedVariant.expectedFileName != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                <String>[
                  if (selectedVariant.expectedFileName != null) 'Expected file: ${selectedVariant.expectedFileName}',
                  if (selectedVariant.notes != null) selectedVariant.notes!,
                ].join('\n'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: config.runtimeBackend,
              decoration: const InputDecoration(
                labelText: 'Local runtime',
                helperText: 'mock for UI tests; ONNX Runtime for the first real EmotiEff implementation',
              ),
              items: <DropdownMenuItem<String>>[
                for (final runtime in model.runtimeOptions)
                  DropdownMenuItem(value: runtime.id, child: Text(runtime.displayName)),
              ],
              onChanged: (String? runtime) {
                if (runtime == null) return;
                controller.updateModelConfig(
                  model.id,
                  config.copyWith(runtimeOptions: <String, Object?>{...config.runtimeOptions, 'backend': runtime}),
                );
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: (config.assetConfig['asset_path'] as String?) ?? '',
              decoration: InputDecoration(
                labelText: 'Model file path',
                helperText: selectedVariant.expectedFileName == null
                    ? 'Future path to a downloaded model file or folder on the device'
                    : 'Path to ${selectedVariant.expectedFileName} on the device',
              ),
              onChanged: (String path) {
                controller.updateModelConfig(
                  model.id,
                  config.copyWith(assetConfig: <String, Object?>{...config.assetConfig, 'asset_path': path}),
                );
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final FilePickerResult? result = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: <String>['onnx'],
                );
                final String? path = result?.files.single.path;
                if (path == null) return;
                await controller.updateModelConfig(
                  model.id,
                  config.copyWith(assetConfig: <String, Object?>{...config.assetConfig, 'asset_path': path}),
                );
              },
              icon: const Icon(Icons.file_open),
              label: const Text('Pick ONNX file'),
            ),
          ],
        ),
      ),
    );
  }
}
