import 'package:flutter/services.dart';

/// Dart wrapper for the native macOS Vision OCR plugin.
/// Used as a replacement for Google ML Kit on macOS.
class VisionOcrChannel {
  static const _channel = MethodChannel('com.lineguide/vision_ocr');

  /// Recognize text in an image file using Apple Vision framework.
  static Future<List<VisionTextBlock>?> recognizeText(String imagePath) async {
    try {
      final result = await _channel.invokeMethod<Map>('recognizeText', {
        'path': imagePath,
      });
      if (result == null) return null;

      final blocks = result['blocks'] as List?;
      if (blocks == null) return [];

      return blocks.map((b) {
        final map = Map<String, dynamic>.from(b as Map);
        return VisionTextBlock(
          text: map['text'] as String? ?? '',
          confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();
    } on MissingPluginException {
      return null;
    }
  }

  /// OCR an entire PDF natively — renders pages with PDFKit, OCRs with Vision.
  /// Returns per-page results with lines and confidence in one call.
  static Future<VisionPdfResult?> ocrPdf(String pdfPath, {double scale = 2.0}) async {
    try {
      final result = await _channel.invokeMethod<Map>('ocrPdf', {
        'path': pdfPath,
        'scale': scale,
      });
      if (result == null) return null;

      final pageCount = result['pageCount'] as int? ?? 0;
      final failedPages = result['failedPages'] as int? ?? 0;
      final pagesRaw = result['pages'] as List? ?? [];

      final pages = pagesRaw.map((p) {
        final map = Map<String, dynamic>.from(p as Map);
        final pageNum = map['page'] as int? ?? 0;
        final linesRaw = map['lines'] as List? ?? [];
        final lines = linesRaw.map((l) {
          final lm = Map<String, dynamic>.from(l as Map);
          return VisionTextBlock(
            text: lm['text'] as String? ?? '',
            confidence: (lm['confidence'] as num?)?.toDouble() ?? 0.0,
          );
        }).toList();
        return VisionPage(page: pageNum, lines: lines);
      }).toList();

      return VisionPdfResult(
        pages: pages,
        pageCount: pageCount,
        failedPages: failedPages,
      );
    } on MissingPluginException {
      return null;
    }
  }
}

class VisionTextBlock {
  final String text;
  final double confidence;

  VisionTextBlock({required this.text, required this.confidence});
}

class VisionPage {
  final int page; // 1-based
  final List<VisionTextBlock> lines;

  VisionPage({required this.page, required this.lines});
}

class VisionPdfResult {
  final List<VisionPage> pages;
  final int pageCount;
  final int failedPages;

  VisionPdfResult({
    required this.pages,
    required this.pageCount,
    required this.failedPages,
  });
}
