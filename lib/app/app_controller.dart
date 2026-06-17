import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../analysis/analysis_model.dart';
import '../analysis/analysis_registry.dart';
import '../analysis/analysis_request.dart';
import '../analysis/analysis_result.dart';
import '../analysis/model_config.dart';
import '../analysis/task_catalog.dart';
import '../analysis/task_spec.dart';
import '../benchmark/benchmark_dataset.dart';
import '../benchmark/benchmark_runner.dart';
import '../data/dataset_import/dataset_import_service.dart';
import '../data/persistence/settings_repository.dart';
import 'package:flutter/foundation.dart';

class AppController extends ChangeNotifier {
  AppController({
    required List<RegisteredModel> registry,
    required SettingsRepository settingsRepository,
    DatasetImportService? datasetImportService,
    BenchmarkRunner? benchmarkRunner,
  })  : _registry = registry,
        _settingsRepository = settingsRepository,
        _datasetImportService = datasetImportService ?? const DatasetImportService(),
        _benchmarkRunner = benchmarkRunner ?? const BenchmarkRunner();

  final List<RegisteredModel> _registry;
  final SettingsRepository _settingsRepository;
  final DatasetImportService _datasetImportService;
  final BenchmarkRunner _benchmarkRunner;

  late AppSettings _settings;
  bool _initialized = false;
  String? _selectedModelId;
  InputAsset? _selectedImage;
  AnalysisResult? _lastResult;
  BenchmarkDataset? _benchmarkDataset;
  BenchmarkProgress? _benchmarkProgress;
  BenchmarkRunResult? _benchmarkResult;
  String? _errorMessage;
  bool _isBusy = false;
  bool _benchmarkCancelled = false;

  Future<void> initialize() async {
    _settings = await _settingsRepository.load();
    _selectedModelId ??= _registry.first.id;
    _initialized = true;
    notifyListeners();
  }

  bool get initialized => _initialized;
  List<RegisteredModel> get models => _registry;
  String get selectedModelId => _selectedModelId ?? _registry.first.id;
  RegisteredModel get selectedModel => _registry.firstWhere((RegisteredModel model) => model.id == selectedModelId);
  AppSettings get settings => _settings;
  ModelConfig configForModel(String modelId) {
    final RegisteredModel model = _registry.firstWhere((RegisteredModel entry) => entry.id == modelId);
    return _settings.modelConfigs[modelId] ?? model.config;
  }

  InputAsset? get selectedImage => _selectedImage;
  AnalysisResult? get lastResult => _lastResult;
  BenchmarkDataset? get benchmarkDataset => _benchmarkDataset;
  BenchmarkProgress? get benchmarkProgress => _benchmarkProgress;
  BenchmarkRunResult? get benchmarkResult => _benchmarkResult;
  String? get errorMessage => _errorMessage;
  bool get isBusy => _isBusy;

  void selectModel(String modelId) {
    _selectedModelId = modelId;
    notifyListeners();
  }

  Future<void> selectImageFromPickerResult(FilePickerResult result) async {
    final PlatformFile platformFile = result.files.single;
    List<int>? bytes = platformFile.bytes;
    if (bytes == null && platformFile.path != null) {
      bytes = await File(platformFile.path!).readAsBytes();
    }
    if (bytes == null) {
      _errorMessage = 'Failed to load selected image bytes.';
      notifyListeners();
      return;
    }
    _selectedImage = InputAsset(
      type: InputAssetType.image,
      uri: platformFile.path ?? platformFile.name,
      displayName: platformFile.name,
      mimeType: platformFile.extension == 'png' ? 'image/png' : 'image/jpeg',
      sizeBytes: bytes.length,
      bytes: bytes,
    );
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> runSingleImageAnalysis() async {
    if (_selectedImage == null) {
      _errorMessage = 'Select an image first.';
      notifyListeners();
      return;
    }
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    final RegisteredModel modelDescriptor = selectedModel;
    final AnalysisModel model = modelDescriptor.factory();
    try {
      final ModelConfig config = _settings.modelConfigs[modelDescriptor.id] ?? modelDescriptor.config;
      await model.load(config);
      _lastResult = await model.analyze(
        AnalysisRequest(
          taskId: TaskCatalog.emotionClassification.id,
          inputs: <InputAsset>[_selectedImage!],
          taskSpec: TaskCatalog.emotionClassification,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Single-image analysis failed: $error');
      debugPrint('$stackTrace');
      _lastResult = null;
      _errorMessage = error.toString();
    } finally {
      await model.unload();
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> importBenchmarkZip(String path) async {
    _benchmarkDataset = await _datasetImportService.loadFromZip(path);
    _benchmarkResult = null;
    _benchmarkProgress = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> importBenchmarkDirectory(String path) async {
    _benchmarkDataset = await _datasetImportService.loadFromDirectory(path);
    _benchmarkResult = null;
    _benchmarkProgress = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> runBenchmark() async {
    final BenchmarkDataset? dataset = _benchmarkDataset;
    if (dataset == null) {
      _errorMessage = 'Import a dataset first.';
      notifyListeners();
      return;
    }

    _isBusy = true;
    _benchmarkCancelled = false;
    _errorMessage = null;
    _benchmarkResult = null;
    _benchmarkProgress = const BenchmarkProgress(
      current: 0,
      total: 0,
      currentFile: '',
      averageLatencyMs: 0,
    );
    notifyListeners();

    final RegisteredModel modelDescriptor = selectedModel;
    final AnalysisModel model = modelDescriptor.factory();
    try {
      final ModelConfig config = _settings.modelConfigs[modelDescriptor.id] ?? modelDescriptor.config;
      await model.load(config);
      _benchmarkResult = await _benchmarkRunner.run(
        dataset: dataset,
        model: model,
        taskSpec: TaskCatalog.emotionClassification,
        onProgress: (BenchmarkProgress progress) {
          _benchmarkProgress = progress;
          notifyListeners();
        },
        shouldCancel: () => _benchmarkCancelled,
      );
    } catch (error, stackTrace) {
      debugPrint('Benchmark failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = error.toString();
    } finally {
      await model.unload();
      _isBusy = false;
      notifyListeners();
    }
  }

  void cancelBenchmark() {
    _benchmarkCancelled = true;
  }

  Future<void> updateModelConfig(String modelId, ModelConfig config) async {
    _settings = _settings.copyWith(
      modelConfigs: <String, ModelConfig>{..._settings.modelConfigs, modelId: config},
    );
    await _settingsRepository.save(_settings);
    notifyListeners();
  }

  Future<void> updateDebugMode(bool value) async {
    _settings = _settings.copyWith(debugMode: value);
    await _settingsRepository.save(_settings);
    notifyListeners();
  }

  Future<void> updateRawOutputRetention(bool value) async {
    _settings = _settings.copyWith(rawOutputRetention: value);
    await _settingsRepository.save(_settings);
    notifyListeners();
  }
}
