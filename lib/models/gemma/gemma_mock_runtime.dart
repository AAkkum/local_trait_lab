import '../../core/types/emotion_label.dart';
import '../../core/utils/math_utils.dart';
import '../../analysis/task_spec.dart';
import 'gemma_runtime.dart';

class GemmaMockRuntime implements GemmaRuntime {
  const GemmaMockRuntime();

  @override
  Future<GemmaRuntimeOutput> runTask({
    required AnalysisTaskSpec taskSpec,
    required InputAsset asset,
    required String prompt,
  }) async {
    final int hash = stableStringHash('${asset.displayName}:${taskSpec.id}');
    final int predictedIndex = hash % kEmotionLabels.length;
    final Map<String, double> scores = <String, double>{};
    for (int i = 0; i < kEmotionLabels.length; i++) {
      scores[kEmotionLabels[i]] = i == predictedIndex ? 3.0 : ((hash + i) % 10) / 20.0;
    }

    final Map<String, double> normalized = softmaxScores(scores);
    final String label = kEmotionLabels[predictedIndex];
    final String json = '''
{
  "label": "$label",
  "scores": {
    "angry": ${roundTo(normalized['angry']!, 6)},
    "disgust": ${roundTo(normalized['disgust']!, 6)},
    "fear": ${roundTo(normalized['fear']!, 6)},
    "happy": ${roundTo(normalized['happy']!, 6)},
    "neutral": ${roundTo(normalized['neutral']!, 6)},
    "sad": ${roundTo(normalized['sad']!, 6)},
    "surprise": ${roundTo(normalized['surprise']!, 6)}
  }
}
''';

    return GemmaRuntimeOutput(
      rawText: json,
      latencyMs: 120 + (hash % 80),
      runtimeBackend: 'mock',
      debug: <String, Object?>{'prompt_preview': prompt.substring(0, prompt.length.clamp(0, 160))},
    );
  }
}
