import 'dart:math' as math;

Map<String, double> normalizeScores(Map<String, double> rawScores) {
  if (rawScores.isEmpty) {
    return <String, double>{};
  }

  final double sum =
      rawScores.values.fold<double>(0.0, (double a, double b) => a + b);
  if (sum == 0) {
    final double uniform = 1.0 / rawScores.length;
    return rawScores
        .map((String key, double _) => MapEntry<String, double>(key, uniform));
  }

  return rawScores.map(
    (String key, double value) => MapEntry<String, double>(key, value / sum),
  );
}

Map<String, double> softmaxScores(Map<String, double> logits) {
  if (logits.isEmpty) {
    return <String, double>{};
  }

  final double maxLogit = logits.values.reduce(math.max);
  final Map<String, double> shifted = logits.map(
    (String key, double value) =>
        MapEntry<String, double>(key, math.exp(value - maxLogit)),
  );
  return normalizeScores(shifted);
}

int stableStringHash(String value) {
  int hash = 0;
  for (final int rune in value.runes) {
    hash = ((hash * 31) + rune) & 0x7fffffff;
  }
  return hash;
}

double roundTo(double value, int fractionDigits) {
  final num factor = math.pow(10, fractionDigits);
  return (value * factor).roundToDouble() / factor;
}
