import 'package:flutter/material.dart';

import '../../app/app_controller.dart';

class ModelSelector extends StatelessWidget {
  const ModelSelector({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: false,
      title: const Text('Model'),
      subtitle: Text(controller.selectedModel.displayName),
      children: <Widget>[
        for (final model in controller.models)
          ListTile(
            selected: controller.selectedModelId == model.id,
            onTap: () => controller.selectModel(model.id),
            leading: Icon(
              controller.selectedModelId == model.id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            ),
            title: Text(model.displayName),
            subtitle: Text(
              '${model.family} · ${model.benchmarkEligible ? 'benchmark-ready' : 'single-run only'}',
            ),
          ),
      ],
    );
  }
}
