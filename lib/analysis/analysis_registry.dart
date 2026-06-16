import 'analysis_model.dart';
import 'model_config.dart';
import '../models/emotieff/emotieff_analysis_model.dart';
import '../models/gemma/gemma_analysis_model.dart';

typedef AnalysisModelFactory = AnalysisModel Function();

class ModelVariant {
  const ModelVariant({
    required this.id,
    required this.displayName,
    required this.version,
    this.expectedFileName,
    this.notes,
  });

  final String id;
  final String displayName;
  final String version;
  final String? expectedFileName;
  final String? notes;
}

class RuntimeOption {
  const RuntimeOption({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

class RegisteredModel {
  const RegisteredModel({
    required this.id,
    required this.displayName,
    required this.family,
    required this.config,
    required this.benchmarkEligible,
    required this.variants,
    required this.runtimeOptions,
    required this.factory,
  });

  final String id;
  final String displayName;
  final String family;
  final ModelConfig config;
  final bool benchmarkEligible;
  final List<ModelVariant> variants;
  final List<RuntimeOption> runtimeOptions;
  final AnalysisModelFactory factory;

  ModelVariant variantById(String variantId) {
    return variants.firstWhere(
      (ModelVariant variant) => variant.id == variantId,
      orElse: () => variants.first,
    );
  }
}

class AnalysisRegistry {
  const AnalysisRegistry._();

  static List<RegisteredModel> buildDefaultModels() => <RegisteredModel>[
        RegisteredModel(
          id: 'gemma',
          displayName: 'Gemma',
          family: 'gemma',
          benchmarkEligible: true,
          variants: const <ModelVariant>[
            ModelVariant(id: 'gemma_e2b', displayName: 'Gemma 4 E2B', version: 'mock-0.1'),
            ModelVariant(id: 'gemma_e4b', displayName: 'Gemma 4 E4B', version: 'mock-0.1'),
          ],
          runtimeOptions: const <RuntimeOption>[
            RuntimeOption(id: 'mock', displayName: 'mock'),
          ],
          config: const ModelConfig(
            modelId: 'gemma',
            variantId: 'gemma_e2b',
            version: 'mock-0.1',
            runtimeOptions: <String, Object?>{'backend': 'mock'},
          ),
          factory: () => GemmaAnalysisModel(),
        ),
        RegisteredModel(
          id: 'emotieff',
          displayName: 'EmotiEff',
          family: 'emotieff',
          benchmarkEligible: true,
          variants: const <ModelVariant>[
            ModelVariant(
              id: 'enet_b0_8_best_afew',
              displayName: 'EfficientNet B0 8-class AFEW',
              version: 'emotieff-v1.1.1',
              expectedFileName: 'enet_b0_8_best_afew.onnx',
              notes: 'Good first ONNX target: small model, about 16 MB in the EmotiEff table.',
            ),
            ModelVariant(
              id: 'enet_b0_8_best_vgaf',
              displayName: 'EfficientNet B0 8-class VGAF',
              version: 'emotieff-v1.1.1',
              expectedFileName: 'enet_b0_8_best_vgaf.onnx',
            ),
            ModelVariant(
              id: 'enet_b0_8_va_mtl',
              displayName: 'EfficientNet B0 8-class VA/MTL',
              version: 'emotieff-v1.1.1',
              expectedFileName: 'enet_b0_8_va_mtl.onnx',
            ),
            ModelVariant(
              id: 'enet_b2_7',
              displayName: 'EfficientNet B2 7-class',
              version: 'emotieff-v1.1.1',
              expectedFileName: 'enet_b2_7.onnx',
              notes: 'Higher reported accuracy but slower and larger than B0 models.',
            ),
            ModelVariant(
              id: 'enet_b2_8',
              displayName: 'EfficientNet B2 8-class',
              version: 'emotieff-v1.1.1',
              expectedFileName: 'enet_b2_8.onnx',
            ),
            ModelVariant(
              id: 'mbf_va_mtl',
              displayName: 'MobileFaceNet VA/MTL',
              version: 'emotieff-v1.1.1',
              expectedFileName: 'mbf_va_mtl.onnx',
            ),
            ModelVariant(
              id: 'mobilevit_va_mtl',
              displayName: 'MobileViT VA/MTL',
              version: 'emotieff-v1.1.1',
              expectedFileName: 'mobilevit_va_mtl.onnx',
            ),
          ],
          runtimeOptions: const <RuntimeOption>[
            RuntimeOption(id: 'mock', displayName: 'mock'),
            RuntimeOption(id: 'onnx', displayName: 'ONNX Runtime'),
          ],
          config: const ModelConfig(
            modelId: 'emotieff',
            variantId: 'enet_b2_7',
            version: 'emotieff-v1.1.1',
            runtimeOptions: <String, Object?>{'backend': 'mock'},
          ),
          factory: () => EmotiEffEmotionModel(),
        ),
      ];
}
