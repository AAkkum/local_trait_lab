import 'dart:io';

import '../../benchmark/benchmark_dataset.dart';
import '../../benchmark/dataset_source.dart';

class DatasetImportService {
  const DatasetImportService();

  Future<BenchmarkDataset> loadFromZip(String zipPath) async {
    return ZipDatasetSource(File(zipPath)).load();
  }

  Future<BenchmarkDataset> loadFromDirectory(String directoryPath) async {
    return TreeUriDatasetSource(Directory(directoryPath)).load();
  }
}
