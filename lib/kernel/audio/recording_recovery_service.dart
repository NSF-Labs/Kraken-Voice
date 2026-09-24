import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:krak_en_voice/kernel/vault/vault_service.dart';
import 'package:krak_en_voice/data/recording_repository.dart';

/// Recovers orphaned audio files that exist on disk but have no vault entry.
///
/// This can happen when:
/// - The app crashes mid-recording (audio file written by native, Dart never persisted)
/// - A hot-reload during development drops state
/// - The native service stopped but the stop callback never reached Flutter
///
/// Called on vault unlock, this service scans the recordings directory and
/// creates vault entries for any unregistered `.m4a` or `.wav` files.
class RecordingRecoveryService {
  final VaultService _vault;

  final Future<Directory> Function() _documentsDirectory;
  final Future<Directory> Function() _temporaryDirectory;

  RecordingRecoveryService(
    this._vault, {
    Future<Directory> Function()? documentsDirectory,
    Future<Directory> Function()? temporaryDirectory,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  /// Preserve recordings created by versions that recorded into Android cache.
  /// Run before transcription/retention workers start using the stored paths.
  Future<void> migrateLegacyCacheRecordings() async {
    if (!_vault.isOpen) return;
    try {
      await _migrateLegacyCacheRecordings();
    } catch (e) {
      // Storage errors must not prevent access to the rest of the vault.
      debugPrint('[Recovery] Cache migration deferred: $e');
    }
  }

  Future<void> _migrateLegacyCacheRecordings() async {
    final cacheDir = await _temporaryDirectory();
    final docsDir = await _documentsDirectory();
    final recordingsDir = Directory(p.join(docsDir.path, 'recordings'));
    await recordingsDir.create(recursive: true);
    final knownPaths = await _getKnownAudioPaths();

    await for (final entry in cacheDir.list()) {
      if (entry is! File ||
          !RegExp(r'^temp_audio_\d+\.m4a$').hasMatch(p.basename(entry.path))) {
        continue;
      }
      final target = File(p.join(recordingsDir.path, p.basename(entry.path)));
      try {
        // A previous launch may have committed the move before removing cache.
        if (!knownPaths.contains(target.path) || !await target.exists()) {
          final partial = await entry.copy('${target.path}.part');
          await partial.rename(target.path);
          await _vault.db.transaction((txn) async {
            for (final table in [
              'recordings',
              'transcription_jobs',
              'summary_versions',
            ]) {
              await txn.update(
                table,
                {'audio_path': target.path},
                where: 'audio_path = ?',
                whereArgs: [entry.path],
              );
            }
          });
        }
        // Only remove the original after the persistent copy and DB commit.
        await entry.delete();
        final breadcrumb = File('${entry.path}.recording');
        if (await breadcrumb.exists()) await breadcrumb.delete();
      } catch (e) {
        debugPrint('[Recovery] Could not migrate ${entry.path}: $e');
        // Do not recover a second entry if the database transaction failed.
        if (knownPaths.contains(entry.path) && await entry.exists()) {
          final currentPaths = await _getKnownAudioPaths();
          if (!currentPaths.contains(target.path) && await target.exists()) {
            await target.delete();
          }
        }
      }
    }
  }

  /// Scans the app's file storage for audio files without vault entries.
  /// Returns the number of recordings recovered.
  Future<int> recoverOrphanedRecordings() async {
    if (!_vault.isOpen) return 0;

    try {
      final docsDir = await _documentsDirectory();
      final recordingsDir = Directory('${docsDir.path}/recordings');

      if (!await recordingsDir.exists()) return 0;

      // Get all known audio paths from the vault
      final knownPaths = await _getKnownAudioPaths();

      // Scan for audio files
      final audioFiles = await recordingsDir
          .list(recursive: true)
          .where((entity) => entity is File)
          .cast<File>()
          .where((file) {
            final ext = file.path.split('.').last.toLowerCase();
            return ext == 'm4a' || ext == 'wav' || ext == 'mp3' || ext == 'aac';
          })
          .toList();

      int recoveredCount = 0;
      final folderRepo = FolderRepository(_vault);

      for (final file in audioFiles) {
        if (knownPaths.contains(file.path)) continue;

        // Check file is substantial (> 4KB, to skip corrupt/empty files)
        final size = await file.length();
        if (size < 4096) {
          debugPrint('[Recovery] Skipping tiny file (${size}B): ${file.path}');
          continue;
        }

        // A user may reopen the app weeks after a crash; age is not a reason
        // to discard a recoverable recording.
        final stat = await file.stat();

        // Recover: create a vault entry
        final modified = stat.modified;
        final title =
            'Recovered ${modified.month}/${modified.day} '
            '${modified.hour.toString().padLeft(2, '0')}:'
            '${modified.minute.toString().padLeft(2, '0')}';

        // Estimate duration from file size (~16KB/s for m4a at 128kbps)
        final estimatedDurationMs = (size / 16000 * 1000).round().clamp(
          1000,
          18000000,
        );

        await folderRepo.createRecording(
          title: title,
          audioPath: file.path,
          durationMs: estimatedDurationMs,
          source: 'recovered',
        );

        recoveredCount++;
        debugPrint('[Recovery] ✅ Recovered orphan: ${file.path} → "$title"');
      }

      if (recoveredCount > 0) {
        debugPrint(
          '[Recovery] Recovered $recoveredCount orphaned recording(s)',
        );
      }

      return recoveredCount;
    } catch (e) {
      debugPrint('[Recovery] ❌ Recovery scan failed: $e');
      return 0;
    }
  }

  /// Returns all audio paths currently registered in the vault.
  Future<Set<String>> _getKnownAudioPaths() async {
    final results = await _vault.db.query(
      'recordings',
      columns: ['audio_path'],
    );
    return results.map((r) => r['audio_path'] as String).toSet();
  }

  /// Cleans up breadcrumb files left by completed or abandoned recording sessions.
  /// A breadcrumb is a `.recording` sidecar file written when recording starts.
  Future<void> cleanupBreadcrumbs() async {
    try {
      final docsDir = await _documentsDirectory();
      final recordingsDir = Directory('${docsDir.path}/recordings');
      if (!await recordingsDir.exists()) return;

      final breadcrumbs = await recordingsDir
          .list()
          .where(
            (entity) => entity is File && entity.path.endsWith('.recording'),
          )
          .cast<File>()
          .toList();

      for (final bc in breadcrumbs) {
        await bc.delete();
      }

      if (breadcrumbs.isNotEmpty) {
        debugPrint('[Recovery] Cleaned ${breadcrumbs.length} breadcrumb(s)');
      }
    } catch (_) {}
  }
}
