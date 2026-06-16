import '../../analysis/model_config.dart';

class AppSettings {
  const AppSettings({
    required this.modelConfigs,
    this.debugMode = false,
    this.rawOutputRetention = true,
  });

  final Map<String, ModelConfig> modelConfigs;
  final bool debugMode;
  final bool rawOutputRetention;

  AppSettings copyWith({
    Map<String, ModelConfig>? modelConfigs,
    bool? debugMode,
    bool? rawOutputRetention,
  }) {
    return AppSettings(
      modelConfigs: modelConfigs ?? this.modelConfigs,
      debugMode: debugMode ?? this.debugMode,
      rawOutputRetention: rawOutputRetention ?? this.rawOutputRetention,
    );
  }
}

abstract class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
  }
}
