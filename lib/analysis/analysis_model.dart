import 'analysis_request.dart';
import 'analysis_result.dart';
import 'model_config.dart';

abstract class AnalysisModel {
  String get id;
  String get displayName;
  String get family;
  Set<String> get supportedTasks;
  bool get isLoaded;
  bool get benchmarkEligible;

  Future<void> load(ModelConfig config);
  Future<AnalysisResult> analyze(AnalysisRequest request);
  Future<void> unload();
}
