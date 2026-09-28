import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'diarizer.dart';

/// Persists and loads speaker embeddings to/from disk.
///
/// Embeddings are stored as JSON sidecar files alongside the audio.
/// Format: `{ "version", "model", "segments": [ {...} ] }`
///
/// Version history:
///   • v1 — TitanNet Small embeddings (192-dim). No model field.
///   • v2 — current. Records the embedding model name so downstream
///     reads can detect cross-model staleness and force a re-extraction.
///
/// JSON+gzip was considered but the overhead of raw floats in JSON is
/// acceptable for typical recording lengths.
class EmbeddingCache {
  /// Current cache schema version.
  static const int currentVersion = 2;

  /// Identifier for the current embedding model. Bump when swapping
  /// to a model whose vector dimension or learned space differs.
  static const String currentModel = 'campplus_en_voxceleb_v1';

  /// Saves segment embeddings to [path].
  Future<void> save(String path, List<SegmentEmbedding> embeddings) async {
    final json = {
      'version': currentVersion,
      'model': currentModel,
      'count': embeddings.length,
      'segments': embeddings.map((e) => e.toJson()).toList(),
    };
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(json));
    debugPrint('[EmbeddingCache] Saved ${embeddings.length} segment embeddings '
        'to $path (${await file.length()} bytes, model=$currentModel)');
  }

  /// Loads cached segment embeddings from [path].
  ///
  /// Returns null if the cache file doesn't exist, is corrupted, or
  /// was produced by a different embedding model (in which case the
  /// stale file is also deleted so the next pipeline pass regenerates
  /// it with the current model).
  Future<List<SegmentEmbedding>?> load(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      debugPrint('[EmbeddingCache] No cache at $path');
      return null;
    }

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      final version = json['version'] as int?;
      final model = json['model'] as String?;
      if (version != currentVersion || model != currentModel) {
        debugPrint('[EmbeddingCache] Stale cache at $path '
            '(version=$version, model=$model — expected '
            '$currentVersion / $currentModel). Deleting.');
        try {
          await file.delete();
        } catch (_) {}
        return null;
      }

      final segments = (json['segments'] as List<dynamic>)
          .map((s) => SegmentEmbedding.fromJson(s as Map<String, dynamic>))
          .toList();

      debugPrint('[EmbeddingCache] Loaded ${segments.length} segment embeddings '
          'from $path');
      return segments;
    } catch (e) {
      debugPrint('[EmbeddingCache] Failed to load cache from $path: $e');
      return null;
    }
  }

  /// Deletes cached embeddings at [path] if they exist.
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      debugPrint('[EmbeddingCache] Deleted cache at $path');
    }
  }

  /// Returns true if a cache file exists at [path].
  Future<bool> exists(String path) => File(path).exists();
}
