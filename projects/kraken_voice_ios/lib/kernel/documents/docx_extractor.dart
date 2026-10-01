import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart' hide ZLibDecoder;
import 'package:xml/xml.dart';

const _maxXml = 8 * 1024 * 1024;
const _maxText = 500000;
const _wordNamespaces = {
  'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
  'http://purl.oclc.org/ooxml/wordprocessingml/main',
};

/// Runs in an isolate. Only reads the document body; never extracts ZIP paths.
Future<String> extractDocxText(String path) async {
  try {
    final file = File(path);
    if (await file.length() > 50 * 1024 * 1024) {
      throw StateError('Choose a document smaller than 50 MB.');
    }
    final directory = ZipDirectory()
      ..read(InputMemoryStream(await file.readAsBytes()));
    final entries = directory.fileHeaders
        .where((e) => e.filename == 'word/document.xml')
        .toList();
    if (entries.length != 1) throw const FormatException();
    final entry = entries.single;
    if (entry.generalPurposeBitFlag & 1 != 0) {
      throw StateError(
        'This Word document is password-protected. Import an unlocked copy.',
      );
    }
    if (entry.uncompressedSize <= 0 || entry.uncompressedSize > _maxXml) {
      throw StateError(
        'This Word document is too large to extract. Split it into smaller files.',
      );
    }
    if (entry.compressionMethod != 0 && entry.compressionMethod != 8)
      throw const FormatException();
    final raw = entry.file!.getRawContent();
    Stream<List<int>> chunks() async* {
      for (var offset = 0; offset < raw.length; offset += 4096) {
        yield Uint8List.sublistView(
          raw,
          offset,
          (offset + 4096).clamp(0, raw.length),
        );
      }
    }

    final stream = entry.compressionMethod == 8
        ? chunks().transform(ZLibDecoder(raw: true))
        : chunks();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > _maxXml) {
        throw StateError('The Word document expands beyond the import limit.');
      }
      bytes.add(chunk);
    }
    final data = bytes.takeBytes();
    if (data.length != entry.uncompressedSize || getCrc32(data) != entry.crc32)
      throw const FormatException();
    String xml;
    if (data.length >= 2 &&
        ((data[0] == 255 && data[1] == 254) ||
            (data[0] == 254 && data[1] == 255))) {
      if (data.length.isOdd) throw const FormatException();
      final view = ByteData.sublistView(data);
      final endian = data[0] == 255 ? Endian.little : Endian.big;
      xml = String.fromCharCodes([
        for (var i = 2; i < data.length; i += 2) view.getUint16(i, endian),
      ]);
    } else {
      xml = utf8.decode(data);
    }
    // No external entities or document-defined entity expansion.
    if (xml.contains('<!DOCTYPE') || xml.contains('<!ENTITY'))
      throw const FormatException();
    final document = XmlDocument.parse(xml);
    final root = document.rootElement;
    bool word(XmlElement e) => _wordNamespaces.contains(e.namespaceUri);
    if (!word(root) || root.name.local != 'document')
      throw const FormatException();
    final body = root.childElements
        .where((e) => word(e) && e.name.local == 'body')
        .firstOrNull;
    if (body == null) throw const FormatException();
    final text = StringBuffer();
    // Iterative walk avoids stack overflow from deeply nested input.
    final pending = <(XmlNode, bool)>[(body, false)];
    while (pending.isNotEmpty) {
      final (node, closing) = pending.removeLast();
      if (node is! XmlElement) continue;
      final local = word(node) ? node.name.local : '';
      if (local == 'del' || local == 'moveFrom') continue;
      if (closing) {
        if (local == 'p' || local == 'tr') text.write('\n');
        if (local == 'tc') text.write('\t');
      } else if (local == 't') {
        text.write(node.innerText);
      } else {
        if (local == 'tab') text.write('\t');
        if (local == 'br' || local == 'cr') text.write('\n');
        pending.add((node, true));
        for (final child in node.children.reversed) {
          pending.add((child, false));
        }
      }
      if (text.length > _maxText)
        throw StateError(
          'This document contains too much text. Split it into smaller documents.',
        );
    }
    final result = text.toString().trim();
    if (result.isEmpty)
      throw StateError(
        'No readable text found. Images and scanned documents need OCR first.',
      );
    return result;
  } on StateError {
    rethrow;
  } catch (_) {
    throw StateError(
      'Unable to read this Word document. Import an unlocked, valid .docx copy.',
    );
  }
}
