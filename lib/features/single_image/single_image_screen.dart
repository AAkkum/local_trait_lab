import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../results/result_screen.dart';

class SingleImageScreen extends StatelessWidget {
  const SingleImageScreen({super.key, required this.controller});

  final AppController controller;

  Future<void> _pickImage() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result != null) {
      await controller.selectImageFromPickerResult(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Single Image Demo')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Selected model: ${controller.selectedModel.displayName}'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.file_open),
                  label: const Text('Select Image'),
                ),
                const SizedBox(height: 12),
                if (controller.selectedImage != null)
                  Text(
                    'Image: ${controller.selectedImage!.displayName} (${controller.selectedImage!.sizeBytes} bytes)',
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: controller.isBusy
                      ? null
                      : () async {
                          await controller.runSingleImageAnalysis();
                          if (context.mounted && controller.lastResult != null) {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => ResultScreen(controller: controller)),
                            );
                          }
                        },
                  icon: controller.isBusy
                      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: const Text('Run Inference'),
                ),
                if (controller.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(controller.errorMessage!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
