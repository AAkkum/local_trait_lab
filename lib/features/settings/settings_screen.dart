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
              for (final model in controller.models)
                _ModelSettingsCard(controller: controller, model: model),
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
            Text(model.displayName,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedVariant.id,
              decoration: const InputDecoration(labelText: 'Model variant'),
              items: <DropdownMenuItem<String>>[
                for (final variant in model.variants)
                  DropdownMenuItem(
                      value: variant.id, child: Text(variant.displayName)),
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
            if (selectedVariant.notes != null ||
                selectedVariant.expectedFileName != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                <String>[
                  if (selectedVariant.expectedFileName != null)
                    'Expected file: ${selectedVariant.expectedFileName}',
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
                helperText:
                    'Select the local execution runtime for this model.',
              ),
              items: <DropdownMenuItem<String>>[
                for (final runtime in model.runtimeOptions)
                  DropdownMenuItem(
                      value: runtime.id, child: Text(runtime.displayName)),
              ],
              onChanged: (String? runtime) {
                if (runtime == null) return;
                controller.updateModelConfig(
                  model.id,
                  config.copyWith(runtimeOptions: <String, Object?>{
                    ...config.runtimeOptions,
                    'backend': runtime
                  }),
                );
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey<String>(
                  '${model.id}-${config.variantId}-${config.assetConfig['asset_path'] ?? ''}'),
              initialValue: (config.assetConfig['asset_path'] as String?) ?? '',
              decoration: InputDecoration(
                labelText: 'Imported model path',
                helperText: _modelFileHelperText(model, selectedVariant),
              ),
              onChanged: (String path) {
                controller.updateModelConfig(
                  model.id,
                  config.copyWith(assetConfig: <String, Object?>{
                    ...config.assetConfig,
                    'asset_path': path
                  }),
                );
              },
            ),
            const SizedBox(height: 8),
            if (model.family == 'gemma') ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final ModelConfig latestConfig =
                      controller.configForModel(model.id);
                  final ModelVariant latestVariant =
                      model.variantById(latestConfig.variantId);
                  final String privatePath =
                      '/data/user/0/com.atabey.local_trait_lab/app_flutter/models/${latestVariant.expectedFileName ?? 'gemma-4-E2B-it.litertlm'}';
                  await controller.updateModelConfig(
                    model.id,
                    latestConfig.copyWith(
                      runtimeOptions: <String, Object?>{
                        ...latestConfig.runtimeOptions,
                        'backend': 'litert_lm',
                      },
                      assetConfig: <String, Object?>{
                        ...latestConfig.assetConfig,
                        'asset_path': privatePath,
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.lock),
                label: const Text('Use app-private model path'),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final ModelConfig latestConfig =
                    controller.configForModel(model.id);
                final ModelVariant latestVariant =
                    model.variantById(latestConfig.variantId);
                final FilePickerResult? result =
                    await FilePicker.pickFiles(type: FileType.any);
                final PlatformFile? picked = result?.files.single;
                if (picked == null) return;
                try {
                  final String path = await _importModelFile(
                    model: model,
                    selectedVariant: latestVariant,
                    picked: picked,
                  );
                  await controller.updateModelConfig(
                    model.id,
                    latestConfig.copyWith(
                      assetConfig: <String, Object?>{
                        ...latestConfig.assetConfig,
                        'asset_path': path
                      },
                    ),
                  );
                } on FileSystemException catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error.message)));
                }
              },
              icon: const Icon(Icons.file_open),
              label: Text(_importButtonLabel(model)),
            ),
          ],
        ),
      ),
    );
  }

  String _modelFileHelperText(
      RegisteredModel model, ModelVariant selectedVariant) {
    if (model.family == 'gemma') {
      return 'Expected file: ${selectedVariant.expectedFileName}. Gemma must be in app-private storage; shared /sdcard paths are not readable by LiteRT-LM.';
    }
    if (selectedVariant.expectedFileName == null) {
      return 'Path to the app-private imported model file';
    }
    return 'Expected file: ${selectedVariant.expectedFileName}. Stored as an app-private copy for ONNX Runtime.';
  }

  String _importButtonLabel(RegisteredModel model) {
    return model.family == 'gemma'
        ? 'Import LiteRT-LM file'
        : 'Import ONNX file';
  }

  Future<String> _importModelFile({
    required RegisteredModel model,
    required ModelVariant selectedVariant,
    required PlatformFile picked,
  }) async {
    final String? sourcePath = picked.path;
    final List<int>? sourceBytes = picked.bytes;
    final String pickedName = picked.name;
    final String extension = p.extension(pickedName).toLowerCase();

    if (model.family == 'gemma' && extension != '.litertlm') {
      throw FileSystemException(
          'Gemma 4 needs a .litertlm file. Selected: $pickedName');
    }
    if (model.family != 'gemma' && extension != '.onnx') {
      throw FileSystemException(
          'This model needs a .onnx file. Selected: $pickedName');
    }
    if (selectedVariant.expectedFileName != null &&
        pickedName != selectedVariant.expectedFileName) {
      throw FileSystemException(
        'Selected $pickedName, but ${selectedVariant.displayName} expects ${selectedVariant.expectedFileName}.',
      );
    }

    final int sourceLength;
    if (sourceBytes != null && sourceBytes.isNotEmpty) {
      sourceLength = sourceBytes.length;
    } else if (sourcePath != null) {
      sourceLength = await File(sourcePath).length();
    } else {
      throw const FileSystemException('No model source selected.');
    }

    if (model.family == 'gemma' && sourceLength < 1024 * 1024 * 1024) {
      throw FileSystemException(
        'Selected Gemma file is only ${(sourceLength / (1024 * 1024)).toStringAsFixed(1)} MB. This is probably not the real Gemma 4 model.',
      );
    }
    if (model.family == 'gemma') {
      if (sourcePath == null) {
        throw const FileSystemException(
            'Gemma import needs a real file path, not in-memory bytes. Put the model in /sdcard/Demo and use that path.');
      }
      return sourcePath;
    }

    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory modelsDir = Directory(p.join(documents.path, 'models'));
    await modelsDir.create(recursive: true);
    final String safeName =
        pickedName.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final File target = File(p.join(modelsDir.path, safeName));

    if (sourceBytes != null && sourceBytes.isNotEmpty) {
      await target.writeAsBytes(sourceBytes, flush: true);
    } else {
      final File source = File(sourcePath!);
      await source.openRead().pipe(target.openWrite());
    }
    return target.path;
  }
}
