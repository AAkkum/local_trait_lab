import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../analysis/analysis_result.dart';
import '../analysis/task_spec.dart';
import '../core/types/emotion_label.dart';
import 'benchmark_dataset.dart';

abstract class DatasetSource {
  Future<BenchmarkDataset> load();
}

class ZipDatasetSource implements DatasetSource {
  ZipDatasetSource(this.zipFile);

  final File zipFile;

  @override
  Future<BenchmarkDataset> load() async {
    final List<int> bytes = await zipFile.readAsBytes();
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final Map<String, ArchiveFile> files = <String, ArchiveFile>{
      for (final ArchiveFile file in archive) file.name: file,
    };

    final ArchiveFile? labelsFile = files['labels.csv'] ?? files['dataset/labels.csv'];
    if (labelsFile == null) {
      throw const AnalysisFailure(
        type: AnalysisFailureType.invalidDataset,
        message: 'labels.csv missing from zip dataset.',
      );
    }

    final String csv = utf8.decode(labelsFile.content as List<int>);
    final List<LabeledExample> examples = <LabeledExample>[];
    for (final _CsvRow row in _parseLabels(csv)) {
      final ArchiveFile? image = files[row.file] ?? files['dataset/${row.file}'];
      if (image == null) {
        throw AnalysisFailure(
          type: AnalysisFailureType.invalidDataset,
          message: 'Image ${row.file} listed in labels.csv not found in zip.',
        );
      }
      examples.add(
        LabeledExample(
          relativePath: row.file,
          groundTruthLabel: row.label,
          image: InputAsset(
            type: InputAssetType.image,
            uri: 'zip://${zipFile.path}/${row.file}',
            displayName: p.basename(row.file),
            mimeType: _guessMimeType(row.file),
            sizeBytes: image.size,
            bytes: (image.content as List<int>),
          ),
        ),
      );
    }

    return BenchmarkDataset(
      name: p.basename(zipFile.path),
      examples: examples,
      sourceType: 'zip',
    );
  }
}

class TreeUriDatasetSource implements DatasetSource {
  TreeUriDatasetSource(this.directory);

  final Directory directory;

  @override
  Future<BenchmarkDataset> load() async {
    final File labelsFile = File(p.join(directory.path, 'labels.csv'));
    if (!await labelsFile.exists()) {
      throw const AnalysisFailure(
        type: AnalysisFailureType.invalidDataset,
        message: 'labels.csv missing from dataset directory.',
      );
    }

    final String csv = await labelsFile.readAsString();
    final List<LabeledExample> examples = <LabeledExample>[];
    for (final _CsvRow row in _parseLabels(csv)) {
      final File imageFile = File(p.join(directory.path, row.file));
      if (!await imageFile.exists()) {
        throw AnalysisFailure(
          type: AnalysisFailureType.invalidDataset,
          message: 'Image ${row.file} listed in labels.csv not found in directory.',
        );
      }
      final List<int> bytes = await imageFile.readAsBytes();
      examples.add(
        LabeledExample(
          relativePath: row.file,
          groundTruthLabel: row.label,
          image: InputAsset(
            type: InputAssetType.image,
            uri: imageFile.uri.toString(),
            displayName: p.basename(imageFile.path),
            mimeType: _guessMimeType(imageFile.path),
            sizeBytes: bytes.length,
            bytes: bytes,
          ),
        ),
      );
    }

    return BenchmarkDataset(
      name: p.basename(directory.path),
      examples: examples,
      sourceType: 'directory',
    );
  }
}

class _CsvRow {
  const _CsvRow(this.file, this.label);
  final String file;
  final String label;
}

List<_CsvRow> _parseLabels(String csv) {
  final List<String> lines = const LineSplitter().convert(csv).where((String line) => line.trim().isNotEmpty).toList();
  if (lines.isEmpty) {
    throw const AnalysisFailure(
      type: AnalysisFailureType.invalidDataset,
      message: 'labels.csv is empty.',
    );
  }

  final String header = lines.first.trim();
  if (header != 'file,label') {
    throw AnalysisFailure(
      type: AnalysisFailureType.invalidDataset,
      message: 'labels.csv header must be file,label but was $header',
    );
  }

  return lines.skip(1).map((_CsvRow Function(String) build) {
    return build;
  }((String line) {
    final List<String> parts = line.split(',');
    if (parts.length != 2) {
      throw AnalysisFailure(
        type: AnalysisFailureType.invalidDataset,
        message: 'Invalid labels.csv row: $line',
      );
    }
    final String label = parts[1].trim();
    if (!isSupportedEmotionLabel(label)) {
      throw AnalysisFailure(
        type: AnalysisFailureType.invalidDataset,
        message: 'Unsupported ground-truth label: $label',
      );
    }
    return _CsvRow(parts[0].trim(), label);
  })).toList();
}

String _guessMimeType(String filePath) {
  final String lower = filePath.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'application/octet-stream';
}
