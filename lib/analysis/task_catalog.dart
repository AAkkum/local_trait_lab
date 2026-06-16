import '../core/types/emotion_label.dart';
import 'task_spec.dart';

class TaskCatalog {
  const TaskCatalog._();

  static final AnalysisTaskSpec emotionClassification = AnalysisTaskSpec(
    id: 'emotion_classification',
    displayName: 'Emotion Classification',
    acceptedInputTypes: const <InputAssetType>[InputAssetType.image],
    labelSpace: const LabelSpace(id: 'emotion7', labels: kEmotionLabels),
    outputSchema: const OutputSchema(
      id: 'emotion_json_v1',
      allowedLabels: kEmotionLabels,
      requiresScoreVector: true,
      strictJson: true,
    ),
    promptTemplate: const PromptTemplate(
      systemInstructions:
          'You are an emotion classification component. Output JSON only. Do not add prose, markdown, or explanations.',
      userTemplate:
          'Classify the dominant emotion in the image file {{file_name}}. Use exactly one label from: {{labels}}. '
          'Return JSON with keys "label" and "scores". The "scores" object must contain all seven labels with numeric confidences.',
    ),
  );
}
