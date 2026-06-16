class ModelConfig {
  const ModelConfig({
    required this.modelId,
    required this.variantId,
    required this.version,
    this.runtimeOptions = const <String, Object?>{},
    this.assetConfig = const <String, Object?>{},
  });

  final String modelId;
  final String variantId;
  final Map<String, Object?> runtimeOptions;
  final Map<String, Object?> assetConfig;
  final String version;

  String get runtimeBackend => (runtimeOptions['backend'] as String?) ?? 'mock';

  ModelConfig copyWith({
    String? modelId,
    String? variantId,
    Map<String, Object?>? runtimeOptions,
    Map<String, Object?>? assetConfig,
    String? version,
  }) {
    return ModelConfig(
      modelId: modelId ?? this.modelId,
      variantId: variantId ?? this.variantId,
      runtimeOptions: runtimeOptions ?? this.runtimeOptions,
      assetConfig: assetConfig ?? this.assetConfig,
      version: version ?? this.version,
    );
  }
}
