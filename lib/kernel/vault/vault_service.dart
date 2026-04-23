import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class VaultService {
  Database? _db;
  bool get isOpen => _db != null;

  /// Opens the encrypted SQLite database using the derived 32-byte key.
  Future<void> openVault(Uint8List key) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = join(docsDir.path, 'kraken.db');

    // sqlcipher expects PRAGMA key to be hex-encoded if passing raw bytes
    final hexKey =
        "x'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'";

    _db = await openDatabase(
      dbPath,
      password: hexKey,
      version: 11,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE entities (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        data TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE workspaces (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        key_ref TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE documents (
        id TEXT PRIMARY KEY,
        workspace_id TEXT,
        spoke_output_id TEXT,
        filename TEXT NOT NULL,
        mime_type TEXT,
        archived INTEGER NOT NULL DEFAULT 0,
        superseded_by TEXT,
        blob_data BLOB
      )
    ''');
    await db.execute('''
      CREATE TABLE workspace_access (
        workspace_id TEXT NOT NULL,
        spoke_id TEXT NOT NULL,
        can_read INTEGER NOT NULL DEFAULT 0,
        can_write INTEGER NOT NULL DEFAULT 0,
        granted_at INTEGER NOT NULL,
        PRIMARY KEY (workspace_id, spoke_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE spoke_outputs (
        id TEXT PRIMARY KEY,
        spoke_id TEXT NOT NULL,
        document_id TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE spoke_data (
        spoke_id TEXT NOT NULL,
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        PRIMARY KEY (spoke_id, key)
      )
    ''');
    await db.execute('''
      CREATE TABLE audit_log (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        spoke_id TEXT,
        workspace_id TEXT,
        operation TEXT NOT NULL,
        outcome TEXT NOT NULL,
        event_category TEXT DEFAULT 'system'
      )
    ''');
    await db.execute('''
      CREATE TABLE transcription_jobs (
        id TEXT PRIMARY KEY,
        audio_path TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        started_at INTEGER,
        completed_at INTEGER,
        transcription_text TEXT,
        summary_json TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE recordings (
        id TEXT PRIMARY KEY,
        folder_id TEXT NOT NULL,
        title TEXT NOT NULL,
        audio_path TEXT NOT NULL,
        duration_ms INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        meeting_date INTEGER,
        source TEXT,
        retention_policy TEXT NOT NULL DEFAULT '90_day',
        audio_deleted_at INTEGER,
        audio_deleted_reason TEXT,
        FOREIGN KEY(folder_id) REFERENCES folders(id)
      )
    ''');
    // Insert default folder
    await db.insert('folders', {
      'id': 'unfiled',
      'name': 'Unfiled',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'is_default': 1,
    });
    await db.execute('''
      CREATE TABLE summary_versions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        audio_path TEXT NOT NULL,
        summary_json TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE recording_tags (
        id TEXT PRIMARY KEY,
        recording_id TEXT NOT NULL,
        tag TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(recording_id) REFERENCES recordings(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_recording_tags_recording ON recording_tags(recording_id)');
    await db.execute('CREATE INDEX idx_recording_tags_tag ON recording_tags(tag)');
    await db.execute('''
      CREATE TABLE action_items (
        id TEXT PRIMARY KEY,
        recording_id TEXT NOT NULL,
        text TEXT NOT NULL,
        is_done INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(recording_id) REFERENCES recordings(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_action_items_recording ON action_items(recording_id)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE audit_log ADD COLUMN event_category TEXT DEFAULT "system"',
      );
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE transcription_jobs (
          id TEXT PRIMARY KEY,
          audio_path TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          started_at INTEGER,
          completed_at INTEGER,
          transcription_text TEXT,
          summary_json TEXT
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE transcription_jobs ADD COLUMN summary_json TEXT',
      );
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE folders (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          is_default INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE recordings (
          id TEXT PRIMARY KEY,
          folder_id TEXT NOT NULL,
          title TEXT NOT NULL,
          audio_path TEXT NOT NULL,
          duration_ms INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY(folder_id) REFERENCES folders(id)
        )
      ''');
      // Insert default folder
      await db.insert('folders', {
        'id': 'unfiled',
        'name': 'Unfiled',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'is_default': 1,
      });
    }
    if (oldVersion < 6) {
      await db.execute(
        "ALTER TABLE recordings ADD COLUMN source TEXT",
      );
    }
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS summary_versions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          audio_path TEXT NOT NULL,
          summary_json TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS recording_tags (
          id TEXT PRIMARY KEY,
          recording_id TEXT NOT NULL,
          tag TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY(recording_id) REFERENCES recordings(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_recording_tags_recording ON recording_tags(recording_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_recording_tags_tag ON recording_tags(tag)');
    }
    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS action_items (
          id TEXT PRIMARY KEY,
          recording_id TEXT NOT NULL,
          text TEXT NOT NULL,
          is_done INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          FOREIGN KEY(recording_id) REFERENCES recordings(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_action_items_recording ON action_items(recording_id)');
    }
    if (oldVersion < 10) {
      await db.execute("ALTER TABLE recordings ADD COLUMN retention_policy TEXT NOT NULL DEFAULT '90_day'");
      await db.execute("ALTER TABLE recordings ADD COLUMN audio_deleted_at INTEGER");
      await db.execute("ALTER TABLE recordings ADD COLUMN audio_deleted_reason TEXT");
    }
    if (oldVersion < 11) {
      await db.execute("ALTER TABLE recordings ADD COLUMN meeting_date INTEGER");
      // Backfill: set meeting_date = created_at for existing recordings
      await db.execute("UPDATE recordings SET meeting_date = created_at WHERE meeting_date IS NULL");
    }
  }

  Future<void> closeVault() async {
    await _db?.close();
    _db = null;
  }

  Database get db {
    if (_db == null) throw StateError('Vault is not open');
    return _db!;
  }

  // --- Basic Vault Operations ---

  Future<void> writeSpokeData(String spokeId, String key, String value) async {
    await db.insert('spoke_data', {
      'spoke_id': spokeId,
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> readSpokeData(String spokeId, String key) async {
    final result = await db.query(
      'spoke_data',
      columns: ['value'],
      where: 'spoke_id = ? AND key = ?',
      whereArgs: [spokeId, key],
    );
    if (result.isNotEmpty) {
      return result.first['value'] as String;
    }
    return null;
  }

  Future<void> logAudit({
    required String id,
    String? spokeId,
    String? workspaceId,
    required String operation,
    required String outcome,
    String eventCategory = 'system',
  }) async {
    await db.insert('audit_log', {
      'id': id,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'spoke_id': spokeId,
      'workspace_id': workspaceId,
      'operation': operation,
      'outcome': outcome,
      'event_category': eventCategory,
    });
  }

  Future<List<Map<String, dynamic>>> getAuditLogs({
    int limit = 50,
    String? category,
  }) async {
    return await db.query(
      'audit_log',
      where: category != null ? 'event_category = ?' : null,
      whereArgs: category != null ? [category] : null,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  /// Write to the shared entity store. Restricted to allowed types.
  Future<void> writeEntity(
    String id,
    String type,
    Map<String, dynamic> data,
  ) async {
    const allowedTypes = {'contact', 'company', 'deal'};
    if (!allowedTypes.contains(type)) {
      throw ArgumentError('Entity type $type is not allowed in v0.');
    }
    await db.insert('entities', {
      'id': id,
      'entity_type': type,
      'data': jsonEncode(data),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> get vaultExists async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = join(docsDir.path, 'kraken.db');
    return File(dbPath).exists();
  }
}
