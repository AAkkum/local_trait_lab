import 'analysis_request.dart';

enum InputAssetType { image, pdf, text, document, imageCollection }

class InputAsset {
  const InputAsset({
    required this.type,
    required this.uri,
    required this.displayName,
    required this.mimeType,
    required this.sizeBytes,
    this.bytes,
    this.width,
    this.height,
  });

  final InputAssetType type;
  final String uri;
  final String displayName;
  final String mimeType;
  final int sizeBytes;
  final List<int>? bytes;
  final int? width;
  final int? height;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type.name,
        'uri': uri,
        'display_name': displayName,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'width': width,
        'height': height,
      };
}

class PromptTemplate {
  const PromptTemplate({
    required this.systemInstructions,
    required this.userTemplate,
  });

  final String systemInstructions;
  final String userTemplate;

  String build(Map<String, String> values) {
    String built = userTemplate;
    values.forEach((String key, String value) {
      built = built.replaceAll('{{$key}}', value);
    });
    return '$systemInstructions\n\n$built';
  }
}

class OutputSchema {
  const OutputSchema({
    required this.id,
    required this.allowedLabels,
    required this.requiresScoreVector,
    required this.strictJson,
  });

  final String id;
  final List<String> allowedLabels;
  final bool requiresScoreVector;
  final bool strictJson;
}

class LabelSpace {
  const LabelSpace({
    required this.id,
    required this.labels,
  });

  final String id;
  final List<String> labels;
}

class AnalysisTaskSpec {
  const AnalysisTaskSpec({
    required this.id,
    required this.displayName,
    required this.acceptedInputTypes,
    required this.outputSchema,
    this.promptTemplate,
    this.labelSpace,
  });

  final String id;
  final String displayName;
  final List<InputAssetType> acceptedInputTypes;
  final PromptTemplate? promptTemplate;
  final OutputSchema outputSchema;
  final LabelSpace? labelSpace;

  bool acceptsRequest(AnalysisRequest request) {
    return request.inputs.every((InputAsset asset) => acceptedInputTypes.contains(asset.type));
  }
}
