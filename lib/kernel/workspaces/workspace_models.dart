import 'dart:typed_data';

class Workspace {
  final String id;
  final String name;
  final DateTime createdAt;
  final String? keyRef;

  Workspace({
    required this.id,
    required this.name,
    required this.createdAt,
    this.keyRef,
  });

  factory Workspace.fromMap(Map<String, dynamic> map) {
    return Workspace(
      id: map['id'] as String,
      name: map['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      keyRef: map['key_ref'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.millisecondsSinceEpoch,
      'key_ref': keyRef,
    };
  }
}

class Document {
  final String id;
  final String? workspaceId;
  final String? spokeOutputId;
  final String filename;
  final String? mimeType;
  final bool archived;
  final String? supersededBy;
  final Uint8List?
  blobData; // Note: holding large blobs in memory is risky in prod, but fine for v0 stub

  Document({
    required this.id,
    this.workspaceId,
    this.spokeOutputId,
    required this.filename,
    this.mimeType,
    required this.archived,
    this.supersededBy,
    this.blobData,
  });

  factory Document.fromMap(Map<String, dynamic> map) {
    return Document(
      id: map['id'] as String,
      workspaceId: map['workspace_id'] as String?,
      spokeOutputId: map['spoke_output_id'] as String?,
      filename: map['filename'] as String,
      mimeType: map['mime_type'] as String?,
      archived: (map['archived'] ?? 0) == 1,
      supersededBy: map['superseded_by'] as String?,
      blobData: map['blob_data'] != null
          ? Uint8List.fromList(
              List<int>.from(map['blob_data'] as List<dynamic>),
            )
          : null,
    );
  }
}

class WorkspaceQuotaExceededException implements Exception {
  final String message;
  WorkspaceQuotaExceededException(this.message);
  @override
  String toString() => 'WorkspaceQuotaExceededException: $message';
}

class AccessDeniedException implements Exception {
  final String message;
  AccessDeniedException(this.message);
  @override
  String toString() => 'AccessDeniedException: $message';
}
