import 'task_spec.dart';

class AnalysisRequest {
  const AnalysisRequest({
    required this.taskId,
    required this.inputs,
    required this.taskSpec,
    this.options = const <String, Object?>{},
  });

  final String taskId;
  final List<InputAsset> inputs;
  final AnalysisTaskSpec taskSpec;
  final Map<String, Object?> options;
}
