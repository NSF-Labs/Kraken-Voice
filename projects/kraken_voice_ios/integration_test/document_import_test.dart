import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:krak_en_voice/kernel/documents/document_extractor.dart';
import 'package:krak_en_voice/kernel/inference/local_inference_service.dart';
import 'package:krak_en_voice/kernel/inference/model_profile.dart';

// Synthetic fixtures only; never opens the user's vault or recordings.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'PDF and DOCX extraction and accelerated summaries',
    (tester) async {
      final temp = await Directory(
        '${(await getTemporaryDirectory()).path}/document_checks',
      ).create(recursive: true);
      final extractor = DocumentExtractor();
      final inference = LocalInferenceService();
      try {
        const facts =
            'Approved budget: 42750 dollars. Maya owns the audit. Deadline: October 16.';
        final pdf = pw.Document();
        pdf.addPage(pw.Page(build: (_) => pw.Text(facts)));
        final pdfFile = File('${temp.path}/budget.pdf');
        await pdfFile.writeAsBytes(await pdf.save());
        final pdfText = await extractor.extract(pdfFile.path);
        expect(pdfText.text, contains('42750'));
        expect(pdfText.text, contains('Maya'));
        expect(pdfText.warning, isEmpty);
        debugPrint('DOCUMENT_CHECK pdf_extraction=PASS');

        final archive = Archive();
        final xml = utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
<w:p><w:r><w:t>Approved budget: 42750 dollars.</w:t></w:r></w:p>
<w:p><w:r><w:t>Maya &amp; André own the audit.</w:t></w:r></w:p>
<w:p><w:del><w:r><w:delText>Rejected budget: 99999.</w:delText></w:r></w:del><w:r><w:t>Deadline: October 16.</w:t></w:r></w:p>
<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Table fact: approved.</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
</w:body></w:document>''');
        archive.addFile(ArchiveFile('word/document.xml', xml.length, xml));
        final wordFile = File('${temp.path}/budget.docx');
        await wordFile.writeAsBytes(ZipEncoder().encode(archive));
        final wordText = await extractor.extract(wordFile.path);
        expect(wordText.text, contains('Maya & André'));
        expect(wordText.text, contains('Table fact: approved.'));
        expect(wordText.text, isNot(contains('99999')));
        debugPrint('DOCUMENT_CHECK docx_tables_unicode_deleted_text=PASS');

        final blankPdf = pw.Document()
          ..addPage(pw.Page(build: (_) => pw.SizedBox()));
        final blank = File('${temp.path}/blank.pdf');
        await blank.writeAsBytes(await blankPdf.save());
        await expectLater(extractor.extract(blank.path), throwsStateError);
        final invalid = File('${temp.path}/invalid.docx');
        await invalid.writeAsString('not a zip archive');
        await expectLater(extractor.extract(invalid.path), throwsStateError);
        debugPrint('DOCUMENT_CHECK unreadable_rejection=PASS');

        await inference.loadModel();
        for (final entry in {
          'pdf': pdfText.text,
          'docx': wordText.text,
        }.entries) {
          final result = StringBuffer();
          await for (final token in inference.generateStream(
            '${entry.value}\nState the approved amount, owner and deadline in one sentence.',
            maxTokens: 128,
          )) {
            result.write(token.text);
          }
          expect(result.toString().replaceAll(',', ''), contains('42750'));
          expect(result.toString(), contains('Maya'));
          expect(result.toString(), contains('16'));
          debugPrint('DOCUMENT_CHECK ${entry.key}_${ModelProfile.gpu ? 'gpu' : 'npu'}_summary=PASS');
        }
      } finally {
        await inference.unloadModel();
        await temp.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
