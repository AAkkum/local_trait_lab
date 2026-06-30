import 'dart:convert';

import '../../analysis/analysis_result.dart';
import '../../core/types/emotion_label.dart';
import '../../core/utils/math_utils.dart';

class ParsedGemmaOutput {
  const ParsedGemmaOutput({
    required this.label,
    required this.scores,
  });

  final String label;
  final Map<String, double> scores;
}

class GemmaOutputParser {
  const GemmaOutputParser();

  ParsedGemmaOutput parse(String rawText) {
    final String candidate = _repairCandidate(rawText);
    final Object? decoded;
    try {
      decoded = jsonDecode(candidate);
    } catch (_) {
      throw const AnalysisFailure(
        type: AnalysisFailureType.invalidStructuredOutput,
        message: 'Gemma output is not valid JSON.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const AnalysisFailure(
        type: AnalysisFailureType.invalidStructuredOutput,
        message: 'Gemma output must be a JSON object.',
      );
    }

    final Object? labelValue = decoded['label'];
    final Object? scoresValue = decoded['scores'];
    if (labelValue is! String) {
      throw const AnalysisFailure(
        type: AnalysisFailureType.invalidStructuredOutput,
        message: 'Gemma output is missing label.',
      );
    }

    if (!isSupportedEmotionLabel(labelValue)) {
      throw AnalysisFailure(
        type: AnalysisFailureType.unsupportedLabelOutput,
        message: 'Gemma returned unsupported label $labelValue',
      );
    }

    final Map<String, double> rawScores = <String, double>{};
    if (scoresValue is Map<String, dynamic>) {
      for (final String label in kEmotionLabels) {
        final Object? value = scoresValue[label];
        if (value is num) {
          rawScores[label] = value.toDouble();
        } else {
          throw AnalysisFailure(
            type: AnalysisFailureType.invalidStructuredOutput,
            message: 'Missing score for $label',
          );
        }
      }
    } else {
      for (final String label in kEmotionLabels) {
        rawScores[label] = label == labelValue ? 1.0 : 0.0;
      }
    }

    final Map<String, double> normalized = normalizeScores(rawScores);
    return ParsedGemmaOutput(label: labelValue, scores: normalized);
  }

  String _repairCandidate(String rawText) {
    final String trimmed = rawText.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return trimmed;
    }

    final RegExp objectPattern = RegExp(r'\{[\s\S]*\}');
    final Match? match = objectPattern.firstMatch(trimmed);
    if (match != null) {
      return match.group(0)!;
    }
    return trimmed;
  }
}
