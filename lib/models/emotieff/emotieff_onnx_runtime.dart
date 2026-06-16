import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

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
    final OrtSession session = await _loadSession();
    final List<String> labels = _labelsForVariant();
    final int inputSize = _inputSizeForVariant();
    final Float32List input = _preprocessImage(asset, inputSize);
    final String inputName = session.inputNames.isNotEmpty ? session.inputNames.first : 'input';
    final String outputName = session.outputNames.isNotEmpty ? session.outputNames.first : 'output';

    final OrtValue inputTensor = await OrtValue.fromList(input, <int>[1, 3, inputSize, inputSize]);
    final Map<String, OrtValue> outputs;
    try {
      outputs = await session.run(<String, OrtValue>{inputName: inputTensor});
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

    final List<dynamic> flattened = await outputTensor.asFlattenedList();
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
        'assumption': 'Input image is treated as an already-cropped face image.',
      },
    );
  }

  @override
  Future<void> close() async {
    await _session?.close();
    _session = null;
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

    final OrtSession? existing = _session;
    if (existing != null) return existing;

    final OrtSession session = await OnnxRuntime().createSession(
      modelPath,
      options: OrtSessionOptions(intraOpNumThreads: 2),
    );
    _session = session;
    return session;
  }

  Float32List _preprocessImage(InputAsset asset, int inputSize) {
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

    final img.Image resized = img.copyResize(decoded, width: inputSize, height: inputSize);
    final Float32List tensor = Float32List(3 * inputSize * inputSize);
    final List<double> mean = _meanForVariant();
    final List<double> std = _stdForVariant();
    final int planeSize = inputSize * inputSize;

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
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
