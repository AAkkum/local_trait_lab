import 'package:local_trait_lab/models/gemma/gemma_output_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const GemmaOutputParser parser = GemmaOutputParser();

  test('accepts valid JSON payload', () {
    final ParsedGemmaOutput parsed = parser.parse('''
    {
      "label": "happy",
      "scores": {
        "angry": 0.1,
        "disgust": 0.1,
        "fear": 0.1,
        "happy": 0.4,
        "neutral": 0.1,
        "sad": 0.1,
        "surprise": 0.1
      }
    }
    ''');

    expect(parsed.label, 'happy');
    expect(parsed.scores['happy'], greaterThan(0));
  });

  test('repairs surrounding prose once', () {
    final ParsedGemmaOutput parsed = parser.parse('Answer: {"label":"neutral","scores":{"angry":0.1,"disgust":0.1,"fear":0.1,"happy":0.1,"neutral":0.4,"sad":0.1,"surprise":0.1}}');
    expect(parsed.label, 'neutral');
  });

  test('rejects malformed output', () {
    expect(() => parser.parse('not json'), throwsA(anything));
  });
}
