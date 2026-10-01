import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'docx_extractor.dart';

class ExtractedDocument {
  final String text;
  final String warning;
  const ExtractedDocument(this.text, this.warning);
}

class DocumentExtractor {
  static const _channel = MethodChannel('kraken.kernel/documents');
  Future<ExtractedDocument> extract(String path) async {
    try {
      if (Platform.isIOS && path.toLowerCase().endsWith('.docx')) {
        return ExtractedDocument(
          await compute(extractDocxText, path),
          'Word import includes body text and tables. Images, comments, headers, footers and footnotes are not included.',
        );
      }
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
