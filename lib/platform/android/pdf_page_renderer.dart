import 'package:flutter/services.dart';

class RenderedPdfPage {
  const RenderedPdfPage({
    required this.pngBytes,
    required this.width,
    required this.height,
  });

  final Uint8List pngBytes;
  final int width;
  final int height;
}

class PdfPageRenderer {
  const PdfPageRenderer._();

  static const MethodChannel _channel =
      MethodChannel('local_trait_lab/gemma_litert');

  static Future<RenderedPdfPage> renderFirstPage(Uint8List pdfBytes) async {
    final Object? response = await _channel.invokeMethod<Object?>(
      'renderPdfFirstPage',
      <String, Object?>{'pdfBytes': pdfBytes},
    );
    final Map<Object?, Object?> map = response as Map<Object?, Object?>;
    return RenderedPdfPage(
      pngBytes: map['pngBytes'] as Uint8List,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
    );
  }
}
