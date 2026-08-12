import '../core/types/emotion_label.dart';
import 'task_spec.dart';

class TaskCatalog {
  const TaskCatalog._();

  static const AnalysisTaskSpec emotionClassification = AnalysisTaskSpec(
    id: 'emotion_classification',
    displayName: 'Emotion Classification',
    acceptedInputTypes: <InputAssetType>[InputAssetType.image],
    labelSpace: LabelSpace(id: 'emotion7', labels: kEmotionLabels),
    outputSchema: OutputSchema(
      id: 'emotion_json_v1',
      allowedLabels: kEmotionLabels,
      requiresScoreVector: true,
      strictJson: true,
    ),
    promptTemplate: PromptTemplate(
      systemInstructions:
          'You are an emotion classification component. Output JSON only. Do not add prose, markdown, or explanations.',
      userTemplate:
          'Classify the dominant emotion in the image file {{file_name}}. Use exactly one label from: {{labels}}. '
          'Return JSON with keys "label" and "scores". The "scores" object must contain all seven labels with numeric confidences.',
    ),
  );

  static const AnalysisTaskSpec privacyInference = AnalysisTaskSpec(
    id: 'privacy_inference',
    displayName: 'Privacy Inference',
    acceptedInputTypes: <InputAssetType>[InputAssetType.image],
    outputSchema: OutputSchema(
      id: 'privacy_inference_json_v2',
      allowedLabels: <String>['low', 'medium', 'high', 'unknown'],
      requiresScoreVector: false,
      strictJson: true,
    ),
    promptTemplate: PromptTemplate(
      systemInstructions:
          'Return JSON only. Analyze a local phone file for a privacy study. Separate visible evidence from probabilistic owner-level inference. Do not identify people, present guesses as facts, or invent evidence.',
      userTemplate: 'Analyze {{file_name}} as a local phone file preview. '
          'Return one JSON object with exactly these keys: '
          '"content_summary" string of at most 30 words, '
          '"evidence" array of up to 3 directly observable short strings, '
          '"owner_inferences" array of up to 4 evidence-based possibilities about the owner, '
          '"private_signals" array of up to 3 personal details or categories the file may expose, '
          '"profiling_uses" array of up to 3 ways an app or third party could use the inferred information, '
          '"cross_file_value" string describing what this clue could reveal when combined with other files, '
          '"sensitivity" one of "low", "medium", "high", "unknown", '
          '"participant_headline" string of at most 10 words, '
          '"participant_message" string of at most 45 words. '
          'The participant fields must present only the strongest non-obvious owner-level inference, not merely describe the file. '
          'The presence of a file does not prove ownership, interest, identity, or intent. If evidence is weak, say that no strong personal inference is supported. '
          'Do not use canned examples or tailor the schema to a particular file type. No markdown, numbering, or extra keys.',
    ),
  );

  static const AnalysisTaskSpec privacyProfileSynthesis = AnalysisTaskSpec(
    id: 'privacy_profile_synthesis',
    displayName: 'Privacy Profile Synthesis',
    acceptedInputTypes: <InputAssetType>[InputAssetType.text],
    outputSchema: OutputSchema(
      id: 'privacy_profile_synthesis_json_v2',
      allowedLabels: <String>['profile'],
      requiresScoreVector: false,
      strictJson: true,
    ),
    promptTemplate: PromptTemplate(
      systemInstructions:
          'Return JSON only. Create a compact privacy profile from multiple file-level inferences. Select only strong, non-redundant, cross-file conclusions. Do not identify people, claim certainty, sensationalize, or invent evidence.',
      userTemplate:
          'Synthesize these per-file inferences into one fixed-size participant profile:\n\n{{input_text}}\n\n'
          'Return one JSON object with exactly these keys: '
          '"headline" string of at most 12 words, '
          '"profile" string of at most 65 words, '
          '"key_inferences" array of 2 or 3 strings, each at most 22 words, '
          '"privacy_implication" string of at most 35 words, '
          '"evidence_summary" array of up to 3 short strings for the research export, '
          '"uncertainty_note" string of at most 20 words for the research export. '
          'Output length must not increase with the number of files. Do not summarize files one by one or repeat the same idea in different sections. '
          'Prioritize conclusions that emerge from combining files and could change how a participant understands local profiling. '
          'Be interesting through specificity and evidence, not exaggeration. If evidence is weak, state a limited profile instead of filling space. '
          'No markdown, numbering prefixes, or extra keys.',
    ),
  );

  static const AnalysisTaskSpec privacyProfileRepair = AnalysisTaskSpec(
    id: 'privacy_profile_repair',
    displayName: 'Privacy Profile Repair',
    acceptedInputTypes: <InputAssetType>[InputAssetType.text],
    outputSchema: OutputSchema(
      id: 'privacy_profile_synthesis_json_v2',
      allowedLabels: <String>['profile'],
      requiresScoreVector: false,
      strictJson: true,
    ),
    promptTemplate: PromptTemplate(
      systemInstructions:
          'Return valid JSON only. Convert the supplied draft into the requested structure without adding unsupported claims.',
      userTemplate: 'Repair this draft profile:\n\n{{input_text}}\n\n'
          'Return exactly one JSON object with keys "headline", "profile", "key_inferences", "privacy_implication", "evidence_summary", and "uncertainty_note". '
          'Use double-quoted JSON strings. key_inferences must be an array of 2 or 3 strings and evidence_summary an array of up to 3 strings. '
          'All other values must be strings. No markdown, comments, trailing commas, or text outside the JSON object.',
    ),
  );
}
