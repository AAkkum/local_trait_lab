import 'package:local_trait_lab/analysis/analysis_result.dart';
import 'package:local_trait_lab/analysis/label_mapping.dart';
import 'package:local_trait_lab/models/emotieff/emotieff_label_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps backend labels into standard emotion labels', () {
    final LabelMappingResult result = mapScoresToStandardLabels(
      rawScores: <String, double>{
        'anger': 3,
        'disgust': 1,
        'fear': 0,
        'joy': 5,
        'neutral': 2,
        'sadness': 1,
        'surprise': 0,
      },
      backendToStandard: kEmotiEffBackendToStandard,
      logits: true,
    );

    expect(result.scores.keys, containsAll(<String>['angry', 'happy', 'sad']));
    expect(result.mappingApplied['joy'], 'happy');
  });

  test('throws on unsupported backend label', () {
    expect(
      () => mapScoresToStandardLabels(
        rawScores: <String, double>{'mystery': 1.0},
        backendToStandard: kEmotiEffBackendToStandard,
        logits: false,
      ),
      throwsA(isA<AnalysisFailure>()),
    );
  });
}
