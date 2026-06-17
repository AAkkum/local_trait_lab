import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../analysis/analysis_result.dart';
import '../../analysis/task_spec.dart';
import 'emotieff_runtime.dart';

class EmotiEffOnnxRuntime implements EmotiEffRuntime {
  EmotiEffOnnxRuntime({
    required this.modelPath,
    required this.variantId,
  });

  final String modelPath;
  final String variantId;

  OrtSession? _session;
  FaceDetector? _faceDetector;

  static const List<String> _labels7 = <String>[
    'Anger',
    'Disgust',
    'Fear',
    'Happiness',
    'Neutral',
    'Sadness',
    'Surprise',
  ];

  static const List<String> _labels8 = <String>[
    'Anger',
    'Contempt',
    'Disgust',
    'Fear',
    'Happiness',
    'Neutral',
    'Sadness',
    'Surprise',
  ];

  @override
  Future<EmotiEffRuntimeOutput> classifyEmotion({required InputAsset asset}) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    debugPrint('[EmotiEff ONNX] classify start asset=${asset.displayName} variant=$variantId path=$modelPath');
    final OrtSession session = await _loadSession();
    debugPrint('[EmotiEff ONNX] session loaded inputs=${session.inputNames} outputs=${session.outputNames}');
    final List<String> labels = _labelsForVariant();
    final int inputSize = _inputSizeForVariant();
    final _PreparedImage prepared = await _preprocessImage(asset, inputSize);
    debugPrint('[EmotiEff ONNX] preprocessing done faceDetected=${prepared.faceDetected} faceCount=${prepared.faceCount} crop=${prepared.cropRectangle}');
    final String inputName = session.inputNames.isNotEmpty ? session.inputNames.first : 'input';
    final String outputName = session.outputNames.isNotEmpty ? session.outputNames.first : 'output';

