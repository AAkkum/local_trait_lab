import 'analysis_model.dart';
import 'model_config.dart';
import '../models/emotieff/emotieff_analysis_model.dart';
import '../models/gemma/gemma_analysis_model.dart';

typedef AnalysisModelFactory = AnalysisModel Function();

class RegisteredModel {
  const RegisteredModel({
    required this.id,
    required this.displayName,
    required this.family,
    required this.config,
    required this.benchmarkEligible,
    required this.factory,
  });

  final String id;
  final String displayName;
  final String family;
  final ModelConfig config;
  final bool benchmarkEligible;
  final AnalysisModelFactory factory;
}

class AnalysisRegistry {
  const AnalysisRegistry._();

  static List<RegisteredModel> buildDefaultModels() => <RegisteredModel>[
        RegisteredModel(
          id: 'gemma_e2b',
          displayName: 'Gemma 4 E2B',
          family: 'gemma',
          benchmarkEligible: true,
          config: const ModelConfig(
            modelId: 'gemma',
            variantId: 'gemma_e2b',
            version: 'mock-0.1',
            runtimeOptions: <String, Object?>{'backend': 'mock'},
          ),
          factory: () => GemmaAnalysisModel(),
        ),
        RegisteredModel(
          id: 'gemma_e4b',
          displayName: 'Gemma 4 E4B',
          family: 'gemma',
          benchmarkEligible: true,
          config: const ModelConfig(
            modelId: 'gemma',
            variantId: 'gemma_e4b',
            version: 'mock-0.1',
            runtimeOptions: <String, Object?>{'backend': 'mock'},
          ),
          factory: () => GemmaAnalysisModel(),
        ),
        RegisteredModel(
          id: 'emotieff_mock_onnx',
          displayName: 'EmotiEff Mock ONNX',
          family: 'emotieff',
          benchmarkEligible: true,
          config: const ModelConfig(
            modelId: 'emotieff',
            variantId: 'emotieff_mock_onnx',
            version: 'mock-0.1',
            runtimeOptions: <String, Object?>{'backend': 'mock'},
          ),
          factory: () => EmotiEffEmotionModel(),
        ),
        RegisteredModel(
          id: 'emotieff_native_placeholder',
          displayName: 'EmotiEff Native Placeholder',
          family: 'emotieff',
          benchmarkEligible: true,
          config: const ModelConfig(
            modelId: 'emotieff',
            variantId: 'emotieff_native_placeholder',
            version: 'native-placeholder-0.1',
            runtimeOptions: <String, Object?>{'backend': 'android_native'},
          ),
          factory: () => EmotiEffEmotionModel(),
        ),
      ];
}
