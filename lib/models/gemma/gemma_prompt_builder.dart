import '../../analysis/task_spec.dart';
import '../../core/types/emotion_label.dart';

class GemmaPromptBuilder {
  const GemmaPromptBuilder();

  String buildEmotionPrompt({
    required AnalysisTaskSpec taskSpec,
    required InputAsset asset,
  }) {
    final PromptTemplate? template = taskSpec.promptTemplate;
    if (template == null) {
      throw StateError('Emotion task requires a prompt template.');
    }
    return template.build(<String, String>{
      'file_name': asset.displayName,
      'labels': kEmotionLabels.join(', '),
    });
  }
}
