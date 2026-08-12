import 'package:local_trait_lab/analysis/analysis_request.dart';
import 'package:local_trait_lab/analysis/model_config.dart';
import 'package:local_trait_lab/analysis/task_catalog.dart';
import 'package:local_trait_lab/analysis/task_spec.dart';
import 'package:local_trait_lab/models/emotieff/emotieff_analysis_model.dart';
import 'package:local_trait_lab/models/gemma/gemma_analysis_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const InputAsset image = InputAsset(
    type: InputAssetType.image,
    uri: 'memory://test.jpg',
    displayName: 'test.jpg',
    mimeType: 'image/jpeg',
    sizeBytes: 4,
    bytes: <int>[1, 2, 3, 4],
  );

  test('mock gemma returns a standardized result', () async {
    final GemmaAnalysisModel model = GemmaAnalysisModel();
    await model.load(const ModelConfig(
        modelId: 'gemma',
        variantId: 'gemma_e2b',
        version: 'mock',
        runtimeOptions: <String, Object?>{'backend': 'mock'}));
    final result = await model.analyze(
      const AnalysisRequest(
          taskId: 'emotion_classification',
          inputs: <InputAsset>[image],
          taskSpec: TaskCatalog.emotionClassification),
    );
    expect(result.succeeded, isTrue);
    expect(result.prediction!.scores.length, 7);
  });

  test('mock gemma returns bounded privacy profile fields', () async {
    final GemmaAnalysisModel model = GemmaAnalysisModel();
    await model.load(const ModelConfig(
        modelId: 'gemma',
        variantId: 'gemma_e2b',
        version: 'mock',
        runtimeOptions: <String, Object?>{'backend': 'mock'}));
    final result = await model.analyze(
      const AnalysisRequest(
        taskId: 'privacy_profile_synthesis',
        inputs: <InputAsset>[
          InputAsset(
            type: InputAssetType.text,
            uri: 'memory://profile.json',
            displayName: 'profile.json',
            mimeType: 'application/json',
            sizeBytes: 2,
            text: '{}',
          ),
        ],
        taskSpec: TaskCatalog.privacyProfileSynthesis,
      ),
    );
    final Map<String, dynamic> profile =
        result.rawOutput! as Map<String, dynamic>;
    expect(result.succeeded, isTrue);
    expect(profile['headline'], isA<String>());
    expect(profile['key_inferences'], hasLength(3));
    expect(profile['privacy_implication'], isA<String>());
  });

  test('mock gemma supports structured privacy profile repair', () async {
    final GemmaAnalysisModel model = GemmaAnalysisModel();
    await model.load(const ModelConfig(
        modelId: 'gemma',
        variantId: 'gemma_e2b',
        version: 'mock',
        runtimeOptions: <String, Object?>{'backend': 'mock'}));
    final result = await model.analyze(
      const AnalysisRequest(
        taskId: 'privacy_profile_repair',
        inputs: <InputAsset>[
          InputAsset(
            type: InputAssetType.text,
            uri: 'memory://profile-draft.txt',
            displayName: 'profile-draft.txt',
            mimeType: 'text/plain',
            sizeBytes: 16,
            text: 'Malformed draft',
          ),
        ],
        taskSpec: TaskCatalog.privacyProfileRepair,
      ),
    );
    final Map<String, dynamic> profile =
        result.rawOutput! as Map<String, dynamic>;
    expect(result.succeeded, isTrue);
    expect(profile['key_inferences'], hasLength(3));
    expect(profile['privacy_implication'], isA<String>());
  });

  test('mock emotieff returns a standardized result', () async {
    final EmotiEffEmotionModel model = EmotiEffEmotionModel();
    await model.load(const ModelConfig(
        modelId: 'emotieff',
        variantId: 'emotieff_mock_onnx',
        version: 'mock',
        runtimeOptions: <String, Object?>{'backend': 'mock'}));
    final result = await model.analyze(
      const AnalysisRequest(
          taskId: 'emotion_classification',
          inputs: <InputAsset>[image],
          taskSpec: TaskCatalog.emotionClassification),
    );
    expect(result.succeeded, isTrue);
    expect(result.prediction!.scores.length, 7);
  });
}
