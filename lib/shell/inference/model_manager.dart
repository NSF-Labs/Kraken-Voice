import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class ModelManager {
  static const String modelFilename = 'gemma4.litertlm';

  /// Returns the absolute path where the model should be stored.
  Future<String> getModelPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$modelFilename';
  }

  /// Checks if the model file already exists locally.
  Future<bool> hasModel() async {
    final path = await getModelPath();
    final file = File(path);
    return await file.exists();
  }

  /// Downloads the model from the given [url] and reports progress.
  Future<void> downloadModel(
    String url, {
    required Function(double progress, String sizeStr) onProgress,
  }) async {
    final path = await getModelPath();
    final dio = Dio();

    try {
      await dio.download(
        url,
        path,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            final sizeStr =
                '${(received / 1024 / 1024).toStringAsFixed(1)} MB / ${(total / 1024 / 1024).toStringAsFixed(1)} MB';
            onProgress(progress, sizeStr);
          } else {
            // If total size is unknown
            final sizeStr =
                '${(received / 1024 / 1024).toStringAsFixed(1)} MB downloaded';
            onProgress(0.0, sizeStr);
          }
        },
      );
    } catch (e) {
      // If download fails, ensure we don't leave a corrupted partial file
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      throw Exception('Failed to download model: $e');
    }
  }

  /// Deletes the local model file if it exists.
  Future<void> deleteModel() async {
    final path = await getModelPath();
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
