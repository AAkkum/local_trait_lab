import '../../analysis/task_spec.dart';

class GemmaRuntimeOutput {
  const GemmaRuntimeOutput({
    required this.rawText,
    required this.latencyMs,
    required this.runtimeBackend,
    this.debug = const <String, Object?>{},
  });

  final String rawText;
  final int latencyMs;
  final String runtimeBackend;
  final Map<String, Object?> debug;
}

abstract class GemmaRuntime {
  Future<void> load() async {}

  Future<GemmaRuntimeOutput> runTask({
    required AnalysisTaskSpec taskSpec,
    required InputAsset asset,
    required String prompt,
  });

  Future<void> close() async {}
}
