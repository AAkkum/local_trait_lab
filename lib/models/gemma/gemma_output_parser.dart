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

  ParsedGemmaOutput parse(String rawText) => parseEmotion(rawText);

  ParsedGemmaOutput parseEmotion(String rawText) {
    final Map<String, dynamic> decoded = parseJsonObject(rawText);
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

  Map<String, dynamic> parseJsonObject(String rawText) {
    for (final String candidate in _jsonCandidates(rawText)) {
      try {
        final Object? decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        // Try the next deterministic candidate.
      }
    }

    throw const AnalysisFailure(
      type: AnalysisFailureType.invalidStructuredOutput,
      message: 'Gemma output is not valid JSON.',
    );
  }

  List<String> _jsonCandidates(String rawText) {
    final String trimmed = rawText.trim();
    final List<String> candidates = <String>[];
    if (trimmed.isNotEmpty) candidates.add(trimmed);

    final RegExp fencedPattern = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    );
    for (final Match match in fencedPattern.allMatches(trimmed)) {
      final String? content = match.group(1);
      if (content != null && content.trim().isNotEmpty) {
        candidates.add(content.trim());
      }
    }

    // Gemma sometimes echoes the input JSON before the final answer. Extract all
    // balanced objects and try the last ones first, which usually contain the
    // requested final output.
    candidates.addAll(_balancedJsonObjects(trimmed).reversed);

    return <String>{
      for (final String candidate in candidates)
        if (candidate.trim().isNotEmpty) candidate.trim(),
    }.toList();
  }

  List<String> _balancedJsonObjects(String text) {
    final List<String> objects = <String>[];
    int? start;
    int depth = 0;
    bool inString = false;
    bool escaping = false;

    for (int i = 0; i < text.length; i++) {
      final String char = text[i];
      if (inString) {
        if (escaping) {
          escaping = false;
        } else if (char == '\\') {
          escaping = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        start ??= i;
        depth++;
      } else if (char == '}' && start != null) {
        depth--;
        if (depth == 0) {
          objects.add(text.substring(start, i + 1));
          start = null;
        }
      }
    }
    return objects;
  }
}
