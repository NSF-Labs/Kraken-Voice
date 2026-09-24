import 'dart:io';
import 'summary_draft_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../kernel/vault/vault_service.dart';
import '../kernel/documents/document_extractor.dart';

class ImportedDocument {
  final String id, folderId, title, path, type, text, warning;
  final String? summary;
  final DateTime createdAt;
  ImportedDocument.fromMap(Map<String, dynamic> row)
    : id = row['id'],
      folderId = row['folder_id'],
      title = row['title'],
      path = row['file_path'],
      type = row['file_type'],
      text = row['extracted_text'],
      warning = row['extraction_warning'] ?? '',
      summary = row['summary_text'],
      createdAt = DateTime.fromMillisecondsSinceEpoch(row['created_at']);
}

class DocumentRepository {
  final VaultService vault;
  final DocumentExtractor extractor;
  final Future<Directory> Function() storageDirectory;
  DocumentRepository(
    this.vault, {
    DocumentExtractor? extractor,
    Future<Directory> Function()? storageDirectory,
  }) : extractor = extractor ?? DocumentExtractor(),
       storageDirectory = storageDirectory ?? getApplicationDocumentsDirectory;

  Future<List<ImportedDocument>> inFolder(String folderId) async =>
      (await vault.db.query(
        'imported_documents',
        where: 'folder_id = ?',
        whereArgs: [folderId],
        orderBy: 'created_at DESC',
      )).map(ImportedDocument.fromMap).toList();

  Future<ImportedDocument> importFile(
    String source,
    String filename,
    String folderId,
  ) async {
    final ext = p.extension(filename).toLowerCase();
    if (!['.pdf', '.docx'].contains(ext)) {
      throw StateError('Choose a PDF or Word .docx document.');
    }
    final input = File(source);
    if (await input.length() > 50 * 1024 * 1024) {
      throw StateError('Choose a document smaller than 50 MB.');
    }
    final dir = Directory(
      p.join((await storageDirectory()).path, 'imported_documents'),
    );
    await dir.create(recursive: true);
    final id = const Uuid().v4();
    final file = File(p.join(dir.path, '$id$ext'));
    try {
      await input.copy(file.path);
      final extracted = await extractor.extract(file.path);
      final row = <String, Object?>{
        'id': id,
        'folder_id': folderId,
        'title': p.basenameWithoutExtension(filename),
        'file_path': file.path,
        'file_type': ext.substring(1),
        'extracted_text': extracted.text,
        'extraction_warning': extracted.warning,
        'summary_text': null,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
      await vault.db.insert('imported_documents', row);
      return ImportedDocument.fromMap(row);
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<void> saveSummary(String id, String summary) async {
    await vault.db.update(
      'imported_documents',
      {'summary_text': summary},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(ImportedDocument document) async {
    final file = File(document.path);
    if (await file.exists()) await file.delete();
    await SummaryDraftRepository(vault).clear('document:${document.id}');
    await vault.db.delete(
      'imported_documents',
      where: 'id = ?',
      whereArgs: [document.id],
    );
  }
}
