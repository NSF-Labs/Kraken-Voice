import 'dart:io';
import 'package:krak_en_voice/kernel/inference/model_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:krak_en_voice/kernel/model_storage_helper.dart';

class ModelManager {
  static String get modelFilename => ModelProfile.filename;

  /// Suffix for the temporary partial download file.
  static const String _partSuffix = '.part';

  /// Maximum number of automatic resume attempts when the connection drops.
  static const int _maxRetries = 5;

  /// Delay between retry attempts (increases with each retry).
  static const Duration _baseRetryDelay = Duration(seconds: 3);

  /// Returns the absolute path where the model should be stored.
  Future<String> getModelPath() async {
    final modelsDir = await ModelStorageHelper().getModelsDirectory();
    return '$modelsDir/$modelFilename';
  }

  /// Checks if the model file already exists locally.
  Future<bool> hasModel() async {
    final path = await getModelPath();
    final file = File(path);
    return await file.exists() && await file.length() == ModelProfile.bytes;
  }

  /// Downloads the model from the given [url] and reports progress.
  ///
  /// Uses a `.part` temporary file and HTTP Range headers to support
  /// **resumable downloads**. If the connection drops (e.g. when the app is
  /// backgrounded and Android kills the socket), the download will
  /// automatically retry up to [_maxRetries] times, picking up from where
  /// it left off.
  Future<void> downloadModel(
    String url, {
    required Function(double progress, String sizeStr) onProgress,
    CancelToken? cancelToken,
  }) async {
    final finalPath = await getModelPath();
    final partPath = '$finalPath$_partSuffix';
    final partFile = File(partPath);

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 30),
        ),
      );

      try {
        // Check how much we already have from a previous partial download.
        int existingBytes = 0;
        if (await partFile.exists()) {
          existingBytes = await partFile.length();
          debugPrint(
            '[ModelManager] Resuming download from ${(existingBytes / 1024 / 1024).toStringAsFixed(1)} MB '
            '(attempt ${attempt + 1}/${_maxRetries + 1})',
          );
        }

        // Build headers for resumable download.
        final headers = <String, dynamic>{};
        if (existingBytes > 0) {
          headers['Range'] = 'bytes=$existingBytes-';
        }

        await dio.download(
          url,
          partPath,
          cancelToken: cancelToken,
          deleteOnError: false, // Keep partial file for resume
          options: Options(headers: headers),
          onReceiveProgress: (received, total) {
            // `received` is bytes received in THIS request.
            // `total` is the remaining content length (-1 if unknown).
            final totalReceived = existingBytes + received;
            final fullSize = total != -1 ? existingBytes + total : -1;

            if (fullSize > 0) {
              final progress = totalReceived / fullSize;
              final sizeStr =
                  '${(totalReceived / 1024 / 1024).toStringAsFixed(1)} MB / '
                  '${(fullSize / 1024 / 1024).toStringAsFixed(1)} MB';
              onProgress(progress, sizeStr);
            } else {
              final sizeStr =
                  '${(totalReceived / 1024 / 1024).toStringAsFixed(1)} MB downloaded';
              onProgress(0.0, sizeStr);
            }
          },
        );

        // Download complete — rename .part → final path.
        final finalFile = File(finalPath);
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        await partFile.rename(finalPath);

        debugPrint('[ModelManager] Download complete: $finalPath');
        return; // Success — exit the retry loop.
      } on DioException catch (e) {
        // If user cancelled, don't retry — propagate immediately.
        if (cancelToken?.isCancelled == true) {
          rethrow;
        }

        // Connection-drop errors are retryable.
        final isRetryable =
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.unknown;

        if (isRetryable && attempt < _maxRetries) {
          final delay = _baseRetryDelay * (attempt + 1);
          debugPrint(
            '[ModelManager] Connection lost, retrying in ${delay.inSeconds}s '
            '(attempt ${attempt + 1}/$_maxRetries): $e',
          );
          await Future.delayed(delay);
          continue; // Retry with resume.
        }

        // Out of retries or non-retryable error — clean up and fail.
        if (await partFile.exists()) {
          await partFile.delete();
        }
        throw Exception('Failed to download model: $e');
      } catch (e) {
        // Non-Dio errors — clean up and fail immediately.
        if (await partFile.exists()) {
          await partFile.delete();
        }
        throw Exception('Failed to download model: $e');
      }
    }
  }

  /// Deletes the local model file if it exists.
  Future<void> deleteModel() async {
    final path = await getModelPath();
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    // Also clean up any partial download.
    final partFile = File('$path$_partSuffix');
    if (await partFile.exists()) {
      await partFile.delete();
    }
  }
}
