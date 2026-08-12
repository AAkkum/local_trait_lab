import '../../analysis/task_spec.dart';
import '../../core/types/emotion_label.dart';

class GemmaPromptBuilder {
  const GemmaPromptBuilder();

  String buildPrompt({
    required AnalysisTaskSpec taskSpec,
    required InputAsset asset,
    PromptTemplate? overrideTemplate,
  }) {
    final PromptTemplate? template =
        overrideTemplate ?? taskSpec.promptTemplate;
    if (template == null) {
      throw StateError('Gemma task ${taskSpec.id} requires a prompt template.');
    }
    return template.build(<String, String>{
      'file_name': asset.displayName,
      'input_type': asset.type.name,
      'input_text': asset.text ?? '',
      'labels': kEmotionLabels.join(', '),
    });
  }
}
