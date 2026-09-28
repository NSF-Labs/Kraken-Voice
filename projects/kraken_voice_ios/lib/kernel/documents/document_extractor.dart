import 'package:flutter/services.dart';

class ExtractedDocument {
  final String text;
  final String warning;
  const ExtractedDocument(this.text, this.warning);
}

class DocumentExtractor {
  static const _channel = MethodChannel('kraken.kernel/documents');
  Future<ExtractedDocument> extract(String path) async {
    try {
      final data = await _channel.invokeMapMethod<String, dynamic>('extract', {
        'path': path,
      });
      final text = data?['text'] as String? ?? '';
      if (text.trim().isEmpty) {
        throw StateError(
          'No readable text found. Scanned documents need OCR first.',
        );
      }
      return ExtractedDocument(text, data?['warning'] as String? ?? '');
    } on PlatformException catch (e) {
      throw StateError(e.message ?? 'Unable to read this document.');
    }
  }
}
