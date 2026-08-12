import 'dart:convert';

import '../../analysis/task_spec.dart';
import '../../core/types/emotion_label.dart';
import '../../core/utils/math_utils.dart';
import 'gemma_runtime.dart';

class GemmaMockRuntime implements GemmaRuntime {
  const GemmaMockRuntime();

  @override
  Future<void> load() async {}

  @override
  Future<void> close() async {}

  @override
  Future<GemmaRuntimeOutput> runTask({
    required AnalysisTaskSpec taskSpec,
    required InputAsset asset,
    required String prompt,
  }) async {
    final int hash = stableStringHash('${asset.displayName}:${taskSpec.id}');
    if (taskSpec.id == 'privacy_profile_synthesis' ||
        taskSpec.id == 'privacy_profile_repair') {
      final String json = jsonEncode(<String, Object?>{
        'headline': 'Your files become a behavioral profile',
        'profile':
            'The selected files suggest a technically oriented person whose saved material may reveal current learning, practical plans, and purchase interests. Together, these clues expose more than any single document.',
        'key_inferences': <String>[
          'Technical documents may reveal an education or career direction.',
          'Saved specifications may indicate active planning or purchase intent.',
          'Repeated topics could identify priorities that currently matter to the user.',
        ],
        'privacy_implication':
            'An app could use these local clues to classify interests and intent without uploading the original files.',
        'evidence_summary': <String>[
          'Recurring technical subject matter',
          'Locally saved reference material',
          'Documents connected to planning or decisions',
        ],
        'uncertainty_note':
            'Probabilistic profile; file ownership and intent remain uncertain.',
      });
      return GemmaRuntimeOutput(
        rawText: json,
        latencyMs: 300 + (hash % 200),
        runtimeBackend: 'mock',
        debug: <String, Object?>{
          'prompt_preview': prompt.substring(0, prompt.length.clamp(0, 160)),
        },
      );
    }

    if (taskSpec.id == 'privacy_inference') {
      final String sensitivity = switch (hash % 3) {
        0 => 'low',
        1 => 'medium',
        _ => 'high',
      };
      final String json = jsonEncode(<String, Object?>{
        'content_summary':
            'The selected file appears to contain personal context that could be used for profiling.',
        'evidence': <String>[
          'objects, text, or setting visible in the selected file',
          'context available without uploading the original file',
        ],
        'owner_inferences': <String>[
          'The topic may relate to a current interest, task, or decision.',
          'Keeping the file may indicate that its information is useful to the owner.',
        ],
        'private_signals': <String>[
          'Possible activity or interest context',
          'Possible planning or decision context',
        ],
        'profiling_uses': <String>[
          'Classify interests for personalization or targeting',
          'Connect repeated topics into a persistent profile',
        ],
        'cross_file_value':
            'Related files could distinguish a passing reference from a repeated interest or active plan.',
        'sensitivity': sensitivity,
        'participant_headline': 'This file reveals more than its contents',
        'participant_message':
            'Its topic and why it was kept may suggest a current interest, task, or decision that another app could add to a longer-term profile.',
      });
      return GemmaRuntimeOutput(
        rawText: json,
        latencyMs: 250 + (hash % 150),
        runtimeBackend: 'mock',
        debug: <String, Object?>{
          'prompt_preview': prompt.substring(0, prompt.length.clamp(0, 160)),
        },
      );
    }

    final int predictedIndex = hash % kEmotionLabels.length;
    final Map<String, double> scores = <String, double>{};
    for (int i = 0; i < kEmotionLabels.length; i++) {
      scores[kEmotionLabels[i]] =
          i == predictedIndex ? 3.0 : ((hash + i) % 10) / 20.0;
    }

    final Map<String, double> normalized = softmaxScores(scores);
    final String label = kEmotionLabels[predictedIndex];
    final String json = jsonEncode(<String, Object?>{
      'label': label,
      'scores': <String, double>{
        'angry': roundTo(normalized['angry']!, 6),
        'disgust': roundTo(normalized['disgust']!, 6),
        'fear': roundTo(normalized['fear']!, 6),
        'happy': roundTo(normalized['happy']!, 6),
        'neutral': roundTo(normalized['neutral']!, 6),
        'sad': roundTo(normalized['sad']!, 6),
        'surprise': roundTo(normalized['surprise']!, 6),
      },
    });

    return GemmaRuntimeOutput(
      rawText: json,
      latencyMs: 120 + (hash % 80),
      runtimeBackend: 'mock',
      debug: <String, Object?>{
        'prompt_preview': prompt.substring(0, prompt.length.clamp(0, 160)),
      },
    );
  }
}
