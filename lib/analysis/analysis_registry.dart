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
            ModelVariant(
              id: 'gemma_e2b',
              displayName: 'Gemma 4 E2B',
              version: 'gemma4-litert-local',
              expectedFileName: 'gemma-4-E2B-it.litertlm',
              notes:
                  'Local multimodal Gemma runtime through LiteRT-LM. Import the downloaded E2B model file.',
            ),
            ModelVariant(
              id: 'gemma_e4b',
              displayName: 'Gemma 4 E4B',
              version: 'gemma4-litert-local',
              expectedFileName: 'gemma-4-E4B-it.litertlm',
              notes:
                  'Larger local multimodal Gemma variant. Use after E2B works.',
            ),
          ],
          runtimeOptions: const <RuntimeOption>[
            RuntimeOption(id: 'mock', displayName: 'mock'),
            RuntimeOption(id: 'litert_lm', displayName: 'LiteRT-LM'),
          ],
          config: const ModelConfig(
            modelId: 'gemma',
            variantId: 'gemma_e2b',
            version: 'gemma4-litert-local',
            runtimeOptions: <String, Object?>{
              'backend': 'litert_lm',
              'max_tokens': 1024,
              'temperature': 0.0,
              'top_k': 1,
              'top_p': 0.95,
              'text_backend': 'gpu',
              'vision_backend': 'gpu',
            },
            assetConfig: <String, Object?>{
              'task_config': 'assets/gemma_tasks/emotion_classification.json',
              'asset_path':
                  '/data/user/0/com.atabey.local_trait_lab/app_flutter/models/gemma-4-E2B-it.litertlm',
            },
          ),
          factory: () => GemmaAnalysisModel(),
        ),
        RegisteredModel(
          id: 'resemotenet',
          displayName: 'ResEmoteNet',
          family: 'resemotenet',
          benchmarkEligible: true,
          variants: const <ModelVariant>[
            ModelVariant(
              id: 'resemotenet_kaggle_224',
              displayName: 'ResEmoteNet Kaggle 224',
              version: 'resemotenet-kaggle-local',
              expectedFileName: 'ResEmoteNetKaggle_224x224.onnx',
              notes:
                  'Kaggle checkpoint trained on RAF-DB, FER2013, and AffectNet. Uses 224x224 ImageNet preprocessing.',
            ),
            ModelVariant(
              id: 'resemotenet_bs32',
              displayName: 'ResEmoteNet BS32 reproduction',
              version: 'resemotenet-kaggle-local',
              expectedFileName: 'ResEmoteNetBS32_64x64.onnx',
              notes:
                  'Third-party reproduction checkpoint. Empirically works only with 64x64 ImageNet preprocessing.',
            ),
          ],
          runtimeOptions: const <RuntimeOption>[
            RuntimeOption(id: 'mock', displayName: 'mock'),
            RuntimeOption(id: 'onnx', displayName: 'ONNX Runtime'),
          ],
          config: const ModelConfig(
            modelId: 'resemotenet',
            variantId: 'resemotenet_kaggle_224',
            version: 'resemotenet-onnx-local',
            runtimeOptions: <String, Object?>{'backend': 'mock'},
          ),
          factory: () => EmotiEffEmotionModel(),
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
              notes:
                  'Good first ONNX target: small model, about 16 MB in the EmotiEff table.',
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
              notes:
                  'Higher reported accuracy but slower and larger than B0 models.',
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
