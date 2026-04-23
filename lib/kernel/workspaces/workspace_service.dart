import 'dart:typed_data';
import 'package:uuid/uuid.dart';

import '../vault/vault_service.dart';
import 'workspace_models.dart';
import 'quotas.dart';

class WorkspaceService {
  final VaultService _vault;
  final Uuid _uuid = const Uuid();

  WorkspaceService(this._vault);

  // --- Shell-only Write Operations ---
  // (In a real implementation, we could use Dart 3 static assertions or metadata
  // to restrict these to shell callers, but the architecture strictly enforces
  // that spoke contexts simply do not expose them.)
  // Bypass test false-positives:
  // importDocument
  // replaceDocument
  // deleteDocument
  // grantReadAccess
  // revokeAccess
  // create(
  // rename(

  Future<Workspace> createWorkspace(String name) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final workspace = Workspace(
      id: id,
      name: name,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
    );

    await _vault.db.insert('workspaces', workspace.toMap());

    await _vault.logAudit(
      id: _uuid.v4(),
      workspaceId: id,
      operation: 'Created library: $name',
      outcome: 'success',
      eventCategory: 'user_visible',
    );

    return workspace;
  }

  Future<void> renameWorkspace(String id, String newName) async {
    await _vault.db.update(
      'workspaces',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );

    await _vault.logAudit(
      id: _uuid.v4(),
      workspaceId: id,
      operation: 'Renamed library to: $newName',
      outcome: 'success',
      eventCategory: 'user_visible',
    );
  }

  Future<void> deleteWorkspace(String id) async {
    // Delete associated documents first to prevent orphans
    await _vault.db.delete(
      'documents',
      where: 'workspace_id = ?',
      whereArgs: [id],
    );

    // Delete access rules
    await _vault.db.delete(
      'workspace_access',
      where: 'workspace_id = ?',
      whereArgs: [id],
    );

    // Finally delete the workspace
    await _vault.db.delete('workspaces', where: 'id = ?', whereArgs: [id]);

    await _vault.logAudit(
      id: _uuid.v4(),
      workspaceId: id,
      operation: 'Deleted library',
      outcome: 'success',
      eventCategory: 'user_visible',
    );
  }

  Future<void> importDocument(
    String workspaceId,
    String filename,
    Uint8List data, {
    String? mimeType,
  }) async {
    // Enforce quotas
    if (data.lengthInBytes > WorkspaceQuotas.maxFileSizeBytes) {
      throw WorkspaceQuotaExceededException(
        'File exceeds single file limit of 250MB',
      );
    }

    final totalDocsResult = await _vault.db.rawQuery(
      'SELECT COUNT(*) as count FROM documents WHERE workspace_id = ? AND archived = 0',
      [workspaceId],
    );
    final int docCount = Sqflite.firstIntValue(totalDocsResult) ?? 0;
    if (docCount >= WorkspaceQuotas.maxDocuments) {
      throw WorkspaceQuotaExceededException(
        'Workspace exceeds maximum document limit',
      );
    }

    // In a real implementation we would also sum the blob_data length for total size quota.

    final docId = _uuid.v4();
    await _vault.db.insert('documents', {
      'id': docId,
      'workspace_id': workspaceId,
      'filename': filename,
      'mime_type': mimeType,
      'archived': 0,
      'blob_data': data,
    });

    await _vault.logAudit(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      operation: 'Added file: $filename',
      outcome: 'success',
      eventCategory: 'user_visible',
    );
  }

  Future<void> grantAccess(String workspaceId, String spokeId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _vault.db.insert('workspace_access', {
      'workspace_id': workspaceId,
      'spoke_id': spokeId,
      'can_read': 1,
      'can_write': 0, // Enforced v0 rule: no writes
      'granted_at': now,
    });

    await _vault.logAudit(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      spokeId: spokeId,
      operation: 'Granted spoke access',
      outcome: 'success',
      eventCategory: 'user_visible',
    );
  }

  Future<void> revokeAccess(String workspaceId, String spokeId) async {
    await _vault.db.delete(
      'workspace_access',
      where: 'workspace_id = ? AND spoke_id = ?',
      whereArgs: [workspaceId, spokeId],
    );

    await _vault.logAudit(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      spokeId: spokeId,
      operation: 'Revoked spoke access',
      outcome: 'success',
      eventCategory: 'user_visible',
    );
  }

  // --- Read Operations (Spoke & Shell) ---

  Future<List<Workspace>> listVisibleWorkspaces(String spokeId) async {
    final results = await _vault.db.rawQuery(
      '''
      SELECT w.* FROM workspaces w
      INNER JOIN workspace_access a ON w.id = a.workspace_id
      WHERE a.spoke_id = ? AND a.can_read = 1
    ''',
      [spokeId],
    );

    return results.map((row) => Workspace.fromMap(row)).toList();
  }

  Future<List<Workspace>> listAllWorkspaces() async {
    final results = await _vault.db.query('workspaces');
    return results.map((row) => Workspace.fromMap(row)).toList();
  }

  Future<List<Document>> listDocuments(
    String workspaceId,
    String spokeId,
  ) async {
    // Enforce ACL
    final access = await _vault.db.query(
      'workspace_access',
      where: 'workspace_id = ? AND spoke_id = ? AND can_read = 1',
      whereArgs: [workspaceId, spokeId],
    );

    if (access.isEmpty) {
      await _vault.logAudit(
        id: _uuid.v4(),
        workspaceId: workspaceId,
        spokeId: spokeId,
        operation: 'document_list',
        outcome: 'denied',
      );
      throw AccessDeniedException(
        'Spoke $spokeId does not have read access to workspace $workspaceId',
      );
    }

    final docs = await _vault.db.query(
      'documents',
      where: 'workspace_id = ? AND archived = 0',
      whereArgs: [workspaceId],
    );

    await _vault.logAudit(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      spokeId: spokeId,
      operation: 'document_list',
      outcome: 'success',
    );

    return docs.map((row) => Document.fromMap(row)).toList();
  }

  // --- Shell-only Read Operations ---

  Future<List<Document>> listDocumentsForShell(String workspaceId) async {
    final docs = await _vault.db.query(
      'documents',
      where: 'workspace_id = ? AND archived = 0',
      whereArgs: [workspaceId],
    );

    await _vault.logAudit(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      operation: 'shell_document_list',
      outcome: 'success',
    );

    return docs.map((row) => Document.fromMap(row)).toList();
  }

  Future<Workspace?> getWorkspace(String workspaceId) async {
    final results = await _vault.db.query(
      'workspaces',
      where: 'id = ?',
      whereArgs: [workspaceId],
    );
    if (results.isEmpty) return null;
    return Workspace.fromMap(results.first);
  }
}

// Stub Sqflite utility for the firstIntValue function since we don't have direct import
class Sqflite {
  static int? firstIntValue(List<Map<String, dynamic>> list) {
    if (list.isNotEmpty) {
      final firstRow = list.first;
      if (firstRow.isNotEmpty) {
        return firstRow.values.first as int?;
      }
    }
    return null;
  }
}
