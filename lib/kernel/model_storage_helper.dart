import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Provides a shared model storage directory that multiple Kraken-family
/// apps can read from, avoiding duplicate 2.5 GB downloads.
///
/// Storage locations (in priority order):
///
/// 1. **Android (shared)**: `/storage/emulated/0/Documents/KrakenModels/`
///    — Visible in the user's Documents folder.
///    — Survives app reinstalls and is accessible to all Kraken apps.
///    — Requires `MANAGE_EXTERNAL_STORAGE` on Android 11+.
///
/// 2. **Android (fallback)**: `Android/data/<pkg>/files/models/`
///    — App-scoped external storage, used if shared permission is denied.
///
/// 3. **iOS / other**: `getApplicationDocumentsDirectory()/models/`
class ModelStorageHelper {
  // Singleton
  static final ModelStorageHelper _instance = ModelStorageHelper._internal();
  factory ModelStorageHelper() => _instance;
  ModelStorageHelper._internal();

  String? _cachedPath;

  /// Well-known directory name shared across all Kraken-family apps.
  static const String _sharedDirName = 'KrakenModels';

  /// Returns the base directory for model storage.
  /// Creates the directory if it doesn't exist.
  Future<String> getModelsDirectory() async {
    if (_cachedPath != null) return _cachedPath!;

    Directory? dir;

    if (Platform.isAndroid) {
      // Try shared public Documents location first
      dir = await _getSharedDirectory();

      // Fallback: app-scoped external storage
      if (dir == null) {
        try {
          final extDir = await getExternalStorageDirectory();
          if (extDir != null) {
            dir = Directory('${extDir.path}/models');
          }
        } catch (e) {
          debugPrint('[ModelStorage] External storage unavailable: $e');
        }
      }
    }

    // Final fallback: internal app documents
    dir ??= Directory('${(await getApplicationDocumentsDirectory()).path}/models');

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    _cachedPath = dir.path;
    debugPrint('[ModelStorage] Models directory: $_cachedPath');
    return _cachedPath!;
  }

  /// Returns the shared public directory, or null if permission is denied.
  Future<Directory?> _getSharedDirectory() async {
    try {
      // On Android 11+ (API 30+), we need MANAGE_EXTERNAL_STORAGE
      // to write to public Documents. Check if we already have it.
      final status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        debugPrint('[ModelStorage] Shared storage permission not granted, '
            'using app-scoped fallback.');
        return null;
      }

      // /storage/emulated/0/Documents/KrakenModels/
      final docsDir = Directory('/storage/emulated/0/Documents/$_sharedDirName');
      if (!await docsDir.exists()) {
        await docsDir.create(recursive: true);
      }
      return docsDir;
    } catch (e) {
      debugPrint('[ModelStorage] Failed to access shared directory: $e');
      return null;
    }
  }

  /// Requests the MANAGE_EXTERNAL_STORAGE permission for shared model access.
  /// Returns true if permission was granted.
  ///
  /// Call this during onboarding before the first download so the model
  /// lands in the shared location from the start.
  Future<bool> requestSharedStoragePermission() async {
    if (!Platform.isAndroid) return false;

    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) {
      // Invalidate cache so next call to getModelsDirectory() re-resolves
      _cachedPath = null;
      debugPrint('[ModelStorage] Shared storage permission granted.');
      return true;
    }

    debugPrint('[ModelStorage] Shared storage permission denied: $status');
    return false;
  }

  /// Whether we are currently using the shared public directory.
  Future<bool> isUsingSharedStorage() async {
    final path = await getModelsDirectory();
    return path.contains(_sharedDirName);
  }

  /// Migrates models from any legacy location to the current preferred
  /// directory. Safe to call multiple times — only copies if source exists
  /// and destination doesn't.
  Future<void> migrateIfNeeded() async {
    if (!Platform.isAndroid) return;

    final currentDir = await getModelsDirectory();

    // Potential old locations to migrate from
    final oldLocations = <String>[];

    // Old internal app documents
    try {
      final appDocs = await getApplicationDocumentsDirectory();
      oldLocations.add(appDocs.path);
    } catch (_) {}

    // Old app-scoped external storage
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        oldLocations.add('${extDir.path}/models');
      }
    } catch (_) {}

    for (final oldBase in oldLocations) {
      // Don't migrate from our own current directory
      if (currentDir.startsWith(oldBase) || oldBase.startsWith(currentDir)) {
        continue;
      }

      // Migrate Gemma model
      await _migrateFile(
        '$oldBase/gemma4.litertlm',
        '$currentDir/gemma4.litertlm',
      );

      // Migrate diarization models
      final oldDiarDir = Directory('$oldBase/diarization_models');
      final newDiarDir = Directory('$currentDir/diarization_models');
      if (await oldDiarDir.exists() && !await newDiarDir.exists()) {
        debugPrint('[ModelStorage] Migrating diarization models from $oldBase...');
        await _copyDirectory(oldDiarDir, newDiarDir);
        debugPrint('[ModelStorage] Diarization migration complete.');
      }
    }
  }

  Future<void> _migrateFile(String oldPath, String newPath) async {
    final oldFile = File(oldPath);
    final newFile = File(newPath);
    if (await oldFile.exists() && !await newFile.exists()) {
      debugPrint('[ModelStorage] Migrating: $oldPath → $newPath');
      await newFile.parent.create(recursive: true);
      await oldFile.copy(newPath);
      debugPrint('[ModelStorage] Migration complete for ${oldFile.path}');
    }
  }

  Future<void> _copyDirectory(Directory source, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      if (entity is File) {
        final destPath = '${dest.path}/${entity.uri.pathSegments.last}';
        await entity.copy(destPath);
      } else if (entity is Directory) {
        final newSubDir = Directory('${dest.path}/${entity.uri.pathSegments[entity.uri.pathSegments.length - 2]}');
        await _copyDirectory(entity, newSubDir);
      }
    }
  }
}
