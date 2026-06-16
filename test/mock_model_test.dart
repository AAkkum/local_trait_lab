import 'package:emotion_benchmark_app/analysis/analysis_request.dart';
import 'package:emotion_benchmark_app/analysis/model_config.dart';
import 'package:emotion_benchmark_app/analysis/task_catalog.dart';
import 'package:emotion_benchmark_app/analysis/task_spec.dart';
import 'package:emotion_benchmark_app/models/emotieff/emotieff_analysis_model.dart';
import 'package:emotion_benchmark_app/models/gemma/gemma_analysis_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final InputAsset image = InputAsset(
    type: InputAssetType.image,
    uri: 'memory://test.jpg',
    displayName: 'test.jpg',
    mimeType: 'image/jpeg',
    sizeBytes: 4,
    bytes: const <int>[1, 2, 3, 4],
  );

  test('mock gemma returns a standardized result', () async {
    final GemmaAnalysisModel model = GemmaAnalysisModel();
    await model.load(const ModelConfig(modelId: 'gemma', variantId: 'gemma_e2b', version: 'mock', runtimeOptions: <String, Object?>{'backend': 'mock'}));
    final result = await model.analyze(
      AnalysisRequest(taskId: 'emotion_classification', inputs: <InputAsset>[image], taskSpec: TaskCatalog.emotionClassification),
    );
    expect(result.succeeded, isTrue);
    expect(result.prediction!.scores.length, 7);
  });

  test('mock emotieff returns a standardized result', () async {
    final EmotiEffEmotionModel model = EmotiEffEmotionModel();
    await model.load(const ModelConfig(modelId: 'emotieff', variantId: 'emotieff_mock_onnx', version: 'mock', runtimeOptions: <String, Object?>{'backend': 'mock'}));
    final result = await model.analyze(
      AnalysisRequest(taskId: 'emotion_classification', inputs: <InputAsset>[image], taskSpec: TaskCatalog.emotionClassification),
    );
    expect(result.succeeded, isTrue);
    expect(result.prediction!.scores.length, 7);
  });
}
