import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:krak_en_voice/kernel/vault/vault_service.dart';
import 'package:krak_en_voice/data/recording_repository.dart';

/// Handles audio retention policy enforcement and storage cap management.
///
/// Two-phase sweep on app launch:
/// 1. **Policy sweep** — delete audio for recordings past their retention window
/// 2. **Cap sweep** — enforce 2 GB storage cap (LRU-first)
///
/// Transcripts, summaries, and metadata are always preserved.
class RetentionService {
  final VaultService _vault;

  // ── Configuration ──
  static const int maxStorageBytes = 2 * 1024 * 1024 * 1024; // 2 GB
  static const int ninetyDaysMs = 90 * 24 * 60 * 60 * 1000;  // 90 days

  /// Live storage tracking for Settings UI.
  final ValueNotifier<int> currentStorageBytes = ValueNotifier(0);

  Timer? _dailySweepTimer;

  RetentionService(this._vault);

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Run the full retention pass. Call once after vault unlock.
  Future<RetentionSweepResult> runSweep() async {
    if (!_vault.isOpen) return RetentionSweepResult();
    
    final result = RetentionSweepResult();
    final repo = FolderRepository(_vault);

    // ── Phase 1: Policy-based sweep ──
    final candidates = await repo.getRetentionCandidates();
    final now = DateTime.now();

    for (final rec in candidates) {
      bool shouldDelete = false;

      switch (rec.retentionPolicy) {
        case 'delete_after_transcription':
          // Failed jobs still need their source audio for retry.
          if (rec.transcriptionStatus == 'completed') {
            shouldDelete = true;
          }
          break;

        case '90_day':
          // H3-14: Use last_access for age, falling back to created_at
          final referenceDate = rec.lastAccess ?? rec.createdAt;
          final ageMs = now.difference(referenceDate).inMilliseconds;
          if (ageMs > ninetyDaysMs) {
            shouldDelete = true;
          }
          break;

        case 'keep_forever':
          // Never auto-delete via policy (still subject to cap)
          break;
      }

      if (shouldDelete) {
        final bytes = await _deleteAudioFile(rec.audioPath);
        if (bytes > 0) {
          await repo.markAudioDeleted(rec.id, 'retention_policy');
          result.policyDeletions++;
          result.bytesFreed += bytes;
        }
      }
    }

    // ── Phase 2: Storage cap enforcement ──
    final capResult = await _enforceStorageCap(repo);
    result.capDeletions = capResult.deletions;
    result.bytesFreed += capResult.bytesFreed;

    // Update live storage counter
    await refreshStorageUsage();

    debugPrint('[Retention] Sweep complete: '
        '${result.policyDeletions} policy, '
        '${result.capDeletions} cap, '
        '${(result.bytesFreed / (1024 * 1024)).toStringAsFixed(1)} MB freed');

    return result;
  }

  /// H3-08: Start a daily background sweep timer.
  /// Call once at app startup after the initial sweep.
  void startDailySweep() {
    _dailySweepTimer?.cancel();
    _dailySweepTimer = Timer.periodic(const Duration(hours: 24), (_) {
      debugPrint('[Retention] Daily sweep triggered');
      runSweep();
    });
    debugPrint('[Retention] Daily sweep scheduler started');
  }

  /// Stop the daily sweep timer (call on dispose).
  void stopDailySweep() {
    _dailySweepTimer?.cancel();
    _dailySweepTimer = null;
  }

  /// Enforce storage cap after a new recording is saved.
  /// Pass the new file's path to exclude it from deletion.
  Future<void> enforceStorageCap({String? excludeAudioPath}) async {
    if (!_vault.isOpen) return;
    final repo = FolderRepository(_vault);
    await _enforceStorageCap(repo, excludeAudioPath: excludeAudioPath);
    await refreshStorageUsage();
  }

  /// Recalculate total audio storage (for Settings UI).
  Future<void> refreshStorageUsage() async {
    if (!_vault.isOpen) return;
    final repo = FolderRepository(_vault);
    int total = 0;
    final recordings = await repo.getRecordingsWithAudioForCap();
    for (final row in recordings) {
      final file = File(row['audio_path'] as String);
      if (await file.exists()) {
        total += await file.length();
      }
    }
    currentStorageBytes.value = total;
  }

