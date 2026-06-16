import '../analysis/task_spec.dart';

class LabeledExample {
  const LabeledExample({
    required this.relativePath,
    required this.groundTruthLabel,
    required this.image,
  });

  final String relativePath;
  final String groundTruthLabel;
  final InputAsset image;
}

class BenchmarkDataset {
  const BenchmarkDataset({
    required this.name,
    required this.examples,
    required this.sourceType,
  });

  final String name;
  final List<LabeledExample> examples;
  final String sourceType;
}
