import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

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
import '../platform/android/pdf_page_renderer.dart';

class PreparedStudyImage {
  const PreparedStudyImage({
    required this.bytes,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final int? width;
  final int? height;
}

class PrivacyStudyFile {
  const PrivacyStudyFile({
    required this.id,
    required this.originalName,
    required this.originalMimeType,
    required this.analysisAsset,
    required this.note,
  });

  final String id;
  final String originalName;
  final String originalMimeType;
  final InputAsset analysisAsset;
  final String note;
}

class PrivacyStudyResult {
  const PrivacyStudyResult({required this.file, required this.result});

  final PrivacyStudyFile file;
  final AnalysisResult result;
}

class ReactionEmotionSample {
  const ReactionEmotionSample({
    required this.timestamp,
    required this.stage,
    required this.event,
    this.modelId,
    this.label,
    this.confidence,
    this.failureReason,
  });

  final DateTime timestamp;
  final String stage;
  final String event;
  final String? modelId;
  final String? label;
  final double? confidence;
  final String? failureReason;

  Map<String, Object?> toJson() => <String, Object?>{
        'timestamp': timestamp.toIso8601String(),
        'stage': stage,
        'event': event,
        'model_id': modelId,
        'label': label,
        'confidence': confidence,
        'failure_reason': failureReason,
      };
}

class AggregatePrivacyProfile {
  const AggregatePrivacyProfile({
    required this.analyzedFiles,
    required this.highSensitivityCount,
    required this.mediumSensitivityCount,
    required this.ownerInferences,
    required this.privateSignals,
    required this.profilingUses,
  });

  final int analyzedFiles;
  final int highSensitivityCount;
  final int mediumSensitivityCount;
  final List<String> ownerInferences;
  final List<String> privateSignals;
  final List<String> profilingUses;

  Map<String, Object?> toJson() => <String, Object?>{
        'analyzed_files': analyzedFiles,
        'high_sensitivity_count': highSensitivityCount,
        'medium_sensitivity_count': mediumSensitivityCount,
        'owner_inferences': ownerInferences,
        'private_signals': privateSignals,
        'profiling_uses': profilingUses,
      };
}

class AppController extends ChangeNotifier {
  static const String _gemmaE2BFileName = 'gemma-4-E2B-it.litertlm';
  static const String _gemmaE2BDownloadUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true';
  static const int _minimumGemmaModelBytes = 1024 * 1024 * 1024;
  static const MethodChannel _nativeChannel =
      MethodChannel('local_trait_lab/gemma_litert');

  AppController({
    required List<RegisteredModel> registry,
    required SettingsRepository settingsRepository,
    DatasetImportService? datasetImportService,
    BenchmarkRunner? benchmarkRunner,
  })  : _registry = registry,
        _settingsRepository = settingsRepository,
        _datasetImportService =
            datasetImportService ?? const DatasetImportService(),
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
  final List<PrivacyStudyFile> _privacyFiles = <PrivacyStudyFile>[];
  final List<PrivacyStudyResult> _privacyResults = <PrivacyStudyResult>[];
  final List<ReactionEmotionSample> _reactionSamples =
      <ReactionEmotionSample>[];
  AnalysisResult? _synthesizedPrivacyProfile;
  int _privacyProgress = 0;
  String? _errorMessage;
  bool _isBusy = false;
  bool _benchmarkCancelled = false;
  bool _privacyCancelled = false;
  bool _gemmaModelReady = false;
  bool _isGemmaDownloading = false;
  bool _isGemmaDownloadPaused = false;
  double? _gemmaDownloadProgress;
  String? _gemmaDownloadStatus;
  Timer? _gemmaDownloadPollTimer;
  bool _isPollingGemmaDownload = false;

  Future<void> initialize() async {
    _settings = await _settingsRepository.load();
    await _refreshGemmaModelStatus(notify: false);
    _selectedModelId ??= _registry.first.id;
    _initialized = true;
    notifyListeners();
  }

  bool get initialized => _initialized;
  List<RegisteredModel> get models => _registry;
  String get selectedModelId => _selectedModelId ?? _registry.first.id;
  RegisteredModel get selectedModel => _registry
      .firstWhere((RegisteredModel model) => model.id == selectedModelId);
  AppSettings get settings => _settings;
  ModelConfig configForModel(String modelId) {
    final RegisteredModel model =
        _registry.firstWhere((RegisteredModel entry) => entry.id == modelId);
    return _settings.modelConfigs[modelId] ?? model.config;
  }

  InputAsset? get selectedImage => _selectedImage;
  AnalysisResult? get lastResult => _lastResult;
  BenchmarkDataset? get benchmarkDataset => _benchmarkDataset;
  BenchmarkProgress? get benchmarkProgress => _benchmarkProgress;
  BenchmarkRunResult? get benchmarkResult => _benchmarkResult;
  List<PrivacyStudyFile> get privacyFiles =>
      List<PrivacyStudyFile>.unmodifiable(_privacyFiles);
  List<PrivacyStudyResult> get privacyResults =>
      List<PrivacyStudyResult>.unmodifiable(_privacyResults);
  List<ReactionEmotionSample> get reactionSamples =>
      List<ReactionEmotionSample>.unmodifiable(_reactionSamples);
  AggregatePrivacyProfile get aggregatePrivacyProfile =>
      _buildAggregatePrivacyProfile();
  AnalysisResult? get synthesizedPrivacyProfile => _synthesizedPrivacyProfile;
  String? _privacyStatusMessage;

  int get privacyProgress => _privacyProgress;
  String? get privacyStatusMessage => _privacyStatusMessage;
  int get pendingPrivacyFileCount => _privacyFiles
      .where((PrivacyStudyFile file) => !_hasPrivacyResult(file.id))
      .length;
  String? get errorMessage => _errorMessage;
  bool get isBusy => _isBusy;
  bool get gemmaModelReady => _gemmaModelReady;
  bool get isGemmaDownloading => _isGemmaDownloading;
  bool get isGemmaDownloadPaused => _isGemmaDownloadPaused;
  double? get gemmaDownloadProgress => _gemmaDownloadProgress;
  String? get gemmaDownloadStatus => _gemmaDownloadStatus;

  @override
  void dispose() {
    _gemmaDownloadPollTimer?.cancel();
    super.dispose();
  }

  void selectModel(String modelId) {
    _selectedModelId = modelId;
    notifyListeners();
  }

  Future<void> selectImageFromPickerResult(FilePickerResult result) async {
    final PlatformFile platformFile = result.files.single;
    final List<int>? bytes = await _loadPlatformFileBytes(platformFile);
    if (bytes == null) {
      _errorMessage = 'Failed to load selected image bytes.';
      notifyListeners();
      return;
    }
    _selectedImage = InputAsset(
      type: InputAssetType.image,
      uri: platformFile.path ?? platformFile.name,
      displayName: platformFile.name,
      mimeType: _imageMimeType(platformFile.extension),
      sizeBytes: bytes.length,
      bytes: bytes,
    );
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> selectPrivacyFilesFromPickerResult(
      FilePickerResult result) async {
    _isBusy = true;
    _errorMessage = null;
    _privacyStatusMessage = 'Preparing selected files on device';
    notifyListeners();

    final List<String> failedFiles = <String>[];
    try {
      for (final PlatformFile platformFile in result.files) {
        final String extension = (platformFile.extension ?? '').toLowerCase();
        final String fileId = _privacyFileIdFromMetadata(platformFile);
        if (_privacyFiles.any((PrivacyStudyFile file) => file.id == fileId)) {
          continue;
        }

        _privacyStatusMessage = 'Preparing ${platformFile.name}';
        notifyListeners();

        try {
          if (extension == 'pdf') {
            final RenderedPdfPage page = await _renderPdfPreview(platformFile);
            final PreparedStudyImage prepared =
                _prepareStudyImage(page.pngBytes);
            _privacyFiles.add(
              PrivacyStudyFile(
                id: fileId,
                originalName: platformFile.name,
                originalMimeType: 'application/pdf',
                analysisAsset: InputAsset(
                  type: InputAssetType.image,
                  uri: '${platformFile.path ?? platformFile.name}#page=1',
                  displayName: '${platformFile.name} page 1 preview',
                  mimeType: 'image/jpeg',
                  sizeBytes: prepared.bytes.length,
                  bytes: prepared.bytes,
                  width: prepared.width ?? page.width,
                  height: prepared.height ?? page.height,
                ),
                note:
                    'PDF support in this prototype renders and analyzes the first page locally.',
              ),
            );
          } else {
            final List<int>? rawBytes =
                await _loadPlatformFileBytes(platformFile);
            if (rawBytes == null || rawBytes.isEmpty) {
              failedFiles.add(platformFile.name);
              continue;
            }
            final PreparedStudyImage prepared = _prepareStudyImage(rawBytes);
            _privacyFiles.add(
              PrivacyStudyFile(
                id: fileId,
                originalName: platformFile.name,
                originalMimeType: _imageMimeType(extension),
                analysisAsset: InputAsset(
                  type: InputAssetType.image,
                  uri: platformFile.path ?? platformFile.name,
                  displayName: platformFile.name,
                  mimeType: 'image/jpeg',
                  sizeBytes: prepared.bytes.length,
                  bytes: prepared.bytes,
                  width: prepared.width,
                  height: prepared.height,
                ),
                note: 'Image file analyzed directly on device.',
              ),
            );
          }
        } catch (error, stackTrace) {
          debugPrint('Preparing ${platformFile.name} failed: $error');
          debugPrint('$stackTrace');
          failedFiles.add(platformFile.name);
        }

        _privacyProgress = _privacyResults.length;
        notifyListeners();
      }
      _privacyProgress = _privacyResults.length;
      _synthesizedPrivacyProfile = null;
      _privacyStatusMessage = null;
      if (failedFiles.isNotEmpty) {
        _errorMessage =
            'Could not prepare ${failedFiles.length} file(s): ${failedFiles.take(3).join(', ')}${failedFiles.length > 3 ? ', ...' : ''}';
      }
    } finally {
      _privacyStatusMessage = null;
      _isBusy = false;
      notifyListeners();
    }
  }

  void clearPrivacyStudy() {
    _privacyFiles.clear();
    _privacyResults.clear();
    _reactionSamples.clear();
    _synthesizedPrivacyProfile = null;
    _privacyProgress = 0;
    _privacyCancelled = false;
    _privacyStatusMessage = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> runPrivacyInferenceBatch() async {
    if (_privacyFiles.isEmpty) {
      _errorMessage = 'Select images or PDFs first.';
      notifyListeners();
      return;
    }

    _isBusy = true;
    _privacyCancelled = false;
    _privacyProgress = _privacyResults.length;
    _privacyStatusMessage =
        'Loading Gemma into memory. This can take about a minute on first run.';
    _errorMessage = null;
    notifyListeners();

    final RegisteredModel modelDescriptor =
        _registry.firstWhere((RegisteredModel model) => model.id == 'gemma');
    final AnalysisModel model = modelDescriptor.factory();
    try {
      final ModelConfig config =
          _settings.modelConfigs[modelDescriptor.id] ?? modelDescriptor.config;
      await model.load(config);
      _privacyStatusMessage = 'Gemma loaded. Analyzing pending files locally.';
      notifyListeners();
      for (int i = 0; i < _privacyFiles.length; i++) {
        if (_privacyCancelled) break;
        final PrivacyStudyFile file = _privacyFiles[i];
        if (_hasPrivacyResult(file.id)) {
          continue;
        }
        _privacyStatusMessage =
            'Analyzing ${file.originalName} (${_privacyResults.length + 1}/${_privacyFiles.length})';
        notifyListeners();
        final AnalysisResult result = await model.analyze(
          AnalysisRequest(
            taskId: TaskCatalog.privacyInference.id,
            inputs: <InputAsset>[file.analysisAsset],
            taskSpec: TaskCatalog.privacyInference,
            options: <String, Object?>{
              'original_file': file.originalName,
              'original_mime_type': file.originalMimeType,
            },
          ),
        );
        _privacyResults.add(PrivacyStudyResult(file: file, result: result));
        _synthesizedPrivacyProfile = null;
        _privacyProgress = _privacyResults.length;
        notifyListeners();
      }
    } catch (error, stackTrace) {
      debugPrint('Privacy inference failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = error.toString();
    } finally {
      _privacyStatusMessage = _privacyCancelled ? 'Run cancelled.' : null;
      await model.unload();
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> synthesizePrivacyProfile() async {
    if (_privacyResults.isEmpty) {
      _errorMessage = 'Run at least one file analysis first.';
      notifyListeners();
      return false;
    }
    if (_synthesizedPrivacyProfile != null) return true;

    _isBusy = true;
    _privacyStatusMessage =
        'Creating one combined profile from all file inferences.';
    _errorMessage = null;
    notifyListeners();

    final RegisteredModel modelDescriptor =
        _registry.firstWhere((RegisteredModel model) => model.id == 'gemma');
    final AnalysisModel model = modelDescriptor.factory();
    bool succeeded = false;
    try {
      final ModelConfig config =
          _settings.modelConfigs[modelDescriptor.id] ?? modelDescriptor.config;
      await model.load(config);
      final String synthesisInput = _buildPrivacyProfileSynthesisInput();
      AnalysisResult result = await model.analyze(
        AnalysisRequest(
          taskId: TaskCatalog.privacyProfileSynthesis.id,
          inputs: <InputAsset>[
            InputAsset(
              type: InputAssetType.text,
              uri: 'privacy_profile_synthesis_input',
              displayName: 'combined privacy inference summaries',
              mimeType: 'application/json',
              sizeBytes: utf8.encode(synthesisInput).length,
              text: synthesisInput,
            ),
          ],
          taskSpec: TaskCatalog.privacyProfileSynthesis,
          options: <String, Object?>{
            'source_result_count': _privacyResults.length,
          },
        ),
      );
      if (!_isUsablePrivacyProfile(result)) {
        _privacyStatusMessage = 'Checking and repairing the profile structure.';
        notifyListeners();
        final String draft = _profileRepairDraft(result);
        result = await model.analyze(
          AnalysisRequest(
            taskId: TaskCatalog.privacyProfileRepair.id,
            inputs: <InputAsset>[
              InputAsset(
                type: InputAssetType.text,
                uri: 'privacy_profile_repair_input',
                displayName: 'profile draft requiring structure repair',
                mimeType: 'text/plain',
                sizeBytes: utf8.encode(draft).length,
                text: draft,
              ),
            ],
            taskSpec: TaskCatalog.privacyProfileRepair,
            options: <String, Object?>{
              'source_result_count': _privacyResults.length,
              'repair_attempt': 1,
            },
          ),
        );
      }
      if (_isUsablePrivacyProfile(result)) {
        _synthesizedPrivacyProfile = result;
        succeeded = true;
      } else {
        _synthesizedPrivacyProfile = null;
        _errorMessage =
            'Profile synthesis failed: ${result.failure?.message ?? 'Gemma did not return a valid structured profile.'}';
      }
    } catch (error, stackTrace) {
      debugPrint('Privacy profile synthesis failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Profile synthesis failed: $error';
    } finally {
      _privacyStatusMessage = null;
      await model.unload();
      _isBusy = false;
      notifyListeners();
    }
    return succeeded;
  }

  bool _isUsablePrivacyProfile(AnalysisResult result) {
    if (result.failure != null || result.rawOutput is! Map) return false;
    final Map<Object?, Object?> output =
        result.rawOutput! as Map<Object?, Object?>;
    if (output['parser_fallback'] == true) return false;

    bool hasText(String key) {
      final Object? value = output[key];
      return value is String && value.trim().isNotEmpty;
    }

    final Object? keyInferences = output['key_inferences'];
    final int usableInferenceCount = keyInferences is List
        ? keyInferences
            .whereType<String>()
            .where((String value) => value.trim().isNotEmpty)
            .length
        : 0;
    return hasText('headline') &&
        hasText('profile') &&
        hasText('privacy_implication') &&
        usableInferenceCount >= 2;
  }

  String _profileRepairDraft(AnalysisResult result) {
    final Object? output = result.rawOutput;
    String draft;
    if (output is Map && output['raw_model_output'] is String) {
      draft = output['raw_model_output'] as String;
    } else if (output is String) {
      draft = output;
    } else if (output != null) {
      draft = jsonEncode(output);
    } else {
      draft = '';
    }
    draft = draft.replaceAll(RegExp(r'\s+'), ' ').trim();
    const int maximumDraftLength = 1400;
    if (draft.length > maximumDraftLength) {
      draft = draft.substring(0, maximumDraftLength);
    }
    return draft.isEmpty
        ? 'No usable draft was returned. Produce a cautious limited profile.'
        : draft;
  }

  void cancelPrivacyInference() {
    _privacyCancelled = true;
  }

  void recordReactionCameraUnavailable({
    required String stage,
    required String event,
    required String reason,
  }) {
    _reactionSamples.add(
      ReactionEmotionSample(
        timestamp: DateTime.now(),
        stage: stage,
        event: event,
        failureReason: reason,
      ),
    );
    notifyListeners();
  }

  Future<void> recordReactionSnapshot({
    required List<int> imageBytes,
    required String stage,
    required String event,
  }) async {
    if (imageBytes.isEmpty) return;
    final RegisteredModel modelDescriptor = _registry.firstWhere(
      (RegisteredModel model) => model.id == 'emotieff',
      orElse: () => _registry.firstWhere(
        (RegisteredModel model) => model.id == 'resemotenet',
      ),
    );
    final AnalysisModel model = modelDescriptor.factory();
    try {
      final ModelConfig config =
          _settings.modelConfigs[modelDescriptor.id] ?? modelDescriptor.config;
      await model.load(config);
      final AnalysisResult result = await model.analyze(
        AnalysisRequest(
          taskId: TaskCatalog.emotionClassification.id,
          inputs: <InputAsset>[
            InputAsset(
              type: InputAssetType.image,
              uri: 'front_camera_snapshot',
              displayName: 'front_camera_snapshot.jpg',
              mimeType: 'image/jpeg',
              sizeBytes: imageBytes.length,
              bytes: imageBytes,
            ),
          ],
          taskSpec: TaskCatalog.emotionClassification,
          options: <String, Object?>{'source': 'front_camera_reaction'},
        ),
      );
      if (result.succeeded && result.prediction != null) {
        _reactionSamples.add(
          ReactionEmotionSample(
            timestamp: DateTime.now(),
            stage: stage,
            event: event,
            modelId: result.modelId,
            label: result.prediction!.label,
            confidence: result.prediction!.confidence,
          ),
        );
        notifyListeners();
      }
    } catch (error, stackTrace) {
      debugPrint('Reaction emotion snapshot failed: $error');
      debugPrint('$stackTrace');
    } finally {
      await model.unload();
    }
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
      final ModelConfig config =
          _settings.modelConfigs[modelDescriptor.id] ?? modelDescriptor.config;
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
    _benchmarkProgress = BenchmarkProgress(
      current: 0,
      total: dataset.examples.length,
      currentFile: 'Loading model',
      averageLatencyMs: 0,
    );
    notifyListeners();

    final RegisteredModel modelDescriptor = selectedModel;
    final AnalysisModel model = modelDescriptor.factory();
    try {
      final ModelConfig config =
          _settings.modelConfigs[modelDescriptor.id] ?? modelDescriptor.config;
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
      modelConfigs: <String, ModelConfig>{
        ..._settings.modelConfigs,
        modelId: config,
      },
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

  Future<void> refreshGemmaModelStatus() async {
    await _refreshGemmaModelStatus(notify: true);
  }

  Future<void> downloadStudyGemmaModel() async {
    if (_isGemmaDownloading || _gemmaModelReady) return;
    _isGemmaDownloading = true;
    _isGemmaDownloadPaused = false;
    _gemmaDownloadProgress = null;
    _gemmaDownloadStatus =
        'Starting a system download. You can leave the app or lock the screen while it continues.';
    notifyListeners();

    try {
      final Map<String, Object?> status = await _invokeNativeGemmaDownload(
        'startGemmaDownload',
        <String, Object?>{
          'url': _gemmaE2BDownloadUrl,
          'fileName': _gemmaE2BFileName,
        },
      );
      await _applyGemmaDownloadStatus(status, notify: true);
      if (_isGemmaDownloading || _isGemmaDownloadPaused) {
        _scheduleGemmaDownloadPolling();
      }
    } catch (error, stackTrace) {
      debugPrint('Gemma system download failed to start: $error');
      debugPrint('$stackTrace');
      _gemmaModelReady = false;
      _isGemmaDownloading = false;
      _isGemmaDownloadPaused = false;
      _gemmaDownloadProgress = null;
      _gemmaDownloadStatus =
          'Download could not start. Check the connection and try again.';
      notifyListeners();
    }
  }

  Future<Map<String, Object?>> _invokeNativeGemmaDownload(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    final Object? response = await _nativeChannel.invokeMethod<Object?>(
      method,
      arguments,
    );
    if (response is Map) {
      return Map<String, Object?>.from(response);
    }
    return <String, Object?>{'state': 'unknown'};
  }

  void _scheduleGemmaDownloadPolling() {
    _gemmaDownloadPollTimer?.cancel();
    _gemmaDownloadPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollGemmaDownloadStatus(),
    );
  }

  Future<void> _pollGemmaDownloadStatus() async {
    if (_isPollingGemmaDownload) return;
    _isPollingGemmaDownload = true;
    try {
      final Map<String, Object?> status = await _invokeNativeGemmaDownload(
        'getGemmaDownloadStatus',
      );
      await _applyGemmaDownloadStatus(status, notify: true);
    } catch (error, stackTrace) {
      debugPrint('Gemma download status polling failed: $error');
      debugPrint('$stackTrace');
    } finally {
      _isPollingGemmaDownload = false;
    }
  }

  Future<void> _applyGemmaDownloadStatus(
    Map<String, Object?> status, {
    required bool notify,
  }) async {
    final String state = (status['state'] as String?) ?? 'unknown';
    final String? localPath = status['local_path'] as String?;
    final int downloadedBytes =
        (status['downloaded_bytes'] as num?)?.toInt() ?? -1;
    final int totalBytes = (status['total_bytes'] as num?)?.toInt() ?? -1;
    final double? progress = (status['progress'] as num?)?.toDouble();

    if (state == 'complete' && localPath != null) {
      final File modelFile = File(localPath);
      final bool validModel = await modelFile.exists() &&
          await modelFile.length() >= _minimumGemmaModelBytes;
      if (validModel) {
        await _configureStudyGemmaModel(localPath);
        _gemmaModelReady = true;
        _isGemmaDownloading = false;
        _isGemmaDownloadPaused = false;
        _gemmaDownloadProgress = 1.0;
        _gemmaDownloadStatus =
            'Gemma 4 E2B is installed. No further download is needed.';
        _gemmaDownloadPollTimer?.cancel();
      } else {
        _gemmaModelReady = false;
        _isGemmaDownloading = false;
        _isGemmaDownloadPaused = false;
        _gemmaDownloadProgress = null;
        _gemmaDownloadStatus =
            'Download finished, but the model file is incomplete. Please retry.';
        _gemmaDownloadPollTimer?.cancel();
      }
    } else if (state == 'running' || state == 'pending') {
      _gemmaModelReady = false;
      _isGemmaDownloading = true;
      _isGemmaDownloadPaused = false;
      _gemmaDownloadProgress = progress;
      _gemmaDownloadStatus = _gemmaDownloadStatusText(
        state: state,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
        reason: status['reason'] as String?,
      );
    } else if (state == 'paused') {
      _gemmaModelReady = false;
      _isGemmaDownloading = false;
      _isGemmaDownloadPaused = true;
      _gemmaDownloadProgress = progress;
      _gemmaDownloadStatus = _gemmaDownloadStatusText(
        state: state,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
        reason: status['reason'] as String?,
      );
    } else if (state == 'failed') {
      _gemmaModelReady = false;
      _isGemmaDownloading = false;
      _isGemmaDownloadPaused = false;
      _gemmaDownloadProgress = null;
      _gemmaDownloadStatus =
          'Download failed. ${(status['reason'] as String?) ?? 'Please try again.'}';
      _gemmaDownloadPollTimer?.cancel();
    } else if (state == 'not_found') {
      _isGemmaDownloading = false;
      _isGemmaDownloadPaused = false;
      _gemmaDownloadProgress = null;
      _gemmaDownloadStatus ??= 'Gemma 4 E2B is not installed yet.';
      _gemmaDownloadPollTimer?.cancel();
    }

    if (notify) notifyListeners();
  }

  String _gemmaDownloadStatusText({
    required String state,
    required int downloadedBytes,
    required int totalBytes,
    String? reason,
  }) {
    final String prefix = switch (state) {
      'pending' => 'Waiting to start system download.',
      'paused' =>
        'Download paused: ${reason ?? 'Android is waiting to retry.'}',
      _ => 'System download running.',
    };
    if (downloadedBytes >= 0 && totalBytes > 0) {
      return '$prefix Downloaded ${(downloadedBytes / (1024 * 1024)).toStringAsFixed(0)} MB of ${(totalBytes / (1024 * 1024)).toStringAsFixed(0)} MB. You can leave the app or lock the screen.';
    }
    if (downloadedBytes >= 0) {
      return '$prefix Downloaded ${(downloadedBytes / (1024 * 1024)).toStringAsFixed(0)} MB. You can leave the app or lock the screen.';
    }
    return '$prefix You can leave the app or lock the screen.';
  }

  Future<void> _refreshGemmaModelStatus({required bool notify}) async {
    final RegisteredModel descriptor =
        _registry.firstWhere((RegisteredModel model) => model.id == 'gemma');
    final ModelConfig current =
        _settings.modelConfigs[descriptor.id] ?? descriptor.config;
    final String? configuredPath = current.assetConfig['asset_path'] as String?;
    final List<String> candidatePaths = <String>{
      if (configuredPath != null && configuredPath.trim().isNotEmpty)
        configuredPath,
      await _gemmaPrivateModelPath(),
    }.toList();

    for (final String candidatePath in candidatePaths) {
      final File targetFile = File(candidatePath);
      final bool validModel = await targetFile.exists() &&
          await targetFile.length() >= _minimumGemmaModelBytes;
      if (validModel) {
        _gemmaDownloadPollTimer?.cancel();
        await _configureStudyGemmaModel(candidatePath);
        _gemmaModelReady = true;
        _isGemmaDownloading = false;
        _isGemmaDownloadPaused = false;
        _gemmaDownloadProgress = 1.0;
        _gemmaDownloadStatus =
            'Gemma 4 E2B is already installed. No download is needed.';
        if (notify) notifyListeners();
        return;
      }
    }

    try {
      final Map<String, Object?> status = await _invokeNativeGemmaDownload(
        'getGemmaDownloadStatus',
      );
      await _applyGemmaDownloadStatus(status, notify: false);
      if (_isGemmaDownloading || _isGemmaDownloadPaused) {
        _scheduleGemmaDownloadPolling();
      }
    } catch (error, stackTrace) {
      debugPrint('Gemma download status refresh failed: $error');
      debugPrint('$stackTrace');
      _gemmaModelReady = false;
      _isGemmaDownloading = false;
      _isGemmaDownloadPaused = false;
      _gemmaDownloadProgress = null;
      _gemmaDownloadStatus = 'Gemma 4 E2B is not installed yet.';
    }
    if (notify) notifyListeners();
  }

  Future<String> _gemmaPrivateModelPath() async {
    final Directory documents = await getApplicationDocumentsDirectory();
    return '${documents.path}/models/$_gemmaE2BFileName';
  }

  Future<void> _configureStudyGemmaModel(String targetPath) async {
    final RegisteredModel descriptor =
        _registry.firstWhere((RegisteredModel model) => model.id == 'gemma');
    final ModelConfig current =
        _settings.modelConfigs[descriptor.id] ?? descriptor.config;
    final ModelConfig configured = current.copyWith(
      variantId: 'gemma_e2b',
      version: 'gemma4-litert-local',
      runtimeOptions: <String, Object?>{
        ...current.runtimeOptions,
        'backend': 'litert_lm',
      },
      assetConfig: <String, Object?>{
        ...current.assetConfig,
        'asset_path': targetPath,
      },
    );
    _settings = _settings.copyWith(
      modelConfigs: <String, ModelConfig>{
        ..._settings.modelConfigs,
        descriptor.id: configured,
      },
    );
    await _settingsRepository.save(_settings);
  }

  Future<RenderedPdfPage> _renderPdfPreview(PlatformFile platformFile) async {
    final String? path = platformFile.path;
    if (path != null && path.trim().isNotEmpty && await File(path).exists()) {
      return PdfPageRenderer.renderFirstPageFromPath(path);
    }
    final List<int>? bytes = await _loadPlatformFileBytes(platformFile);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Could not read selected PDF.');
    }
    return PdfPageRenderer.renderFirstPage(Uint8List.fromList(bytes));
  }

  PreparedStudyImage _prepareStudyImage(List<int> rawBytes) {
    final Uint8List input =
        rawBytes is Uint8List ? rawBytes : Uint8List.fromList(rawBytes);
    final img.Image? decoded = img.decodeImage(input);
    if (decoded == null) {
      return PreparedStudyImage(bytes: input);
    }

    img.Image normalized = img.bakeOrientation(decoded);
    const int maxSide = 1152;
    final int longestSide = normalized.width > normalized.height
        ? normalized.width
        : normalized.height;
    if (longestSide > maxSide) {
      final double scale = maxSide / longestSide;
      normalized = img.copyResize(
        normalized,
        width: (normalized.width * scale).round(),
        height: (normalized.height * scale).round(),
        interpolation: img.Interpolation.average,
      );
    }

    return PreparedStudyImage(
      bytes: Uint8List.fromList(img.encodeJpg(normalized, quality: 84)),
      width: normalized.width,
      height: normalized.height,
    );
  }

  Future<List<int>?> _loadPlatformFileBytes(PlatformFile platformFile) async {
    if (platformFile.bytes != null) return platformFile.bytes;
    if (platformFile.path != null) {
      return File(platformFile.path!).readAsBytes();
    }
    return null;
  }

  String _buildPrivacyProfileSynthesisInput() {
    const int totalSignalBudget = 1400;
    final int perFileBudget =
        (totalSignalBudget ~/ _privacyResults.length).clamp(55, 180);
    final List<String> lines = <String>[
      'FILES=${_privacyResults.length}',
    ];
    for (int index = 0; index < _privacyResults.length; index++) {
      final Object? raw = _privacyResults[index].result.rawOutput;
      final Map<Object?, Object?> json = raw is Map
          ? raw.cast<Object?, Object?>()
          : const <Object?, Object?>{};
      final String ownerSignal = _firstString(json['owner_inferences']) ??
          _stringValue(json['participant_message']) ??
          _stringValue(json['content_summary']) ??
          'No reliable owner-level signal';
      final String? privateSignal = _firstString(json['private_signals']);
      final String combined = privateSignal == null
          ? ownerSignal
          : '$ownerSignal Private clue: $privateSignal';
      lines.add(
        '${index + 1}|${_truncateSynthesisSignal(combined, perFileBudget)}',
      );
    }
    return lines.join('\n');
  }

  String? _firstString(Object? value) {
    if (value is! List) return null;
    for (final Object? item in value) {
      if (item is String && item.trim().isNotEmpty) return item.trim();
    }
    return null;
  }

  String? _stringValue(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  String _truncateSynthesisSignal(String value, int maximumCharacters) {
    final String compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= maximumCharacters) return compact;
    return '${compact.substring(0, maximumCharacters - 3).trimRight()}...';
  }

  AggregatePrivacyProfile _buildAggregatePrivacyProfile() {
    final Set<String> ownerInferences = <String>{};
    final Set<String> privateSignals = <String>{};
    final Set<String> profilingUses = <String>{};
    int high = 0;
    int medium = 0;
    for (final PrivacyStudyResult entry in _privacyResults) {
      final Object? raw = entry.result.rawOutput;
      if (raw is! Map<String, dynamic>) continue;
      final String sensitivity = (raw['sensitivity'] as String?) ?? '';
      if (sensitivity == 'high') high++;
      if (sensitivity == 'medium') medium++;
      ownerInferences.addAll(_stringList(raw['owner_inferences']));
      privateSignals.addAll(_stringList(raw['private_signals']));
      profilingUses.addAll(_stringList(raw['profiling_uses']));
    }
    return AggregatePrivacyProfile(
      analyzedFiles: _privacyResults.length,
      highSensitivityCount: high,
      mediumSensitivityCount: medium,
      ownerInferences: ownerInferences.take(3).toList(),
      privateSignals: privateSignals.take(3).toList(),
      profilingUses: profilingUses.take(3).toList(),
    );
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .whereType<String>()
        .where((String item) => item.trim().isNotEmpty)
        .toList();
  }

  bool _hasPrivacyResult(String fileId) {
    return _privacyResults
        .any((PrivacyStudyResult result) => result.file.id == fileId);
  }

  String _privacyFileIdFromMetadata(PlatformFile file) {
    final String normalizedName = file.name.trim().toLowerCase();
    return '$normalizedName:${file.size}';
  }

  String _imageMimeType(String? extension) {
    return switch ((extension ?? '').toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }
}
