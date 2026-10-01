import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/kernel/documents/docx_extractor.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('docx-check');
  });
  tearDown(() => temp.delete(recursive: true));
  Future<String> extract(
    String body, {
    String namespace =
        'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
  }) async {
    final zip = Archive()
      ..addFile(
        ArchiveFile.string(
          'word/document.xml',
          '<w:document xmlns:w="$namespace"><w:body>$body</w:body></w:document>',
        ),
      );
    final file = File('${temp.path}/check.docx');
    await file.writeAsBytes(ZipEncoder().encode(zip));
    return extractDocxText(file.path);
  }

  test(
    'body, tables, Unicode and accepted edits preserve reading order',
    () async {
      final text = await extract(
        '<w:p><w:r><w:t>Maya &amp; André</w:t><w:tab/><w:t>42750</w:t><w:br/><w:t>October 16</w:t></w:r></w:p><w:del><w:r><w:delText>99999</w:delText></w:r></w:del><w:moveFrom><w:r><w:t>Old text</w:t></w:r></w:moveFrom><w:tbl><w:tr><w:tc><w:p><w:r><w:t>Owner</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Maya</w:t></w:r></w:p></w:tc></w:tr></w:tbl>',
      );
      expect(text, contains('Maya & André\t42750\nOctober 16'));
      expect(text, contains('Owner\n\tMaya'));
      expect(text, isNot(contains('99999')));
      expect(text, isNot(contains('Old text')));
    },
  );
  test('strict OOXML namespace is accepted', () async {
    expect(
      await extract(
        '<w:p><w:r><w:t>Strict Word</w:t></w:r></w:p>',
        namespace: 'http://purl.oclc.org/ooxml/wordprocessingml/main',
      ),
      'Strict Word',
    );
  });
  test('empty or image-only document gives readable error', () async {
    await expectLater(
      extract('<w:p/>'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('No readable text'),
        ),
      ),
    );
  });
  test('corrupt and non-Word ZIP files are rejected', () async {
    final file = File('${temp.path}/bad.docx');
    await file.writeAsString('not a zip');
    await expectLater(extractDocxText(file.path), throwsStateError);
    await file.writeAsBytes(
      ZipEncoder().encode(
        Archive()..addFile(ArchiveFile.string('other.xml', 'oops')),
      ),
    );
    await expectLater(extractDocxText(file.path), throwsStateError);
  });
  test('malformed XML and oversized text are rejected', () async {
    await expectLater(extract('<w:p><w:t>unfinished'), throwsStateError);
    await expectLater(
      extract('<w:p><w:r><w:t>${'a' * 500001}</w:t></w:r></w:p>'),
      throwsStateError,
    );
  });
}
