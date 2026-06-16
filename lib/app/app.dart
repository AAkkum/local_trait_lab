import 'package:flutter/material.dart';

import '../analysis/analysis_registry.dart';
import '../analysis/model_config.dart';
import '../data/persistence/settings_repository.dart';
import '../features/home/home_screen.dart';
import 'app_controller.dart';

class LocalTraitLabApp extends StatefulWidget {
  const LocalTraitLabApp({super.key});

  @override
  State<LocalTraitLabApp> createState() => _LocalTraitLabAppState();
}

class _LocalTraitLabAppState extends State<LocalTraitLabApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    final List<RegisteredModel> registry = AnalysisRegistry.buildDefaultModels();
    _controller = AppController(
      registry: registry,
      settingsRepository: InMemorySettingsRepository(
        AppSettings(modelConfigs: <String, ModelConfig>{for (final RegisteredModel model in registry) model.id: model.config}),
      ),
    );
    _controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Trait Lab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          if (!_controller.initialized) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return HomeScreen(controller: _controller);
        },
      ),
    );
  }
}
