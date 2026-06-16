import '../../analysis/task_spec.dart';

class EmotiEffRuntimeOutput {
  const EmotiEffRuntimeOutput({
    required this.rawScores,
    required this.latencyMs,
    required this.runtimeBackend,
    this.debug = const <String, Object?>{},
  });

  final Map<String, double> rawScores;
  final int latencyMs;
  final String runtimeBackend;
  final Map<String, Object?> debug;
}

abstract class EmotiEffRuntime {
  Future<EmotiEffRuntimeOutput> classifyEmotion({
    required InputAsset asset,
  });
}