    debugPrint('[EmotiEff ONNX] creating input tensor');
    final OrtValue inputTensor = await OrtValue.fromList(prepared.tensor, <int>[1, 3, inputSize, inputSize]);
    final Map<String, OrtValue> outputs;
    try {
      debugPrint('[EmotiEff ONNX] running session');
      outputs = await session.run(<String, OrtValue>{inputName: inputTensor}).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw const AnalysisFailure(
            type: AnalysisFailureType.runtimeUnavailable,
            message: 'ONNX inference timed out after 20 seconds.',
          );
        },
      );
      debugPrint('[EmotiEff ONNX] session returned outputs=${outputs.keys.toList()}');
    } finally {
      await inputTensor.dispose();
    }

    final OrtValue? outputTensor = outputs[outputName] ?? (outputs.isNotEmpty ? outputs.values.first : null);
    if (outputTensor == null) {
      throw const AnalysisFailure(
        type: AnalysisFailureType.invalidStructuredOutput,
        message: 'ONNX model returned no outputs.',
      );
    }

    final List<dynamic> flattened = await outputTensor.asFlattenedList().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw const AnalysisFailure(
          type: AnalysisFailureType.runtimeUnavailable,
          message: 'Reading ONNX output timed out after 10 seconds.',
        );
      },
    );
    for (final OrtValue output in outputs.values) {
      await output.dispose();
    }
    stopwatch.stop();

    final List<double> scores = flattened.map((dynamic value) => (value as num).toDouble()).toList();
    final List<double> emotionScores = _emotionPart(scores, labels.length);
    if (emotionScores.length < labels.length) {
      throw AnalysisFailure(
        type: AnalysisFailureType.invalidStructuredOutput,
        message: 'ONNX output has ${emotionScores.length} scores, expected at least ${labels.length}.',
      );
    }

    return EmotiEffRuntimeOutput(
      rawScores: <String, double>{
        for (int i = 0; i < labels.length; i++) labels[i]: emotionScores[i],
      },
      latencyMs: stopwatch.elapsedMilliseconds,
      runtimeBackend: 'onnx',
      debug: <String, Object?>{
        'variant_id': variantId,
        'model_path': modelPath,
        'input_name': inputName,
        'output_name': outputName,
        'input_shape': <int>[1, 3, inputSize, inputSize],
        'face_detected': prepared.faceDetected,
        'face_count': prepared.faceCount,
        'crop_rectangle': prepared.cropRectangle,
        'preprocessing': 'ML Kit largest-face crop with margin, then EmotiEff resize/normalize.',
      },
    );
  }

  @override
  Future<void> close() async {
    await _session?.close();
    _session = null;
    await _faceDetector?.close();
    _faceDetector = null;
  }

  Future<OrtSession> _loadSession() async {
    if (modelPath.trim().isEmpty) {
      throw const AnalysisFailure(
        type: AnalysisFailureType.runtimeUnavailable,
        message: 'No EmotiEff ONNX model file path configured. Select an .onnx file in Advanced settings.',
      );
    }
    final File modelFile = File(modelPath);
    if (!await modelFile.exists()) {
      throw AnalysisFailure(
        type: AnalysisFailureType.runtimeUnavailable,
        message: 'Configured EmotiEff ONNX model file does not exist: $modelPath',
      );
    }
    final int modelSize = await modelFile.length();
    if (modelSize < 1024 * 1024) {
      throw AnalysisFailure(
        type: AnalysisFailureType.runtimeUnavailable,
        message: 'Configured ONNX file is only $modelSize bytes. This is too small for the EmotiEff model and is probably not the real model file.',
      );
    }

    final OrtSession? existing = _session;
    if (existing != null) return existing;

    debugPrint('[EmotiEff ONNX] creating ONNX session from $modelPath');
    final OrtSession session;
    try {
      session = await OnnxRuntime().createSession(
        modelPath,
        options: OrtSessionOptions(intraOpNumThreads: 2),
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw const AnalysisFailure(
            type: AnalysisFailureType.runtimeUnavailable,
            message: 'Creating ONNX session timed out after 20 seconds.',
          );
        },
      );
    } on AnalysisFailure {
      rethrow;
    } on PlatformException catch (error) {
      throw AnalysisFailure(
        type: AnalysisFailureType.runtimeUnavailable,
        message: 'ONNX Runtime could not load the imported model file. Re-import a valid .onnx file in Advanced settings. Details: ${error.code}',
        details: <String, Object?>{'path': modelPath, 'platform_message': error.message},
      );
    }
    debugPrint('[EmotiEff ONNX] ONNX session created');
    _session = session;
    return session;
  }

  Future<_PreparedImage> _preprocessImage(InputAsset asset, int inputSize) async {
    final List<int>? bytes = asset.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const AnalysisFailure(
        type: AnalysisFailureType.invalidInput,
        message: 'Selected image has no loaded bytes.',
      );
    }
    final img.Image? decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) {
      throw const AnalysisFailure(
        type: AnalysisFailureType.invalidInput,
        message: 'Could not decode selected image.',
      );
    }

    debugPrint('[EmotiEff ONNX] decoded image ${decoded.width}x${decoded.height}; detecting face');
    final List<Face> faces = await _detectFaces(asset, bytes).timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('[EmotiEff ONNX] face detection timeout; falling back to full image');
        return <Face>[];
      },
    );
    debugPrint('[EmotiEff ONNX] face detection returned ${faces.length} faces');
    final _CropResult crop = _cropLargestFace(decoded, faces);
    final img.Image resized = img.copyResize(crop.image, width: inputSize, height: inputSize);
    final Float32List tensor = _imageToTensor(resized, inputSize);
    return _PreparedImage(
      tensor: tensor,
      faceDetected: crop.faceDetected,
      faceCount: faces.length,
      cropRectangle: crop.cropRectangle,
    );
  }

  Future<List<Face>> _detectFaces(InputAsset asset, List<int> bytes) async {
    final FaceDetector detector = _faceDetector ??= FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: false,
        enableContours: false,
        enableClassification: false,
        minFaceSize: 0.05,
      ),
    );
    final String path = await _pathForMlKit(asset, bytes);
    debugPrint('[EmotiEff ONNX] ML Kit input path=$path');
    return detector.processImage(InputImage.fromFilePath(path));
  }

  Future<String> _pathForMlKit(InputAsset asset, List<int> bytes) async {
    final Uri? parsed = Uri.tryParse(asset.uri);
    if (parsed != null && parsed.scheme == 'file') {
      final String path = parsed.toFilePath();
      if (await File(path).exists()) return path;
    }
    if (!asset.uri.startsWith('zip://') && await File(asset.uri).exists()) {
      return asset.uri;
    }

    final Directory directory = await getTemporaryDirectory();
    final String safeName = asset.displayName.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final File file = File('${directory.path}/mlkit_$safeName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  _CropResult _cropLargestFace(img.Image decoded, List<Face> faces) {
    if (faces.isEmpty) {
      return _CropResult(
        image: decoded,
        faceDetected: false,
        cropRectangle: <String, int>{'x': 0, 'y': 0, 'width': decoded.width, 'height': decoded.height},
      );
    }

    final Face largest = faces.reduce((Face a, Face b) {
      final double areaA = a.boundingBox.width * a.boundingBox.height;
      final double areaB = b.boundingBox.width * b.boundingBox.height;
      return areaA >= areaB ? a : b;
    });
    final Rect box = largest.boundingBox;
    final double marginX = box.width * 0.25;
    final double marginY = box.height * 0.35;
    final int x = (box.left - marginX).floor().clamp(0, decoded.width - 1);
    final int y = (box.top - marginY).floor().clamp(0, decoded.height - 1);
    final int right = (box.right + marginX).ceil().clamp(x + 1, decoded.width);
    final int bottom = (box.bottom + marginY).ceil().clamp(y + 1, decoded.height);
    final int width = right - x;
    final int height = bottom - y;

    return _CropResult(
      image: img.copyCrop(decoded, x: x, y: y, width: width, height: height),
      faceDetected: true,
      cropRectangle: <String, int>{'x': x, 'y': y, 'width': width, 'height': height},
    );
  }

  Float32List _imageToTensor(img.Image image, int inputSize) {
    final Float32List tensor = Float32List(3 * inputSize * inputSize);
    final List<double> mean = _meanForVariant();
    final List<double> std = _stdForVariant();
    final int planeSize = inputSize * inputSize;

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = image.getPixel(x, y);
        final int offset = y * inputSize + x;
        tensor[offset] = ((pixel.r / 255.0) - mean[0]) / std[0];
        tensor[planeSize + offset] = ((pixel.g / 255.0) - mean[1]) / std[1];
        tensor[2 * planeSize + offset] = ((pixel.b / 255.0) - mean[2]) / std[2];
      }
    }
    return tensor;
  }

  List<String> _labelsForVariant() => variantId.contains('_7') ? _labels7 : _labels8;

  int _inputSizeForVariant() {
    if (variantId.startsWith('mbf_')) return 112;
    if (variantId.contains('_b2_')) return 260;
    return 224;
  }

  List<double> _meanForVariant() => variantId.startsWith('mbf_') ? const <double>[0.5, 0.5, 0.5] : const <double>[0.485, 0.456, 0.406];

  List<double> _stdForVariant() => variantId.startsWith('mbf_') ? const <double>[0.5, 0.5, 0.5] : const <double>[0.229, 0.224, 0.225];

  List<double> _emotionPart(List<double> scores, int labelCount) {
    if (variantId.contains('_mtl') && scores.length >= labelCount + 2) {
      return scores.sublist(0, math.min(labelCount, scores.length - 2));
    }
    return scores.take(labelCount).toList();
  }
}

class _PreparedImage {
  const _PreparedImage({
    required this.tensor,
    required this.faceDetected,
    required this.faceCount,
    required this.cropRectangle,
  });

  final Float32List tensor;
  final bool faceDetected;
  final int faceCount;
  final Map<String, int> cropRectangle;
}

class _CropResult {
  const _CropResult({
    required this.image,
    required this.faceDetected,
    required this.cropRectangle,
  });

  final img.Image image;
  final bool faceDetected;
  final Map<String, int> cropRectangle;
}
