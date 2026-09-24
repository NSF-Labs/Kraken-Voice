import 'dart:convert';
import 'document_repository.dart';
import 'summary_draft_repository.dart';
import 'dart:io';
import 'package:krak_en_voice/kernel/kernel.dart';
import 'package:krak_en_voice/inference/model_manager.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

class Folder {
  final String id;
  final String name;
  final DateTime createdAt;
  final bool isDefault;

  Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.isDefault = false,
  });

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'],
      name: map['name'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
      isDefault: map['is_default'] == 1,
    );
  }
}

class Recording {
  final String id;
  final String folderId;
  final String title;
  final String audioPath;
  final int durationMs;
  final DateTime createdAt;
  final String? source;

  // Meaningful date: user-editable, defaults to createdAt
  final DateTime meetingDate;

  // Implicitly joined from transcription_jobs
  final String? transcriptionStatus;

  // Retention fields
  final String
  retentionPolicy; // '90_day', 'delete_after_transcription', 'keep_forever'
  final DateTime? audioDeletedAt;
  final String?
  audioDeletedReason; // 'retention_policy', 'storage_cap', 'user_deleted'

  // H3-06: Track last access for LRU retention ordering
  final DateTime? lastAccess;

  // Trash system: soft-delete with 30-day TTL
  final bool isTrashed;
  final DateTime? trashedAt;

  bool get isAudioDeleted => audioDeletedAt != null;

  Recording({
    required this.id,
    required this.folderId,
    required this.title,
    required this.audioPath,
    required this.durationMs,
    required this.createdAt,
    DateTime? meetingDate,
    this.source,
    this.transcriptionStatus,
    this.retentionPolicy = '90_day',
    this.audioDeletedAt,
    this.audioDeletedReason,
    this.lastAccess,
    this.isTrashed = false,
    this.trashedAt,
  }) : meetingDate = meetingDate ?? createdAt;

