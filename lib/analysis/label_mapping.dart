import '../core/types/emotion_label.dart';
import '../core/utils/math_utils.dart';
import 'analysis_result.dart';

class LabelMappingResult {
  const LabelMappingResult({
    required this.scores,
    required this.mappingApplied,
  });

  final Map<String, double> scores;
  final Map<String, String> mappingApplied;
}

LabelMappingResult mapScoresToStandardLabels({
  required Map<String, double> rawScores,
  required Map<String, String> backendToStandard,
  required bool logits,
}) {
  final Map<String, double> mapped = <String, double>{for (final String label in kEmotionLabels) label: 0.0};
  final Map<String, String> mappingApplied = <String, String>{};

  for (final MapEntry<String, double> entry in rawScores.entries) {
    final String? mappedLabel = backendToStandard[entry.key];
    if (mappedLabel == null || !isSupportedEmotionLabel(mappedLabel)) {
      throw AnalysisFailure(
        type: AnalysisFailureType.unsupportedLabelOutput,
        message: 'Unsupported backend label: ${entry.key}',
        details: <String, Object?>{'label': entry.key},
      );
    }
    mapped[mappedLabel] = entry.value;
    mappingApplied[entry.key] = mappedLabel;
  }

  final Map<String, double> normalized = logits ? softmaxScores(mapped) : normalizeScores(mapped);
  return LabelMappingResult(scores: normalized, mappingApplied: mappingApplied);
}
