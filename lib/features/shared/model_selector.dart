import 'package:flutter/material.dart';

import '../../analysis/model_config.dart';
import '../../app/app_controller.dart';

class ModelSelector extends StatelessWidget {
  const ModelSelector({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: false,
      title: const Text('Model family'),
      subtitle: Text(_selectedModelSummary()),
      children: <Widget>[
        for (final model in controller.models)
          ListTile(
            selected: controller.selectedModelId == model.id,
            onTap: () => controller.selectModel(model.id),
            leading: Icon(
              controller.selectedModelId == model.id
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(model.displayName),
            subtitle: Text(_modelSubtitle(model.id)),
          ),
      ],
    );
  }

  String _selectedModelSummary() {
    final ModelConfig config =
        controller.configForModel(controller.selectedModel.id);
    final variant = controller.selectedModel.variantById(config.variantId);
    return '${controller.selectedModel.displayName} · ${variant.displayName}';
  }

  String _modelSubtitle(String modelId) {
    final model = controller.models.firstWhere((entry) => entry.id == modelId);
    final ModelConfig config = controller.configForModel(model.id);
    final variant = model.variantById(config.variantId);
    return '${variant.displayName} · local runtime: ${config.runtimeBackend}';
  }
}