  factory Recording.fromMap(Map<String, dynamic> map) {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(map['created_at']);
    return Recording(
      id: map['id'],
      folderId: map['folder_id'],
      title: map['title'],
      audioPath: map['audio_path'],
      durationMs: map['duration_ms'],
      createdAt: createdAt,
      meetingDate: map['meeting_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['meeting_date'] as int)
          : createdAt,
      source: map['source'],
      transcriptionStatus: map['status'],
      retentionPolicy: map['retention_policy'] as String? ?? '90_day',
      audioDeletedAt: map['audio_deleted_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['audio_deleted_at'] as int)
          : null,
      audioDeletedReason: map['audio_deleted_reason'] as String?,
      lastAccess: map['last_access'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_access'] as int)
          : null,
      isTrashed: (map['is_trashed'] as int?) == 1,
      trashedAt: map['trashed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['trashed_at'] as int)
          : null,
    );
  }
}

enum DateFilter { all, today, thisWeek, thisMonth, custom }

enum SortField { date, duration, title }

class FolderRepository {
  final VaultService _vault;

  FolderRepository(this._vault);
  SummaryDraftRepository get summaryDrafts => SummaryDraftRepository(_vault);

  Future<List<Folder>> getFolders() async {
    final results = await _vault.db.query(
      'folders',
      orderBy: 'is_default DESC, name ASC',
    );
    return results.map((e) => Folder.fromMap(e)).toList();
  }

  Future<Folder> createFolder(String name) async {
    final folder = Folder(
      id: const Uuid().v4(),
      name: name,
      createdAt: DateTime.now(),
      isDefault: false,
    );

    await _vault.db.insert('folders', {
      'id': folder.id,
      'name': folder.name,
      'created_at': folder.createdAt.millisecondsSinceEpoch,
      'is_default': folder.isDefault ? 1 : 0,
    });

    return folder;
  }

  Future<void> renameFolder(String id, String newName) async {
    await _vault.db.update(
      'folders',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteFolder(String id, {String? moveToFolderId}) async {
    if (id == 'unfiled') return; // Default cannot be deleted

    if (moveToFolderId != null) {
      await _vault.db.update(
        'recordings',
        {'folder_id': moveToFolderId},
        where: 'folder_id = ?',
        whereArgs: [id],
      );
    } else {
      // Include trashed recordings, not just the currently visible folder list.
      final recordings = await _vault.db.query(
        'recordings',
        columns: ['id'],
        where: 'folder_id = ?',
        whereArgs: [id],
      );
      for (final recording in recordings) {
        await deleteRecording(recording['id'] as String);
      }
    }

    if (moveToFolderId != null) {
      await _vault.db.update(
        'imported_documents',
        {'folder_id': moveToFolderId},
        where: 'folder_id = ?',
        whereArgs: [id],
      );
    } else {
      final documents = DocumentRepository(_vault);
      for (final document in await documents.inFolder(id)) {
        await documents.delete(document);
      }
    }
    await _vault.db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Recording>> getRecordingsForFolder(
    String folderId, {
    DateFilter dateFilter = DateFilter.all,
    DateTime? customStart,
    DateTime? customEnd,
    SortField sortField = SortField.date,
    bool sortAscending = false,
  }) async {
    // Build date filter clause
    String dateClause = '';
    List<dynamic> dateArgs = [];
    if (dateFilter != DateFilter.all) {
      final now = DateTime.now();
      late int sinceMs;
      if (dateFilter == DateFilter.today) {
        sinceMs = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      } else if (dateFilter == DateFilter.thisWeek) {
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        sinceMs = DateTime(
          weekStart.year,
          weekStart.month,
          weekStart.day,
        ).millisecondsSinceEpoch;
      } else if (dateFilter == DateFilter.thisMonth) {
        sinceMs = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
      } else if (dateFilter == DateFilter.custom && customStart != null) {
        sinceMs = customStart.millisecondsSinceEpoch;
      } else {
        sinceMs = 0;
      }
      dateClause = ' AND r.created_at >= ?';
      dateArgs.add(sinceMs);
      if (dateFilter == DateFilter.custom && customEnd != null) {
        dateClause += ' AND r.created_at <= ?';
        dateArgs.add(customEnd.millisecondsSinceEpoch);
      }
    }

    // Build sort clause
    String orderBy;
    final dir = sortAscending ? 'ASC' : 'DESC';
    switch (sortField) {
      case SortField.duration:
        orderBy = 'r.duration_ms $dir';
        break;
      case SortField.title:
        orderBy = 'r.title COLLATE NOCASE $dir';
        break;
      case SortField.date:
        orderBy = 'r.created_at $dir';
    }

    final results = await _vault.db.rawQuery(
      '''
      SELECT r.*, tj.status
      FROM recordings r
      LEFT JOIN transcription_jobs tj ON r.audio_path = tj.audio_path
      WHERE r.folder_id = ? AND r.is_trashed = 0$dateClause
      ORDER BY $orderBy
    ''',
      [folderId, ...dateArgs],
    );

    return results.map((e) => Recording.fromMap(e)).toList();
  }

  /// Returns all non-trashed recordings, ordered by most recent first.
  /// Used by ChatService to build a full recording inventory for AI context.
  Future<List<Recording>> getAllRecordings() async {
    final results = await _vault.db.rawQuery('''
      SELECT r.*, tj.status
      FROM recordings r
      LEFT JOIN transcription_jobs tj ON r.audio_path = tj.audio_path
      WHERE r.is_trashed = 0
      ORDER BY r.created_at DESC
    ''');
    return results.map((e) => Recording.fromMap(e)).toList();
  }

  Future<Recording> createRecording({
    required String title,
    required String audioPath,
    required int durationMs,
    String folderId = 'unfiled',
    String? source,
  }) async {
    final retentionPolicy = await PreferencesService()
        .getDefaultRetentionPolicy();
    final rec = Recording(
      id: const Uuid().v4(),
      folderId: folderId,
      title: title,
      audioPath: audioPath,
      durationMs: durationMs,
      createdAt: DateTime.now(),
      source: source,
      retentionPolicy: retentionPolicy,
    );

    await _vault.db.insert('recordings', {
      'id': rec.id,
      'folder_id': rec.folderId,
      'title': rec.title,
      'audio_path': rec.audioPath,
      'duration_ms': rec.durationMs,
      'created_at': rec.createdAt.millisecondsSinceEpoch,
      'meeting_date': rec.meetingDate.millisecondsSinceEpoch,
      'source': rec.source,
      'retention_policy': rec.retentionPolicy,
    });

    return rec;
  }

  Future<void> moveRecording(String recordingId, String newFolderId) async {
    await _vault.db.update(
      'recordings',
      {'folder_id': newFolderId},
      where: 'id = ?',
      whereArgs: [recordingId],
    );
  }

  Future<void> renameRecording(String recordingId, String newTitle) async {
    await _vault.db.update(
      'recordings',
      {'title': newTitle},
      where: 'id = ?',
      whereArgs: [recordingId],
    );
  }

  /// Update the user-editable meeting date for a recording.
  Future<void> setMeetingDate(String recordingId, DateTime date) async {
    await _vault.db.update(
      'recordings',
      {'meeting_date': date.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [recordingId],
    );
  }

  /// Returns the highest severity state level for a folder
  /// 0 = Clear, 1 = Pending, 2 = Attention (Failed)
  Future<int> getFolderStateLevel(String folderId) async {
    final result = await _vault.db.rawQuery(
      '''
      SELECT MAX(
        CASE 
          WHEN tj.status = 'failed' THEN 2 
          WHEN tj.status = 'pending' OR tj.status = 'processing' THEN 1 
          ELSE 0 
        END
      ) as state_level
      FROM recordings r
      LEFT JOIN transcription_jobs tj ON r.audio_path = tj.audio_path
      WHERE r.folder_id = ?
    ''',
      [folderId],
    );

    if (result.isEmpty || result.first['state_level'] == null) return 0;
    return result.first['state_level'] as int;
  }

  Future<String?> getTranscriptionText(String audioPath) async {
    final result = await _vault.db.query(
      'transcription_jobs',
      columns: ['transcription_text'],
      where: 'audio_path = ?',
      whereArgs: [audioPath],
    );
    if (result.isNotEmpty && result.first['transcription_text'] != null) {
      return result.first['transcription_text'] as String;
    }
    return null;
  }

  /// Returns the per-segment Whisper output (with audio-time boundaries)
  /// for a recording, or null if none was persisted (e.g. transcribed before
  /// schema v16, or transcription failed).
  Future<List<WhisperSegment>?> getTranscriptionSegments(
    String audioPath,
  ) async {
    final result = await _vault.db.query(
      'transcription_jobs',
      columns: ['transcription_segments_json'],
      where: 'audio_path = ?',
      whereArgs: [audioPath],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    final raw = result.first['transcription_segments_json'] as String?;
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => WhisperSegment.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  // H1-30: Update transcript text after user edits
  Future<void> updateTranscriptionText(String audioPath, String newText) async {
    await _vault.db.update(
      'transcription_jobs',
      {'transcription_text': newText, 'user_corrected': 1},
      where: 'audio_path = ?',
      whereArgs: [audioPath],
    );
  }

  // H1-31: Check if transcript has been user-corrected
  Future<bool> isTranscriptUserCorrected(String audioPath) async {
    final result = await _vault.db.query(
      'transcription_jobs',
      columns: ['user_corrected'],
      where: 'audio_path = ?',
      whereArgs: [audioPath],
    );
    if (result.isNotEmpty) {
      return (result.first['user_corrected'] as int?) == 1;
    }
    return false;
  }

  Future<String?> getSummaryJson(String audioPath) async {
    final result = await _vault.db.query(
      'transcription_jobs',
      columns: ['summary_json'],
      where: 'audio_path = ?',
      whereArgs: [audioPath],
    );
    if (result.isNotEmpty && result.first['summary_json'] != null) {
      return result.first['summary_json'] as String;
    }
    return null;
  }

  Future<void> saveSummaryJson(String audioPath, String jsonStr) async {
    // Archive the current summary before overwriting (if one exists)
    final current = await getSummaryJson(audioPath);
    if (current != null) {
      await _vault.db.insert('summary_versions', {
        'audio_path': audioPath,
        'summary_json': current,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      // Keep only the last 5 versions
      final versions = await _vault.db.query(
        'summary_versions',
        where: 'audio_path = ?',
        whereArgs: [audioPath],
        orderBy: 'created_at DESC',
      );
      if (versions.length > 5) {
        final idsToDelete = versions.sublist(5).map((v) => v['id']).toList();
        for (final id in idsToDelete) {
          await _vault.db.delete(
            'summary_versions',
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    }
    // Save new summary
    await _vault.db.update(
      'transcription_jobs',
      {'summary_json': jsonStr},
      where: 'audio_path = ?',
      whereArgs: [audioPath],
    );
  }

  /// Returns summary versions ordered newest-first (max 5).
  Future<List<Map<String, dynamic>>> getSummaryVersions(
    String audioPath,
  ) async {
    return await _vault.db.query(
      'summary_versions',
      where: 'audio_path = ?',
      whereArgs: [audioPath],
      orderBy: 'created_at DESC',
      limit: 5,
    );
  }

  /// Restores a previous summary version as the current active summary.
  Future<void> restoreSummaryVersion(
    String audioPath,
    String summaryJson,
  ) async {
    await saveSummaryJson(audioPath, summaryJson);
  }

  Future<void> deleteRecording(String recordingId) async {
    final rows = await _vault.db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [recordingId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final audioPath = rows.first['audio_path'] as String;
    final embeddingsPath = await getEmbeddingsPath(recordingId);

    // Keep the database entry if file deletion fails, so the user can retry.
    for (final path in [audioPath, '$audioPath.recording', ?embeddingsPath]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }

    await _vault.db.transaction((txn) async {
      await txn.delete(
        'summary_drafts',
        where: 'owner_key = ?',
        whereArgs: ['audio:$audioPath'],
      );
      for (final table in ['transcription_jobs', 'summary_versions']) {
        await txn.delete(
          table,
          where: 'audio_path = ?',
          whereArgs: [audioPath],
        );
      }
      // Explicit cleanup also works on databases without foreign keys enabled.
      for (final table in [
        'diarization_results',
        'speaker_labels',
        'recording_tags',
        'recording_chats',
        'action_items',
      ]) {
        await txn.delete(
          table,
          where: 'recording_id = ?',
          whereArgs: [recordingId],
        );
      }
      await txn.delete('recordings', where: 'id = ?', whereArgs: [recordingId]);
    });
  }

  Future<void> deleteRecordings(List<String> recordingIds) async {
    for (final id in recordingIds) {
      await deleteRecording(id);
    }
  }

  // ─── Trash (soft-delete) ──────────────────────────────────────────────────

  /// Soft-deletes a recording by moving it to trash. Preserves all data.
  Future<void> trashRecording(String recordingId) async {
    await _vault.db.update(
      'recordings',
      {'is_trashed': 1, 'trashed_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [recordingId],
    );
  }

  /// Soft-deletes multiple recordings.
  Future<void> trashRecordings(List<String> recordingIds) async {
    for (final id in recordingIds) {
      await trashRecording(id);
    }
  }

  /// Restores a recording from trash.
  Future<void> restoreRecording(String recordingId) async {
    await _vault.db.update(
      'recordings',
      {'is_trashed': 0, 'trashed_at': null},
      where: 'id = ?',
      whereArgs: [recordingId],
    );
  }

  /// Returns all trashed recordings, sorted by most recently trashed.
  Future<List<Recording>> getTrashedRecordings() async {
    final results = await _vault.db.rawQuery('''
      SELECT r.*, tj.status
      FROM recordings r
      LEFT JOIN transcription_jobs tj ON r.audio_path = tj.audio_path
      WHERE r.is_trashed = 1
      ORDER BY r.trashed_at DESC
    ''');
    return results.map((e) => Recording.fromMap(e)).toList();
  }

  /// Permanently deletes a trashed recording (irreversible).
  Future<void> permanentlyDeleteRecording(String recordingId) async {
    await deleteRecording(recordingId);
  }

  /// Permanently deletes ALL trashed recordings.
  Future<void> emptyTrash() async {
    final trashed = await getTrashedRecordings();
    for (final rec in trashed) {
      await deleteRecording(rec.id);
    }
  }

  /// Auto-cleans recordings that have been in trash for more than 30 days.
  /// Should be called on app startup.
  Future<int> autoCleanTrash() async {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    final expired = await _vault.db.rawQuery(
      '''
      SELECT id FROM recordings
      WHERE is_trashed = 1 AND trashed_at < ?
    ''',
      [cutoff],
    );

    for (final row in expired) {
      await deleteRecording(row['id'] as String);
    }
    return expired.length;
  }

  /// Full-text search across recording titles, transcripts, summaries, and tags.
  /// Returns recordings with matched snippet text for UI highlighting.
  Future<List<SearchResult>> searchRecordings(String query) async {
    if (query.trim().isEmpty) return [];

    final q = '%${query.trim()}%';

    final results = await _vault.db.rawQuery(
      '''
      SELECT DISTINCT r.*, tj.status, tj.transcription_text, tj.summary_json,
             f.name as folder_name
      FROM recordings r
      LEFT JOIN transcription_jobs tj ON r.audio_path = tj.audio_path
      LEFT JOIN folders f ON r.folder_id = f.id
      LEFT JOIN recording_tags rt ON r.id = rt.recording_id
      WHERE (r.title LIKE ? 
         OR tj.transcription_text LIKE ? 
         OR tj.summary_json LIKE ?
         OR rt.tag LIKE ?)
      AND r.is_trashed = 0
      ORDER BY r.created_at DESC
    ''',
      [q, q, q, q],
    );

    return results.map((row) {
      final recording = Recording.fromMap(row);
      final transcript = row['transcription_text'] as String?;
      final summary = row['summary_json'] as String?;
      final folderName = row['folder_name'] as String? ?? 'Unknown';

      // Find best snippet
      String? snippet;
      String matchSource = 'title';

      if (transcript != null &&
          transcript.toLowerCase().contains(query.toLowerCase())) {
        snippet = _extractSnippet(transcript, query);
        matchSource = 'transcript';
      } else if (summary != null &&
          summary.toLowerCase().contains(query.toLowerCase())) {
        snippet = _extractSnippet(summary, query);
        matchSource = 'summary';
      }

      return SearchResult(
        recording: recording,
        folderName: folderName,
        snippet: snippet,
        matchSource: matchSource,
        query: query.trim(),
      );
    }).toList();
  }

  /// Extracts a ~120 character window around the first match of [query] in [text].
  String _extractSnippet(String text, String query) {
    final lower = text.toLowerCase();
    final idx = lower.indexOf(query.toLowerCase());
    if (idx == -1) return text.substring(0, text.length.clamp(0, 120));

    final start = (idx - 50).clamp(0, text.length);
    final end = (idx + query.length + 70).clamp(0, text.length);

    String snippet = text.substring(start, end).replaceAll('\n', ' ');
    if (start > 0) snippet = '…$snippet';
    if (end < text.length) snippet = '$snippet…';
    return snippet;
  }

  // --- Tag Operations ---

  /// Returns all tags for a recording, ordered alphabetically.
  Future<List<String>> getTagsForRecording(String recordingId) async {
    final results = await _vault.db.query(
      'recording_tags',
      columns: ['tag'],
      where: 'recording_id = ?',
      whereArgs: [recordingId],
      orderBy: 'tag ASC',
    );
    return results.map((r) => r['tag'] as String).toList();
  }

  /// Replaces all tags for a recording with the given list.
  Future<void> setTagsForRecording(
    String recordingId,
    List<String> tags,
  ) async {
    // Clear existing
    await _vault.db.delete(
      'recording_tags',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
    );

    // Insert new
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final tag in tags) {
      final cleaned = tag.trim().toLowerCase();
      if (cleaned.isEmpty) continue;
      await _vault.db.insert('recording_tags', {
        'id': '${recordingId}_$cleaned',
        'recording_id': recordingId,
        'tag': cleaned,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Returns all unique tags across all recordings, with counts.
  Future<List<Map<String, dynamic>>> getAllTags() async {
    return await _vault.db.rawQuery('''
      SELECT tag, COUNT(*) as count
      FROM recording_tags
      GROUP BY tag
      ORDER BY count DESC, tag ASC
    ''');
  }

  /// Finds the recording ID for a given audio path.
  Future<String?> getRecordingIdByAudioPath(String audioPath) async {
    final result = await _vault.db.query(
      'recordings',
      columns: ['id'],
      where: 'audio_path = ?',
      whereArgs: [audioPath],
      limit: 1,
    );
    if (result.isNotEmpty) return result.first['id'] as String;
    return null;
  }

  // --- Action Item Operations (I3) ---

  /// Returns all action items across all recordings, with recording info.
  Future<List<ActionItem>> getAllActionItems() async {
    final results = await _vault.db.rawQuery('''
      SELECT ai.*, r.title as recording_title, r.folder_id
      FROM action_items ai
      JOIN recordings r ON ai.recording_id = r.id
      ORDER BY ai.is_done ASC, ai.created_at DESC
    ''');
    return results.map((r) => ActionItem.fromMap(r)).toList();
  }

  /// Returns action items for a specific recording.
  Future<List<ActionItem>> getActionItemsForRecording(
    String recordingId,
  ) async {
    final results = await _vault.db.rawQuery(
      '''
      SELECT ai.*, r.title as recording_title, r.folder_id
      FROM action_items ai
      JOIN recordings r ON ai.recording_id = r.id
      WHERE ai.recording_id = ?
      ORDER BY ai.is_done ASC, ai.created_at ASC
    ''',
      [recordingId],
    );
    return results.map((r) => ActionItem.fromMap(r)).toList();
  }

  /// Syncs action items from a summary JSON for a recording.
  /// Parses the action_items array and inserts new ones (avoids duplicates by text match).
  Future<void> syncActionItemsFromSummary(
    String recordingId,
    String summaryJson,
  ) async {
    try {
      final parsed = jsonDecode(summaryJson) as Map<String, dynamic>;
      final items = (parsed['action_items'] as List<dynamic>?) ?? [];
      if (items.isEmpty) return;

      final existing = await getActionItemsForRecording(recordingId);
      final existingTexts = existing
          .map((e) => e.text.toLowerCase().trim())
          .toSet();
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final item in items) {
        final text = item.toString().trim();
        if (text.isEmpty || existingTexts.contains(text.toLowerCase())) {
          continue;
        }
        await _vault.db.insert('action_items', {
          'id': const Uuid().v4(),
          'recording_id': recordingId,
          'text': text,
          'is_done': 0,
          'created_at': now,
        });
      }
    } catch (_) {}
  }

  /// Toggles the done state of an action item.
  Future<void> toggleActionItem(String actionItemId) async {
    final result = await _vault.db.query(
      'action_items',
      columns: ['is_done'],
      where: 'id = ?',
      whereArgs: [actionItemId],
      limit: 1,
    );
    if (result.isEmpty) return;
    final current = result.first['is_done'] as int;
    await _vault.db.update(
      'action_items',
      {'is_done': current == 0 ? 1 : 0},
      where: 'id = ?',
      whereArgs: [actionItemId],
    );
  }

  /// Deletes an action item.
  Future<void> deleteActionItem(String actionItemId) async {
    await _vault.db.delete(
      'action_items',
      where: 'id = ?',
      whereArgs: [actionItemId],
    );
  }

  /// Suggests the best folder for a recording based on its title and transcript snippet.
  /// Uses Gemma inference if available, falls back to tag frequency matching.
  /// Returns the suggested Folder, or null if no good match.
  Future<Folder?> suggestFolder(String title, String? transcriptSnippet) async {
    final folders = await getFolders();
    // Only suggest if there are 2+ user folders (exclude default if others exist)
    final userFolders = folders.where((f) => !f.isDefault).toList();
    if (userFolders.isEmpty) return null;

    // Build folder context: name + tags from their recordings
    final folderProfiles = <String, List<String>>{};
    for (final folder in userFolders) {
      final recs = await getRecordingsForFolder(folder.id);
      final allTags = <String>[];
      for (final rec in recs) {
        allTags.addAll(await getTagsForRecording(rec.id));
      }
      folderProfiles[folder.id] = allTags;
    }

    // Try Gemma-based suggestion
    try {
      final modelManager = ModelManager();
      if (await modelManager.hasModel()) {
        final inferenceService = LocalInferenceService();
        await inferenceService.loadModel();
        final folderDescriptions = userFolders
            .map((f) {
              final tags = folderProfiles[f.id] ?? [];
              return '${f.name}: ${tags.take(10).join(', ')}';
            })
            .join('\n');

        final snippet =
            transcriptSnippet != null && transcriptSnippet.length > 300
            ? transcriptSnippet.substring(0, 300)
            : (transcriptSnippet ?? '');

        final prompt =
            '''Given a recording titled "$title" with this transcript excerpt:
"$snippet"

Which folder is the best fit? Choose EXACTLY ONE folder name from the list below, or respond "none" if no folder fits.

Folders:
$folderDescriptions

Respond with only the folder name, nothing else.''';

        final buffer = StringBuffer();
        await for (final token in inferenceService.generateStream(
          prompt,
          maxTokens: 64,
        )) {
          buffer.write(token.text);
        }
        final suggestedName = buffer.toString().trim().toLowerCase();

        if (suggestedName != 'none') {
          for (final f in userFolders) {
            if (f.name.toLowerCase() == suggestedName) return f;
          }
        }
      }
    } catch (_) {}

    // Fallback: tag overlap scoring
    final titleWords = title
        .toLowerCase()
        .split(RegExp(r'\W+'))
        .where((w) => w.length > 3)
        .toSet();
    String? bestFolderId;
    int bestScore = 0;
    for (final entry in folderProfiles.entries) {
      int score = 0;
      for (final tag in entry.value) {
        if (titleWords.contains(tag.toLowerCase())) score += 2;
        if (title.toLowerCase().contains(tag.toLowerCase())) score += 1;
      }
      if (score > bestScore) {
        bestScore = score;
        bestFolderId = entry.key;
      }
    }

    if (bestFolderId != null && bestScore >= 2) {
      return userFolders.firstWhere((f) => f.id == bestFolderId);
    }
    return null;
  }

  // ─── Retention ──────────────────────────────────────────────────────────────

  /// Update the retention policy for a recording.
  Future<void> setRetentionPolicy(String recordingId, String policy) async {
    await _vault.db.update(
      'recordings',
      {'retention_policy': policy},
      where: 'id = ?',
      whereArgs: [recordingId],
    );
  }

  /// Mark a recording's audio as deleted (keeps transcript/summary).
  Future<void> markAudioDeleted(String recordingId, String reason) async {
    await _vault.db.update(
      'recordings',
      {
        'audio_deleted_at': DateTime.now().millisecondsSinceEpoch,
        'audio_deleted_reason': reason,
      },
      where: 'id = ?',
      whereArgs: [recordingId],
    );
  }

  // H3-06: Touch last_access timestamp when user views a recording
  Future<void> touchLastAccess(String recordingId) async {
    await _vault.db.update(
      'recordings',
      {'last_access': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [recordingId],
    );
  }

  /// Get all recordings eligible for retention sweep (audio not yet deleted).
  Future<List<RetentionCandidate>> getRetentionCandidates() async {
    final results = await _vault.db.rawQuery('''
      SELECT r.id, r.audio_path, r.retention_policy, r.created_at, r.last_access, tj.status
      FROM recordings r
      LEFT JOIN transcription_jobs tj ON r.audio_path = tj.audio_path
      WHERE r.audio_deleted_at IS NULL
      ORDER BY COALESCE(r.last_access, r.created_at) ASC
    ''');

    return results
        .map(
          (m) => RetentionCandidate(
            id: m['id'] as String,
            audioPath: m['audio_path'] as String,
            retentionPolicy: m['retention_policy'] as String? ?? '90_day',
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              m['created_at'] as int,
            ),
            lastAccess: m['last_access'] != null
                ? DateTime.fromMillisecondsSinceEpoch(m['last_access'] as int)
                : null,
            transcriptionStatus: m['status'] as String?,
          ),
        )
        .toList();
  }

  /// H3-14: Get recordings ordered by last_access for cap enforcement
  Future<List<Map<String, dynamic>>> getRecordingsWithAudioForCap() async {
    return await _vault.db.rawQuery('''
      SELECT id, audio_path, created_at, last_access
      FROM recordings
      WHERE audio_deleted_at IS NULL
      ORDER BY COALESCE(last_access, created_at) ASC
    ''');
  }

  /// H3-19: Get recordings with audio sorted by file size (largest first)
  Future<List<Map<String, dynamic>>> getRecordingsWithAudioBySize() async {
    return await _vault.db.rawQuery('''
      SELECT r.id, r.title, r.audio_path, r.duration_ms, r.created_at,
             r.retention_policy, r.folder_id
      FROM recordings r
      WHERE r.audio_deleted_at IS NULL
      ORDER BY r.duration_ms DESC
    ''');
  }

  // ─── Diarization data access ────────────────────────────────────────────────

  /// Saves a diarization result and generates default speaker labels.
  Future<void> saveDiarizationResult(
    String recordingId,
    DiarizationResult result,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final segmentsJson = jsonEncode(
      result.segments.map((s) => s.toJson()).toList(),
    );

    // Upsert diarization result
    await _vault.db.insert('diarization_results', {
      'recording_id': recordingId,
      'threshold': result.config.threshold,
      'min_duration': result.config.minDuration,
      'speaker_count': result.speakerCount,
      'segments_json': segmentsJson,
      'embeddings_path': result.embeddingsPath,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Generate default speaker labels (only if not already user-renamed)
    final existingLabels = await _vault.db.query(
      'speaker_labels',
      where: 'recording_id = ? AND is_user_renamed = 1',
      whereArgs: [recordingId],
    );
    final userRenamed = {
      for (final row in existingLabels)
        row['speaker_index'] as int: row['display_name'] as String,
    };

    // Clear old labels and re-generate
    await _vault.db.delete(
      'speaker_labels',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
    );

    final speakerIndices = result.segments.map((s) => s.speaker).toSet();
    for (final idx in speakerIndices) {
      final isRenamed = userRenamed.containsKey(idx);
      await _vault.db.insert('speaker_labels', {
        'id': '${recordingId}_$idx',
        'recording_id': recordingId,
        'speaker_index': idx,
        'display_name': isRenamed ? userRenamed[idx]! : 'Speaker ${idx + 1}',
        'is_user_renamed': isRenamed ? 1 : 0,
      });
    }
  }

  /// Returns the diarization segments for a recording, or null if none exist.
  Future<List<DiarizationSegment>?> getDiarizationSegments(
    String recordingId,
  ) async {
    final rows = await _vault.db.query(
      'diarization_results',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final segmentsJson = rows.first['segments_json'] as String;
    final segments = (jsonDecode(segmentsJson) as List<dynamic>)
        .map((s) => DiarizationSegment.fromJson(s as Map<String, dynamic>))
        .toList();
    return segments;
  }

  /// Returns speaker labels as {speakerIndex: displayName}.
  Future<Map<int, String>> getSpeakerLabels(String recordingId) async {
    final rows = await _vault.db.query(
      'speaker_labels',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
    );
    return {
      for (final row in rows)
        row['speaker_index'] as int: row['display_name'] as String,
    };
  }

  /// Renames a speaker label. This is a v1 user-facing action.
  Future<void> renameSpeaker(
    String recordingId,
    int speakerIndex,
    String newName,
  ) async {
    await _vault.db.update(
      'speaker_labels',
      {'display_name': newName, 'is_user_renamed': 1},
      where: 'recording_id = ? AND speaker_index = ?',
      whereArgs: [recordingId, speakerIndex],
    );
  }

  /// Returns the cached embeddings path for a recording, or null.
  Future<String?> getEmbeddingsPath(String recordingId) async {
    final rows = await _vault.db.query(
      'diarization_results',
      columns: ['embeddings_path'],
      where: 'recording_id = ?',
      whereArgs: [recordingId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['embeddings_path'] as String?;
  }

  /// Returns the diarization config used for a recording.
  Future<DiarizationConfig?> getDiarizationConfig(String recordingId) async {
    final rows = await _vault.db.query(
      'diarization_results',
      columns: ['threshold', 'min_duration'],
      where: 'recording_id = ?',
      whereArgs: [recordingId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DiarizationConfig(
      threshold: (rows.first['threshold'] as num).toDouble(),
      minDuration: (rows.first['min_duration'] as num).toDouble(),
    );
  }

  /// Cleans up diarization data for a recording (on deletion).
  Future<void> deleteDiarizationData(String recordingId) async {
    await _vault.db.delete(
      'diarization_results',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
    );
    await _vault.db.delete(
      'speaker_labels',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
    );
  }

  // ─── Chat persistence ──────────────────────────────────────────────────────

  /// Saves a complete chat conversation for a recording, replacing any existing one.
  Future<void> saveChatForRecording(
    String recordingId,
    List<Map<String, dynamic>> messages,
  ) async {
    // Clear previous chat for this recording
    await _vault.db.delete(
      'recording_chats',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
    );
    // Insert new messages
    for (final msg in messages) {
      await _vault.db.insert('recording_chats', {
        'recording_id': recordingId,
        'role': msg['role'] as String,
        'content': msg['content'] as String,
        'created_at':
            (msg['created_at'] as int?) ??
            DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// Loads the saved chat messages for a recording, ordered chronologically.
  Future<List<Map<String, dynamic>>> getChatForRecording(
    String recordingId,
  ) async {
    return await _vault.db.query(
      'recording_chats',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
      orderBy: 'created_at ASC',
    );
  }

  /// Checks whether a recording has any saved chat messages.
  Future<bool> hasChatForRecording(String recordingId) async {
    final result = await _vault.db.rawQuery(
      'SELECT COUNT(*) as cnt FROM recording_chats WHERE recording_id = ?',
      [recordingId],
    );
    return (result.first['cnt'] as int) > 0;
  }

  /// Clears the saved chat for a recording.
  Future<void> clearChatForRecording(String recordingId) async {
    await _vault.db.delete(
      'recording_chats',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
    );
  }

  /// Formats saved chat messages into a human-readable string for export.
  Future<String?> getExportableChatLog(String recordingId) async {
    final messages = await getChatForRecording(recordingId);
    if (messages.isEmpty) return null;

    final sb = StringBuffer();
    for (final msg in messages) {
      final role = msg['role'] as String;
      final content = msg['content'] as String;
      final ts = DateTime.fromMillisecondsSinceEpoch(msg['created_at'] as int);
      final label = role == 'user' ? 'You' : 'Kraken AI';
      final time =
          '${ts.hour.toString().padLeft(2, '0')}:'
          '${ts.minute.toString().padLeft(2, '0')}:'
          '${ts.second.toString().padLeft(2, '0')}';
      sb.writeln('[$time] $label:');
      sb.writeln(content);
      sb.writeln();
    }
    return sb.toString();
  }
}

class SearchResult {
  final Recording recording;
  final String folderName;
  final String? snippet;
  final String matchSource; // 'title', 'transcript', or 'summary'
  final String query;

  SearchResult({
    required this.recording,
    required this.folderName,
    this.snippet,
    required this.matchSource,
    required this.query,
  });
}

class ActionItem {
  final String id;
  final String recordingId;
  final String text;
  final bool isDone;
  final DateTime createdAt;
  final String? recordingTitle;
  final String? folderId;

  ActionItem({
    required this.id,
    required this.recordingId,
    required this.text,
    required this.isDone,
    required this.createdAt,
    this.recordingTitle,
    this.folderId,
  });

  factory ActionItem.fromMap(Map<String, dynamic> map) {
    return ActionItem(
      id: map['id'],
      recordingId: map['recording_id'],
      text: map['text'],
      isDone: map['is_done'] == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
      recordingTitle: map['recording_title'],
      folderId: map['folder_id'],
    );
  }
}

// ─── Retention data helpers ──────────────────────────────────────────────────

/// Lightweight struct returned by the retention sweep query.
class RetentionCandidate {
  final String id;
  final String audioPath;
  final String retentionPolicy;
  final DateTime createdAt;
  final DateTime? lastAccess;
  final String? transcriptionStatus;

  RetentionCandidate({
    required this.id,
    required this.audioPath,
    required this.retentionPolicy,
    required this.createdAt,
    this.lastAccess,
    this.transcriptionStatus,
  });
}
