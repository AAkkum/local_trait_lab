import '../../core/utils/math_utils.dart';
import '../../analysis/task_spec.dart';
import 'emotieff_runtime.dart';

class EmotiEffMockRuntime implements EmotiEffRuntime {
  const EmotiEffMockRuntime();

  static const List<String> _backendLabels = <String>[
    'anger',
    'disgust',
    'fear',
    'joy',
    'neutral',
    'sadness',
    'surprise',
  ];

  @override
  Future<EmotiEffRuntimeOutput> classifyEmotion({
    required InputAsset asset,
  }) async {
    final int hash = stableStringHash(asset.displayName);
    final int predictedIndex = hash % _backendLabels.length;
    final Map<String, double> logits = <String, double>{};
    for (int i = 0; i < _backendLabels.length; i++) {
      logits[_backendLabels[i]] = i == predictedIndex ? 2.7 : ((hash + i * 7) % 12) / 8.0;
    }

    return EmotiEffRuntimeOutput(
      rawScores: logits,
      latencyMs: 40 + (hash % 30),
      runtimeBackend: 'mock',
      debug: <String, Object?>{'backend_labels': _backendLabels},
    );
  }
}