  /// H3-62: Cancel any active transcription job, then delete the recording.
  /// Returns true if deletion succeeded.
  Future<bool> cancelAndDelete(FolderRepository repo, String recordingId) async {
    if (!_vault.isOpen) return false;
    try {
      // Step 1: Look up the recording's audio path
      final rows = await _vault.db.query(
        'recordings',
        columns: ['audio_path'],
        where: 'id = ?',
        whereArgs: [recordingId],
      );
      if (rows.isEmpty) return false;
      final audioPath = rows.first['audio_path'] as String;

      // Step 2: Cancel any pending/processing transcription job
      await _vault.db.delete(
        'transcription_jobs',
        where: 'audio_path = ? AND status IN (?, ?)',
        whereArgs: [audioPath, 'pending', 'processing'],
      );

      // Step 3: Delete the audio file
      final file = File(audioPath);
      if (await file.exists()) {
        await file.delete();
      }

      // Step 4: Delete the recording row (cascades to tags, action items)
      await _vault.db.delete(
        'recordings',
        where: 'id = ?',
        whereArgs: [recordingId],
      );

      await refreshStorageUsage();
      return true;
    } catch (e) {
      debugPrint('[Retention] cancelAndDelete failed: $e');
      return false;
    }
  }

  // ─── Internal ──────────────────────────────────────────────────────────────

  Future<_CapResult> _enforceStorageCap(
    FolderRepository repo, {
    String? excludeAudioPath,
  }) async {
    final recordings = await repo.getRecordingsWithAudioForCap();

    // Build file inventory
    final entries = <_AudioEntry>[];
    int totalBytes = 0;

    for (final row in recordings) {
      final path = row['audio_path'] as String;
      if (path == excludeAudioPath) continue; // protect active recording

      final file = File(path);
      if (await file.exists()) {
        final size = await file.length();
        totalBytes += size;
        entries.add(_AudioEntry(
          id: row['id'] as String,
          path: path,
          // H3-14: Use last_access for LRU ordering
          sortKey: (row['last_access'] ?? row['created_at']) as int,
          sizeBytes: size,
        ));
      }
    }

    // Sort by LRU (least recently accessed first)
    entries.sort((a, b) => a.sortKey.compareTo(b.sortKey));

    int deletions = 0;
    int bytesFreed = 0;

    while (totalBytes > maxStorageBytes && entries.isNotEmpty) {
      final oldest = entries.removeAt(0);
      final deleted = await _deleteAudioFile(oldest.path);
      if (deleted > 0) {
        await repo.markAudioDeleted(oldest.id, 'storage_cap');
        totalBytes -= oldest.sizeBytes;
        bytesFreed += oldest.sizeBytes;
        deletions++;
      }
    }

    return _CapResult(deletions: deletions, bytesFreed: bytesFreed);
  }

  /// Delete audio file from disk. Returns bytes freed, or 0 on failure.
  Future<int> _deleteAudioFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final size = await file.length();
        await file.delete();

        // Audit log
        if (_vault.isOpen) {
          await _vault.logAudit(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            operation: 'retention_delete_audio',
            outcome: path,
          );
        }

        return size;
      }
    } catch (e) {
      debugPrint('[Retention] Failed to delete $path: $e');
    }
    return 0;
  }
}

// ─── Supporting types ────────────────────────────────────────────────────────

class RetentionSweepResult {
  int policyDeletions = 0;
  int capDeletions = 0;
  int bytesFreed = 0;
}

class _CapResult {
  final int deletions;
  final int bytesFreed;
  _CapResult({required this.deletions, required this.bytesFreed});
}

class _AudioEntry {
  final String id;
  final String path;
  final int sortKey; // last_access or created_at epoch ms
  final int sizeBytes;

  _AudioEntry({
    required this.id,
    required this.path,
    required this.sortKey,
    required this.sizeBytes,
  });
}
