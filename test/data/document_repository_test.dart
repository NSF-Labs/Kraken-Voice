import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/data/document_repository.dart';
import 'package:krak_en_voice/data/recording_repository.dart';
import 'package:krak_en_voice/kernel/documents/document_extractor.dart';
import 'recording_safety_test.dart' show MemoryDatabase, MemoryVault;

class TestExtractor extends DocumentExtractor {
  bool fail = false;
  @override
  Future<ExtractedDocument> extract(String path) async {
    expect(await File(path).exists(), true);
    if (fail) throw StateError('No readable text');
    return const ExtractedDocument('Budget 42750; Maya; October 16.', '');
  }
}

void main() {
  late Directory temp;
  late MemoryDatabase db;
  late MemoryVault vault;
  late TestExtractor extractor;
  late DocumentRepository repository;
  late File original;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kraken-doc-test');
    vault = MemoryVault();
    db = vault.db;
    extractor = TestExtractor();
    repository = DocumentRepository(
      vault,
      extractor: extractor,
      storageDirectory: () async => temp,
    );
    original = File('${temp.path}/original.pdf');
    await original.writeAsString('Synthetic document');
  });
  tearDown(() => temp.delete(recursive: true));

  test('imports durable copy and extracted text without audio jobs', () async {
    final doc = await repository.importFile(
      original.path,
      'Budget.PDF',
      'unfiled',
    );
    expect(doc.type, 'pdf');
    expect(doc.text, contains('Maya'));
    expect(doc.path, isNot(original.path));
    expect(db.rows('recordings'), isEmpty);
    expect(db.rows('transcription_jobs'), isEmpty);
    await repository.saveSummary(doc.id, 'Saved summary');
    expect(
      (await repository.inFolder('unfiled')).single.summary,
      'Saved summary',
    );
    await repository.delete(doc);
    expect(await File(doc.path).exists(), false);
    expect(await original.exists(), true);
  });
  test('failed extraction leaves no imported copy or database row', () async {
    extractor.fail = true;
    await expectLater(
      repository.importFile(original.path, 'bad.pdf', 'unfiled'),
      throwsStateError,
    );
    expect(db.rows('imported_documents'), isEmpty);
    expect(
      await Directory('${temp.path}/imported_documents').list().toList(),
      isEmpty,
    );
    expect(await original.exists(), true);
  });
  test(
    'folder move and deletion include documents and preserve originals',
    () async {
      final doc = await repository.importFile(
        original.path,
        'Budget.pdf',
        'folder-a',
      );
      final folders = FolderRepository(vault);
      await folders.deleteFolder('folder-a', moveToFolderId: 'folder-b');
      expect((await repository.inFolder('folder-b')).single.id, doc.id);
      await folders.deleteFolder('folder-b');
      expect(db.rows('imported_documents'), isEmpty);
      expect(await File(doc.path).exists(), false);
      expect(await original.exists(), true);
    },
  );
}
