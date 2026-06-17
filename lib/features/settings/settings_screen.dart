import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
                'Configure model variants, local runtimes, and imported model files.',
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
                helperText: 'Select the local execution runtime for this model.',
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
                labelText: 'Imported model path',
                helperText: selectedVariant.expectedFileName == null
                    ? 'Path to the app-private imported model file'
                    : 'Import ${selectedVariant.expectedFileName}; the app stores a private copy for ONNX Runtime',
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
                final FilePickerResult? result = await FilePicker.pickFiles(type: FileType.any);
                final PlatformFile? picked = result?.files.single;
                if (picked == null) return;
                final String path = await _importModelFile(
                  preferredFileName: selectedVariant.expectedFileName ?? picked.name,
                  sourcePath: picked.path,
                  sourceBytes: picked.bytes,
                );
                await controller.updateModelConfig(
                  model.id,
                  config.copyWith(assetConfig: <String, Object?>{...config.assetConfig, 'asset_path': path}),
                );
              },
              icon: const Icon(Icons.file_open),
              label: const Text('Import ONNX file'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _importModelFile({
    required String preferredFileName,
    String? sourcePath,
    List<int>? sourceBytes,
  }) async {
    final List<int> bytes;
    if (sourceBytes != null && sourceBytes.isNotEmpty) {
      bytes = sourceBytes;
    } else if (sourcePath != null) {
      bytes = await File(sourcePath).readAsBytes();
    } else {
      throw const FileSystemException('No ONNX model source selected.');
    }

    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory modelsDir = Directory(p.join(documents.path, 'models'));
    await modelsDir.create(recursive: true);
    final String safeName = preferredFileName.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final File target = File(p.join(modelsDir.path, safeName));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }
}
