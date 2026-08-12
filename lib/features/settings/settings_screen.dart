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
              _GemmaDownloadPanel(
                controller: controller,
                model: model,
                config: config,
                selectedVariant: selectedVariant,
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
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory modelsDir = Directory(p.join(documents.path, 'models'));
    await modelsDir.create(recursive: true);
    final String safeName = (selectedVariant.expectedFileName ?? pickedName)
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
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

class _GemmaDownloadPanel extends StatefulWidget {
  const _GemmaDownloadPanel({
    required this.controller,
    required this.model,
    required this.config,
    required this.selectedVariant,
  });

  final AppController controller;
  final RegisteredModel model;
  final ModelConfig config;
  final ModelVariant selectedVariant;

  @override
  State<_GemmaDownloadPanel> createState() => _GemmaDownloadPanelState();
}

class _GemmaDownloadPanelState extends State<_GemmaDownloadPanel> {
  late final TextEditingController _urlController;
  double? _progress;
  String? _message;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: _defaultGemmaDownloadUrl(widget.selectedVariant),
    );
  }

  @override
  void didUpdateWidget(covariant _GemmaDownloadPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedVariant.id != widget.selectedVariant.id) {
      _urlController.text = _defaultGemmaDownloadUrl(widget.selectedVariant);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Gemma model file',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              'The app cannot ship a 2.6 GB model. Download or import it once into app-private storage.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _urlController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Download URL',
                helperText:
                    'Default uses the LiteRT community Hugging Face file. Paste another direct .litertlm URL if needed.',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _downloading ? null : _downloadModel,
              icon: _downloading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(
                  _downloading ? 'Downloading model' : 'Download Gemma model'),
            ),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 8),
              if (_progress != null) LinearProgressIndicator(value: _progress),
              const SizedBox(height: 4),
              Text(_message!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _downloadModel() async {
    final Uri? uri = Uri.tryParse(_urlController.text.trim());
    if (uri == null || !uri.hasScheme) {
      setState(() => _message = 'Enter a valid model download URL.');
      return;
    }
    setState(() {
      _downloading = true;
      _progress = null;
      _message =
          'Starting download. This is a multi-GB file and can take several minutes.';
    });
    try {
      final Directory documents = await getApplicationDocumentsDirectory();
      final Directory modelsDir = Directory(p.join(documents.path, 'models'));
      await modelsDir.create(recursive: true);
      final String fileName =
          widget.selectedVariant.expectedFileName ?? 'gemma_model.litertlm';
      final File target = File(p.join(modelsDir.path, fileName));
      final File temp = File('${target.path}.download');
      if (await temp.exists()) await temp.delete();

      final HttpClientRequest request = await _openWithRedirects(uri);
      final HttpClientResponse response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}',
            uri: uri);
      }
      final int total = response.contentLength;
      int received = 0;
      final IOSink sink = temp.openWrite();
      await for (final List<int> chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        if (mounted) {
          setState(() {
            _progress = total > 0 ? received / total : null;
            _message = total > 0
                ? 'Downloaded ${(received / (1024 * 1024)).toStringAsFixed(1)} MB / ${(total / (1024 * 1024)).toStringAsFixed(1)} MB'
                : 'Downloaded ${(received / (1024 * 1024)).toStringAsFixed(1)} MB';
          });
        }
      }
      await sink.flush();
      await sink.close();
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
      await widget.controller.updateModelConfig(
        widget.model.id,
        widget.config.copyWith(
          runtimeOptions: <String, Object?>{
            ...widget.config.runtimeOptions,
            'backend': 'litert_lm',
          },
          assetConfig: <String, Object?>{
            ...widget.config.assetConfig,
            'asset_path': target.path,
          },
        ),
      );
      if (mounted) {
        setState(() {
          _progress = 1.0;
          _message = 'Download complete. Gemma path updated.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _progress = null;
          _message = 'Download failed: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<HttpClientRequest> _openWithRedirects(Uri uri) async {
    final HttpClient client = HttpClient();
    Uri current = uri;
    for (int i = 0; i < 5; i++) {
      final HttpClientRequest request = await client.getUrl(current);
      request.followRedirects = false;
      final HttpClientResponse response = await request.close();
      if (response.isRedirect &&
          response.headers.value(HttpHeaders.locationHeader) != null) {
        final String location =
            response.headers.value(HttpHeaders.locationHeader)!;
        current = current.resolve(location);
        await response.drain<void>();
        continue;
      }
      return client.getUrl(current);
    }
    throw HttpException('Too many redirects', uri: uri);
  }

  String _defaultGemmaDownloadUrl(ModelVariant variant) {
    if (variant.id == 'gemma_e4b') {
      return 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm?download=true';
    }
    return 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true';
  }
}
